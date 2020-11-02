// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "./spec_interfaces/IElections.sol";
import "./spec_interfaces/IDelegations.sol";
import "./spec_interfaces/IGuardiansRegistration.sol";
import "./spec_interfaces/ICommittee.sol";
import "./spec_interfaces/ICertification.sol";
import "./ManagedContract.sol";

/// @title Elections contract
contract Elections is IElections, ManagedContract {
	using SafeMath for uint256;

	uint32 constant PERCENT_MILLIE_BASE = 100000;

	mapping(address => mapping(address => uint256)) voteUnreadyVotes; // by => to => expiration
	mapping(address => uint256) public votersStake;
	mapping(address => address) voteOutVotes; // by => to
	mapping(address => uint256) accumulatedStakesForVoteOut; // addr => total stake
	mapping(address => bool) votedOutGuardians;

	struct Settings {
		uint32 minSelfStakePercentMille;
		uint32 voteUnreadyPercentMilleThreshold;
		uint32 voteOutPercentMilleThreshold;
	}
	Settings settings;

    /// Constructor
    /// @param _contractRegistry is the contract registry address
    /// @param _registryAdmin is the registry admin address
	/// @param minSelfStakePercentMille is the minimum self stake in percent-mille (0-100,000) 
	/// @param voteUnreadyPercentMilleThreshold is the minimum vote-unready threshold in percent-mille (0-100,000)
	/// @param voteOutPercentMilleThreshold is the minimum vote-out threshold in percent-mille (0-100,000)
	constructor(IContractRegistry _contractRegistry, address _registryAdmin, uint32 minSelfStakePercentMille, uint32 voteUnreadyPercentMilleThreshold, uint32 voteOutPercentMilleThreshold) ManagedContract(_contractRegistry, _registryAdmin) public {
		setMinSelfStakePercentMille(minSelfStakePercentMille);
		setVoteOutPercentMilleThreshold(voteOutPercentMilleThreshold);
		setVoteUnreadyPercentMilleThreshold(voteUnreadyPercentMilleThreshold);
	}

	modifier onlyDelegationsContract() {
		require(msg.sender == address(delegationsContract), "caller is not the delegations contract");

		_;
	}

	modifier onlyGuardiansRegistrationContract() {
		require(msg.sender == address(guardianRegistrationContract), "caller is not the guardian registrations contract");

		_;
	}

	modifier onlyCertificationContract() {
		require(msg.sender == address(certificationContract), "caller is not the certification contract");

		_;
	}

	/*
	 * External functions
	 */

	/// Notifies that the guardian is ready to sync with other nodes
	/// @dev ready to sync state is not managed in the contract that only emits an event
	/// @dev readyToSync clears the readyForCommittee state
	function readyToSync() external override onlyWhenActive {
		address guardian = guardianRegistrationContract.resolveGuardianAddress(msg.sender); // this validates registration
		require(!isVotedOut(guardian), "caller is voted-out");

		emit GuardianStatusUpdated(guardian, true, false);

		committeeContract.removeMember(guardian);
	}

	/// Notifies that the guardian is ready to join the committee
	/// @dev a qualified guardian calling readyForCommittee is added to the committee
	function readyForCommittee() external override onlyWhenActive {
		_readyForCommittee(msg.sender);
	}

	/// Checks if a guardian is qualified to join the committee
	/// @dev when true, calling readyForCommittee() will result in adding the guardian to the committee
	/// @dev called periodically by guardians to check if they are qualified to join the committee
	/// @param guardian is the guardian to check
	/// @return canJoin indicating that the guardian can join the current committee
	function canJoinCommittee(address guardian) external view override returns (bool) {
		guardian = guardianRegistrationContract.resolveGuardianAddress(guardian); // this validates registration

		if (isVotedOut(guardian)) {
			return false;
		}

		uint256 effectiveStake = getGuardianEffectiveStake(guardian, settings);
		return committeeContract.checkAddMember(guardian, effectiveStake);
	}

	/// Returns an address effective stake
	/// The effective stake is derived from a guardian delegate stake and selfs stake  
	/// @return effectiveStake is the guardian's effective stake
	function getEffectiveStake(address guardian) external override view returns (uint effectiveStake) {
		return getGuardianEffectiveStake(guardian, settings);
	}

	/// Returns the current committee along with the guardians' Orbs address and IP
	/// @return committee is a list of the committee members' guardian addresses
	/// @return weights is a list of the committee members' weight (effective stake)
	/// @return orbsAddrs is a list of the committee members' orbs address
	/// @return certification is a list of bool indicating the committee members certification
	/// @return ips is a list of the committee members' ip
	function getCommittee() external override view returns (address[] memory committee, uint256[] memory weights, address[] memory orbsAddrs, bool[] memory certification, bytes4[] memory ips) {
		IGuardiansRegistration _guardianRegistrationContract = guardianRegistrationContract;
		(committee, weights, certification) = committeeContract.getCommittee();
		orbsAddrs = _guardianRegistrationContract.getGuardiansOrbsAddress(committee);
		ips = _guardianRegistrationContract.getGuardianIps(committee);
	}

	// Vote-unready

	/// Casts an unready vote on a subject guardian
	/// @dev Called by a guardian as part of the automatic vote-unready flow
	/// @dev The transaction may be sent from the guardian or orbs address.
	/// @param subject is the subject guardian to vote out
	/// @param voteExpiration is the expiration time of the vote unready to prevent counting of a vote that is already irrelevant.
	function voteUnready(address subject, uint voteExpiration) external override onlyWhenActive {
		require(voteExpiration >= block.timestamp, "vote expiration time must not be in the past");

		address voter = guardianRegistrationContract.resolveGuardianAddress(msg.sender);
		voteUnreadyVotes[voter][subject] = voteExpiration;
		emit VoteUnreadyCasted(voter, subject, voteExpiration);

		(address[] memory generalCommittee, uint256[] memory generalWeights, bool[] memory certification) = committeeContract.getCommittee();

		bool votedUnready = isCommitteeVoteUnreadyThresholdReached(generalCommittee, generalWeights, certification, subject);
		if (votedUnready) {
			clearCommitteeUnreadyVotes(generalCommittee, subject);
			emit GuardianVotedUnready(subject);

			emit GuardianStatusUpdated(subject, false, false);
			committeeContract.removeMember(subject);
		}
	}

	/// Returns the current vote unready vote for a voter and a subject pair
	/// @param voter is the voting guardian address
	/// @param subject is the subject guardian address
	/// @return valid indicates whether there is a valid vote
	/// @return expiration returns the votes expiration time
	function getVoteUnreadyVote(address voter, address subject) public override view returns (bool valid, uint256 expiration) {
		expiration = voteUnreadyVotes[voter][subject];
		valid = expiration != 0 && block.timestamp < expiration;
	}

	/// Returns the current vote-unready status of a subject guardian.
	/// @dev the committee and certification data is used to check the certified and committee threshold
	/// @param subject is the subject guardian address
	/// @return committee is a list of the current committee members
	/// @return weights is a list of the current committee members weight
	/// @return certification is a list of bool indicating the committee members certification
	/// @return votes is a list of bool indicating the members that votes the subject unready
	/// @return subjectInCommittee indicates that the subject is in the committee
	/// @return subjectInCertifiedCommittee indicates that the subject is in the certified committee
	function getVoteUnreadyStatus(address subject) external override view returns (address[] memory committee, uint256[] memory weights, bool[] memory certification, bool[] memory votes, bool subjectInCommittee, bool subjectInCertifiedCommittee) {
		(committee, weights, certification) = committeeContract.getCommittee();

		votes = new bool[](committee.length);
		for (uint i = 0; i < committee.length; i++) {
			address memberAddr = committee[i];
			if (block.timestamp < voteUnreadyVotes[memberAddr][subject]) {
				votes[i] = true;
			}

			if (memberAddr == subject) {
				subjectInCommittee = true;
				subjectInCertifiedCommittee = certification[i];
			}
		}
	}

	// Vote-out

	/// Casts a voteOut vote by the sender to the given address
	/// @dev the transaction is sent from the guardian address
	/// @param subject is the subject guardian address
	function voteOut(address subject) external override onlyWhenActive {
		Settings memory _settings = settings;

		address voter = msg.sender;
		address prevSubject = voteOutVotes[voter];

		voteOutVotes[voter] = subject;
		emit VoteOutCasted(voter, subject);

		uint256 voterStake = delegationsContract.getDelegatedStake(voter);

		if (prevSubject == address(0)) {
			votersStake[voter] = voterStake;
		}

		if (subject == address(0)) {
			delete votersStake[voter];
		}

		uint totalStake = delegationsContract.getTotalDelegatedStake();

		if (prevSubject != address(0) && prevSubject != subject) {
			applyVoteOutVotesFor(prevSubject, 0, voterStake, totalStake, _settings);
		}

		if (subject != address(0)) {
			uint voteStakeAdded = prevSubject != subject ? voterStake : 0;
			applyVoteOutVotesFor(subject, voteStakeAdded, 0, totalStake, _settings); // recheck also if not new
		}
	}

	/// Returns the subject address the addr has voted-out against
	/// @param voter is the voting guardian address
	/// @return subject is the subject the voter has voted out
	function getVoteOutVote(address voter) external override view returns (address) {
		return voteOutVotes[voter];
	}

	/// Returns the governance voteOut status of a guardian.
	/// @dev A guardian is voted out if votedStake / totalDelegatedStake (in percent mille) > threshold
	/// @param subject is the subject guardian address
	/// @return votedOut indicates whether the subject was voted out
	/// @return votedStake is the total stake voting against the subject
	/// @return totalDelegatedStake is the total delegated stake
	function getVoteOutStatus(address subject) external override view returns (bool votedOut, uint votedStake, uint totalDelegatedStake) {
		votedOut = isVotedOut(subject);
		votedStake = accumulatedStakesForVoteOut[subject];
		totalDelegatedStake = delegationsContract.getTotalDelegatedStake();
	}

	/*
	 * Notification functions from other PoS contracts
	 */

	/// Notifies a delegated stake change event
	/// @dev Called by: delegation contract
	/// @param delegate is the delegate to update
	/// @param selfDelegatedStake is the delegate self stake (0 if not self-delegating)
	/// @param delegatedStake is the delegate delegated stake (0 if not self-delegating)
	/// @param totalDelegatedStake is the total delegated stake
	function delegatedStakeChange(address delegate, uint256 selfDelegatedStake, uint256 delegatedStake, uint256 totalDelegatedStake) external override onlyDelegationsContract onlyWhenActive {
		Settings memory _settings = settings;

		uint effectiveStake = calcEffectiveStake(selfDelegatedStake, delegatedStake, _settings);
		emit StakeChanged(delegate, selfDelegatedStake, delegatedStake, effectiveStake);

		committeeContract.memberWeightChange(delegate, effectiveStake);

		applyStakesToVoteOutBy(delegate, delegatedStake, totalDelegatedStake, _settings);
	}

	/// Notifies a new guardian was unregistered
	/// @dev Called by: guardian registration contract
	/// @dev when a guardian unregisters its status is updated to not ready to sync and is removed from the committee
	/// @param guardian is the address of the guardian that unregistered
	function guardianUnregistered(address guardian) external override onlyGuardiansRegistrationContract onlyWhenActive {
		emit GuardianStatusUpdated(guardian, false, false);
		committeeContract.removeMember(guardian);
	}

	/// Notifies on a guardian certification change
	/// @dev Called by: guardian registration contract
	/// @param guardian is the address of the guardian to update
	/// @param isCertified indicates whether the guardian is certified
	function guardianCertificationChanged(address guardian, bool isCertified) external override onlyCertificationContract onlyWhenActive {
		committeeContract.memberCertificationChange(guardian, isCertified);
	}

	/*
     * Governance functions
	 */

	/// Sets the minimum self stake requirement for the effective stake
	/// @dev governance function called only by the functional manager
	/// @param minSelfStakePercentMille is the minimum self stake in percent-mille (0-100,000) 
	function setMinSelfStakePercentMille(uint32 minSelfStakePercentMille) public override onlyFunctionalManager {
		require(minSelfStakePercentMille <= PERCENT_MILLIE_BASE, "minSelfStakePercentMille must be 100000 at most");
		emit MinSelfStakePercentMilleChanged(minSelfStakePercentMille, settings.minSelfStakePercentMille);
		settings.minSelfStakePercentMille = minSelfStakePercentMille;
	}

	/// Returns the minimum self-stake required for the effective stake
	/// @return minSelfStakePercentMille is the minimum self stake in percent-mille 
	function getMinSelfStakePercentMille() external override view returns (uint32) {
		return settings.minSelfStakePercentMille;
	}

	/// Sets the vote-out threshold
	/// @dev governance function called only by the functional manager
	/// @param voteOutPercentMilleThreshold is the minimum threshold in percent-mille (0-100,000)
	function setVoteOutPercentMilleThreshold(uint32 voteOutPercentMilleThreshold) public override onlyFunctionalManager {
		require(voteOutPercentMilleThreshold <= PERCENT_MILLIE_BASE, "voteOutPercentMilleThreshold must not be larger than 100000");
		emit VoteOutPercentMilleThresholdChanged(voteOutPercentMilleThreshold, settings.voteOutPercentMilleThreshold);
		settings.voteOutPercentMilleThreshold = voteOutPercentMilleThreshold;
	}

	/// Returns the vote-out threshold
	/// @return voteOutPercentMilleThreshold is the minimum threshold in percent-mille
	function getVoteOutPercentMilleThreshold() external override view returns (uint32) {
		return settings.voteOutPercentMilleThreshold;
	}

	/// Sets the vote-unready threshold
	/// @dev governance function called only by the functional manager
	/// @param voteUnreadyPercentMilleThreshold is the minimum threshold in percent-mille (0-100,000)
	function setVoteUnreadyPercentMilleThreshold(uint32 voteUnreadyPercentMilleThreshold) public override onlyFunctionalManager {
		require(voteUnreadyPercentMilleThreshold <= PERCENT_MILLIE_BASE, "voteUnreadyPercentMilleThreshold must not be larger than 100000");
		emit VoteUnreadyPercentMilleThresholdChanged(voteUnreadyPercentMilleThreshold, settings.voteUnreadyPercentMilleThreshold);
		settings.voteUnreadyPercentMilleThreshold = voteUnreadyPercentMilleThreshold;
	}

	/// Returns the vote-unready threshold
	/// @return voteUnreadyPercentMilleThreshold is the minimum threshold in percent-mille
	function getVoteUnreadyPercentMilleThreshold() external override view returns (uint32) {
		return settings.voteUnreadyPercentMilleThreshold;
	}

	/// Returns the contract's settings 
	/// @return minSelfStakePercentMille is the minimum self stake in percent-mille
	/// @return voteUnreadyPercentMilleThreshold is the minimum threshold in percent-mille
	/// @return voteOutPercentMilleThreshold is the minimum threshold in percent-mille
	function getSettings() external override view returns (
		uint32 minSelfStakePercentMille,
		uint32 voteUnreadyPercentMilleThreshold,
		uint32 voteOutPercentMilleThreshold
	) {
		Settings memory _settings = settings;
		minSelfStakePercentMille = _settings.minSelfStakePercentMille;
		voteUnreadyPercentMilleThreshold = _settings.voteUnreadyPercentMilleThreshold;
		voteOutPercentMilleThreshold = _settings.voteOutPercentMilleThreshold;
	}

	/// Initializes the ready for committee notification for the committee guardians
	/// @dev governance function called only by the initialization manager during migration 
	/// @dev identical behaviour as if each guardian sent readyForCommittee() 
	/// @param guardians a list of guardians addresses to update
	function initReadyForCommittee(address[] calldata guardians) external override onlyInitializationAdmin {
		for (uint i = 0; i < guardians.length; i++) {
			_readyForCommittee(guardians[i]);
		}
	}

	/*
     * Private functions
	 */


	/// Handles a readyForCommittee notification
	/// @dev may be called with either the guardian address or the guardian's orbs address
	/// @dev notifies the committee contract that will add the guardian if qualified
	/// @param guardian is the guardian ready for committee
	function _readyForCommittee(address guardian) private {
		guardian = guardianRegistrationContract.resolveGuardianAddress(guardian); // this validates registration
		require(!isVotedOut(guardian), "caller is voted-out");

		emit GuardianStatusUpdated(guardian, true, true);

		uint256 effectiveStake = getGuardianEffectiveStake(guardian, settings);
		committeeContract.addMember(guardian, effectiveStake, certificationContract.isGuardianCertified(guardian));
	}

	/// Calculates a guardian effective stake based on its self-stake and delegated stake
	function calcEffectiveStake(uint256 selfStake, uint256 delegatedStake, Settings memory _settings) private pure returns (uint256) {
		if (selfStake.mul(PERCENT_MILLIE_BASE) >= delegatedStake.mul(_settings.minSelfStakePercentMille)) {
			return delegatedStake;
		}
		return selfStake.mul(PERCENT_MILLIE_BASE).div(_settings.minSelfStakePercentMille); // never overflows or divides by zero
	}

	/// Returns the effective state of a guardian 
	/// @dev calls the delegation contract to retrieve the guardian current stake and delegated stake
	/// @param guardian is the guardian to query
	/// @param _settings is the contract settings struct
	/// @return effectiveStake is the guardian's effective stake
	function getGuardianEffectiveStake(address guardian, Settings memory _settings) private view returns (uint256 effectiveStake) {
		IDelegations _delegationsContract = delegationsContract;
		(,uint256 selfStake) = _delegationsContract.getDelegationInfo(guardian);
		uint256 delegatedStake = _delegationsContract.getDelegatedStake(guardian);
		return calcEffectiveStake(selfStake, delegatedStake, _settings);
	}

	// Vote-unready

	/// Checks if the vote unready threshold was reached for a given subject
	/// @dev a subject is voted-unready if either it reaches the threshold in the general committee or a certified subject reaches the threshold in the certified committee
	/// @param committee is a list of the current committee members
	/// @param weights is a list of the current committee members weight
	/// @param certification is a list of bool indicating the committee members certification
	/// @param subject is the subject guardian address
	/// @return thresholdReached is a bool indicating that the threshold was reached
	function isCommitteeVoteUnreadyThresholdReached(address[] memory committee, uint256[] memory weights, bool[] memory certification, address subject) private returns (bool) {
		Settings memory _settings = settings;

		uint256 totalCommitteeStake = 0;
		uint256 totalVoteUnreadyStake = 0;
		uint256 totalCertifiedStake = 0;
		uint256 totalCertifiedVoteUnreadyStake = 0;

		address member;
		uint256 memberStake;
		bool isSubjectCertified;
		for (uint i = 0; i < committee.length; i++) {
			member = committee[i];
			memberStake = weights[i];

			if (member == subject && certification[i]) {
				isSubjectCertified = true;
			}

			totalCommitteeStake = totalCommitteeStake.add(memberStake);
			if (certification[i]) {
				totalCertifiedStake = totalCertifiedStake.add(memberStake);
			}

			(bool valid, uint256 expiration) = getVoteUnreadyVote(member, subject);
			if (valid) {
				totalVoteUnreadyStake = totalVoteUnreadyStake.add(memberStake);
				if (certification[i]) {
					totalCertifiedVoteUnreadyStake = totalCertifiedVoteUnreadyStake.add(memberStake);
				}
			} else if (expiration != 0) {
				// Vote is stale, delete from state
				delete voteUnreadyVotes[member][subject];
			}
		}

		return (
			totalCommitteeStake > 0 &&
			totalVoteUnreadyStake.mul(PERCENT_MILLIE_BASE) >= uint256(_settings.voteUnreadyPercentMilleThreshold).mul(totalCommitteeStake)
		) || (
			isSubjectCertified &&
			totalCertifiedStake > 0 &&
			totalCertifiedVoteUnreadyStake.mul(PERCENT_MILLIE_BASE) >= uint256(_settings.voteUnreadyPercentMilleThreshold).mul(totalCertifiedStake)
		);
	}

	/// Clears the committee members vote-unready state upon declaring a guardian unready
	/// @param committee is a list of the current committee members
	/// @param subject is the subject guardian address
	function clearCommitteeUnreadyVotes(address[] memory committee, address subject) private {
		for (uint i = 0; i < committee.length; i++) {
			voteUnreadyVotes[committee[i]][subject] = 0; // clear vote-outs
		}
	}

	// Vote-out

	/// Updates the vote-out state upon a stake change notification
	/// @param voter is the voter address
	/// @param currentVoterStake is the voter delegated stake
	/// @param totalDelegatedStake is the total delegated stake
	/// @param _settings is the contract settings struct
	function applyStakesToVoteOutBy(address voter, uint256 currentVoterStake, uint256 totalDelegatedStake, Settings memory _settings) private {
		address subject = voteOutVotes[voter];
		if (subject == address(0)) return;

		uint256 prevVoterStake = votersStake[voter];
		votersStake[voter] = currentVoterStake;

		applyVoteOutVotesFor(subject, currentVoterStake, prevVoterStake, totalDelegatedStake, _settings);
	}

	/// Applies updates in a vote-out subject state and checks whether its threshold was reached
	/// @param subject is the vote-out subject
	/// @param voteOutStakeAdded is the added votes against the subject
	/// @param voteOutStakeRemoved is the removed votes against the subject
	/// @param totalDelegatedStake is the total delegated stake used to check the vote-out threshold
	/// @param _settings is the contract settings struct
    function applyVoteOutVotesFor(address subject, uint256 voteOutStakeAdded, uint256 voteOutStakeRemoved, uint256 totalDelegatedStake, Settings memory _settings) private {
		if (isVotedOut(subject)) {
			return;
		}

		uint256 accumulated = accumulatedStakesForVoteOut[subject].
			sub(voteOutStakeRemoved).
			add(voteOutStakeAdded);

		bool shouldBeVotedOut = totalDelegatedStake > 0 && accumulated.mul(PERCENT_MILLIE_BASE) >= uint256(_settings.voteOutPercentMilleThreshold).mul(totalDelegatedStake);
		if (shouldBeVotedOut) {
			votedOutGuardians[subject] = true;
			emit GuardianVotedOut(subject);

			emit GuardianStatusUpdated(subject, false, false);
			committeeContract.removeMember(subject);
		}

		accumulatedStakesForVoteOut[subject] = accumulated;
	}

	/// Checks whether a guardian was voted out
	function isVotedOut(address guardian) private view returns (bool) {
		return votedOutGuardians[guardian];
	}

	/*
     * Contracts topology / registry interface
     */

	ICommittee committeeContract;
	IDelegations delegationsContract;
	IGuardiansRegistration guardianRegistrationContract;
	ICertification certificationContract;

	/// Refreshes the address of the other contracts the contract interacts with
    /// @dev called by the registry contract upon an update of a contract in the registry
	function refreshContracts() external override {
		committeeContract = ICommittee(getCommitteeContract());
		delegationsContract = IDelegations(getDelegationsContract());
		guardianRegistrationContract = IGuardiansRegistration(getGuardiansRegistrationContract());
		certificationContract = ICertification(getCertificationContract());
	}

}
