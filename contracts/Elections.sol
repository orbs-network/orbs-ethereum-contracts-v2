pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "./spec_interfaces/ICommitteeListener.sol";
import "./spec_interfaces/IDelegation.sol";
import "./interfaces/IElections.sol";
import "./spec_interfaces/IGuardiansRegistration.sol";
import "./IStakingContract.sol";
import "./spec_interfaces/ICommittee.sol";
import "./spec_interfaces/ICertification.sol";
import "./ContractRegistryAccessor.sol";
import "./Lockable.sol";
import "./ManagedContract.sol";


contract Elections is IElections, ManagedContract {
	using SafeMath for uint256;

	mapping (address => mapping (address => uint256)) votedUnreadyVotes; // by => to => timestamp
	mapping (address => uint256) votersStake;
	mapping (address => address) voteOutVotes; // by => to
	mapping (address => uint256) accumulatedStakesForVoteOut; // addr => total stake
	mapping (address => bool) votedOutGuardians;

	uint32 constant PERCENT_MILLIE_BASE = 100000;

	struct Settings {
		uint32 minSelfStakePercentMille;
		uint32 voteUnreadyPercentMilleThreshold;
		uint32 voteOutPercentMilleThreshold;
	}
	Settings public settings;

	modifier onlyDelegationsContract() {
		require(msg.sender == address(delegationsContract), "caller is not the delegations contract");

		_;
	}

	modifier onlyGuardiansRegistrationContract() {
		require(msg.sender == address(guardianRegistrationContract), "caller is not the guardian registrations contract");

		_;
	}

	constructor(IContractRegistry _contractRegistry, address _registryAdmin, uint32 minSelfStakePercentMille, uint32 voteUnreadyPercentMilleThreshold, uint32 voteOutPercentMilleThreshold) ManagedContract(_contractRegistry, _registryAdmin) public {
		setMinSelfStakePercentMille(minSelfStakePercentMille);
		setVoteOutPercentMilleThreshold(voteOutPercentMilleThreshold);
		setVoteUnreadyPercentMilleThreshold(voteUnreadyPercentMilleThreshold);
	}

	/// @dev Called by: guardian registration contract
	/// Notifies a new guardian was registered
	function guardianRegistered(address addr) external {}

	/// @dev Called by: guardian registration contract
	/// Notifies a new guardian was unregistered
	function guardianUnregistered(address addr) external onlyGuardiansRegistrationContract {
		emit GuardianStatusUpdated(addr, false, false);
		committeeContract.removeMember(addr);
	}

	/// @dev Called by: guardian registration contract
	/// Notifies on a guardian certification change
	function guardianCertificationChanged(address addr, bool isCertified) external {
		committeeContract.memberCertificationChange(addr, isCertified);
	}

	function requireNotVotedOut(address addr) private view {
		require(!isVotedOut(addr), "caller is voted-out");
	}

	function readyForCommittee() external {
		address guardianAddr = guardianRegistrationContract.resolveGuardianAddress(msg.sender); // this validates registration
		require(!isVotedOut(guardianAddr), "caller is voted-out");

		emit GuardianStatusUpdated(guardianAddr, true, true);
		committeeContract.addMember(guardianAddr, getCommitteeEffectiveStake(guardianAddr, settings), certificationContract.isGuardianCertified(guardianAddr));
	}

	function readyToSync() external {
		address guardianAddr = guardianRegistrationContract.resolveGuardianAddress(msg.sender); // this validates registration
		require(!isVotedOut(guardianAddr), "caller is voted-out");

		emit GuardianStatusUpdated(guardianAddr, true, false);
		committeeContract.removeMember(guardianAddr);
	}

	function clearCommitteeUnreadyVotes(address[] memory committee, address votee) private {
		for (uint i = 0; i < committee.length; i++) {
			votedUnreadyVotes[committee[i]][votee] = 0; // clear vote-outs
		}
	}

	function isCommitteeVoteUnreadyThresholdReached(address[] memory committee, uint256[] memory weights, bool[] memory certification, address votee) private returns (bool) {
		Settings memory _settings = settings;

		uint256 totalCommitteeStake = 0;
		uint256 totalVoteUnreadyStake = 0;
		uint256 totalCertifiedStake = 0;
		uint256 totalCertifiedVoteUnreadyStake = 0;

		address member;
		uint256 memberStake;
		bool isVoteeCertified;
		for (uint i = 0; i < committee.length; i++) {
			member = committee[i];
			memberStake = weights[i];

			if (member == votee && certification[i]) {
				isVoteeCertified = true;
			}

			totalCommitteeStake = totalCommitteeStake.add(memberStake);
			if (certification[i]) {
				totalCertifiedStake = totalCertifiedStake.add(memberStake);
			}

			uint256 expiration = votedUnreadyVotes[member][votee];
			if (expiration != 0) {
				if (now < expiration) {
					// Vote is valid
					totalVoteUnreadyStake = totalVoteUnreadyStake.add(memberStake);
					if (certification[i]) {
						totalCertifiedVoteUnreadyStake = totalCertifiedVoteUnreadyStake.add(memberStake);
					}
				} else {
					// Vote is stale, delete from state
					votedUnreadyVotes[member][votee] = 0;
				}
			}
		}

		return (totalCommitteeStake > 0 && totalVoteUnreadyStake.mul(PERCENT_MILLIE_BASE).div(totalCommitteeStake) >= _settings.voteUnreadyPercentMilleThreshold)
			|| (isVoteeCertified && totalCertifiedStake > 0 && totalCertifiedVoteUnreadyStake.mul(PERCENT_MILLIE_BASE).div(totalCertifiedStake) >= _settings.voteUnreadyPercentMilleThreshold);
	}

	function voteUnready(address subjectAddr, uint voteExpiration) external onlyWhenActive {
		require(voteExpiration >= now, "vote expiration time must not be in the past");
		address sender = guardianRegistrationContract.resolveGuardianAddress(msg.sender);
		votedUnreadyVotes[sender][subjectAddr] = voteExpiration;
		emit VoteUnreadyCasted(sender, subjectAddr, voteExpiration);

		(address[] memory generalCommittee, uint256[] memory generalWeights, bool[] memory certification) = committeeContract.getCommittee();

		bool votedUnready = isCommitteeVoteUnreadyThresholdReached(generalCommittee, generalWeights, certification, subjectAddr);
		if (votedUnready) {
			clearCommitteeUnreadyVotes(generalCommittee, subjectAddr);
			emit GuardianVotedUnready(subjectAddr);
			emit GuardianStatusUpdated(subjectAddr, false, false);
            committeeContract.removeMember(subjectAddr);
		}
	}

	function voteOut(address subject) external onlyWhenActive {
		Settings memory _settings = settings;

		address prevSubject = voteOutVotes[msg.sender];
		voteOutVotes[msg.sender] = subject;

		uint256 voterStake = delegationsContract.getDelegatedStakes(msg.sender);

		if (prevSubject == address(0)) {
			votersStake[msg.sender] = voterStake;
		}

		if (subject == address(0)) {
			delete votersStake[msg.sender];
		}

		uint totalStake = delegationsContract.getTotalDelegatedStake();

		if (prevSubject != address(0) && prevSubject != subject) {
			_applyVoteOutVotesFor(prevSubject, 0, voterStake, totalStake, _settings);
		}

		if (subject != address(0)) {
			uint voteStakeAdded = prevSubject != subject ? voterStake : 0;
			_applyVoteOutVotesFor(subject, voteStakeAdded, 0, totalStake, _settings); // recheck also if not new
		}
		emit VoteOutCasted(msg.sender, subject);
	}

	function calcGovernanceEffectiveStake(bool selfDelegating, uint256 totalDelegatedStake) private pure returns (uint256) {
		return selfDelegating ? totalDelegatedStake : 0;
	}

	function getVoteOutVote(address addr) external view returns (address) {
		return voteOutVotes[addr];
	}

	function getAccumulatedStakesForVoteOut(address addr) external view returns (uint256) {
		return accumulatedStakesForVoteOut[addr];
	}

	function _applyStakesToVoteOutBy(address voter, uint256 currentVoterStake, uint256 totalGovernanceStake, Settings memory _settings) private {
		address subjectAddr = voteOutVotes[voter];
		if (subjectAddr == address(0)) return;

		uint256 prevVoterStake = votersStake[voter];
		votersStake[voter] = currentVoterStake;

		_applyVoteOutVotesFor(subjectAddr, currentVoterStake, prevVoterStake, totalGovernanceStake, _settings);
	}

    function _applyVoteOutVotesFor(address subjectAddr, uint256 voteOutStakeAdded, uint256 voteOutStakeRemoved, uint256 totalGovernanceStake, Settings memory _settings) private {
		if (isVotedOut(subjectAddr)) {
			return;
		}

		uint256 accumulated = accumulatedStakesForVoteOut[subjectAddr].
			sub(voteOutStakeRemoved).
			add(voteOutStakeAdded);

		bool shouldBeVotedOut = totalGovernanceStake > 0 && accumulated.mul(PERCENT_MILLIE_BASE).div(totalGovernanceStake) >= _settings.voteOutPercentMilleThreshold;
		if (shouldBeVotedOut) {
			votedOutGuardians[subjectAddr] = true;
			emit GuardianVotedOut(subjectAddr);

			emit GuardianStatusUpdated(subjectAddr, false, false);
			committeeContract.removeMember(subjectAddr);

			accumulated = 0;
		}

		accumulatedStakesForVoteOut[subjectAddr] = accumulated;
	}

	function isVotedOut(address addr) private view returns (bool) {
		return votedOutGuardians[addr];
	}

	function delegatedStakeChange(address addr, uint256 selfStake, uint256 delegatedStake, uint256 totalDelegatedStake) external onlyDelegationsContract onlyWhenActive {
		Settings memory _settings = settings;
		_applyDelegatedStake(addr, selfStake, delegatedStake, _settings);
		_applyStakesToVoteOutBy(addr, delegatedStake, totalDelegatedStake, _settings);
	}

	function _applyDelegatedStake(address addr, uint256 selfStake, uint256 delegatedStake, Settings memory _settings) private {
		uint effectiveStake = getCommitteeEffectiveStake(selfStake, delegatedStake, _settings);
		emit StakeChanged(addr, selfStake, delegatedStake, effectiveStake);

		committeeContract.memberWeightChange(addr, effectiveStake);
	}

	function getEffectiveStake(address addr) external view returns (uint effectiveStake) {
		return getCommitteeEffectiveStake(addr, settings);
	}

	function getCommitteeEffectiveStake(uint256 selfStake, uint256 delegatedStake, Settings memory _settings) private pure returns (uint256) {
		if (selfStake.mul(PERCENT_MILLIE_BASE) >= delegatedStake.mul(_settings.minSelfStakePercentMille)) {
			return delegatedStake;
		}

		return selfStake.mul(PERCENT_MILLIE_BASE).div(_settings.minSelfStakePercentMille); // never overflows or divides by zero
	}

	function getCommitteeEffectiveStake(address v, Settings memory _settings) private view returns (uint256) {
		return getCommitteeEffectiveStake(stakingContract.getStakeBalanceOf(v), delegationsContract.getDelegatedStakes(v), _settings);
	}

	function removeMemberFromCommittees(address addr) private {
		committeeContract.removeMember(addr);
	}

	function setMinSelfStakePercentMille(uint32 minSelfStakePercentMille) public onlyFunctionalManager {
		require(minSelfStakePercentMille <= PERCENT_MILLIE_BASE, "minSelfStakePercentMille must be 100000 at most");
		emit MinSelfStakePercentMilleChanged(minSelfStakePercentMille, settings.minSelfStakePercentMille);
		settings.minSelfStakePercentMille = minSelfStakePercentMille;
	}

	function setVoteOutPercentMilleThreshold(uint32 voteOutPercentMilleThreshold) public onlyFunctionalManager {
		require(voteOutPercentMilleThreshold <= PERCENT_MILLIE_BASE, "voteOutPercentMilleThreshold must not be larger than 100000");
		emit VoteOutPercentMilleThresholdChanged(voteOutPercentMilleThreshold, settings.voteOutPercentMilleThreshold);
		settings.voteOutPercentMilleThreshold = voteOutPercentMilleThreshold;
	}

	function setVoteUnreadyPercentMilleThreshold(uint32 voteUnreadyPercentMilleThreshold) public onlyFunctionalManager {
		require(voteUnreadyPercentMilleThreshold <= PERCENT_MILLIE_BASE, "voteUnreadyPercentMilleThreshold must not be larger than 100000");
		emit VoteUnreadyPercentMilleThresholdChanged(voteUnreadyPercentMilleThreshold, settings.voteUnreadyPercentMilleThreshold);
		settings.voteUnreadyPercentMilleThreshold = voteUnreadyPercentMilleThreshold;
	}

	function getMinSelfStakePercentMille() external view returns (uint32) {
		return settings.minSelfStakePercentMille;
	}

	function getVoteOutPercentMilleThreshold() external view returns (uint32) {
		return settings.voteOutPercentMilleThreshold;
	}

	function getVoteUnreadyPercentMilleThreshold() external view returns (uint32) {
		return settings.voteUnreadyPercentMilleThreshold;
	}

	function getVoteOutStatus(address subjectAddr) external view returns (uint votedStake, uint totalDelegatedStake) {
		votedStake = accumulatedStakesForVoteOut[subjectAddr];
		totalDelegatedStake = delegationsContract.getTotalDelegatedStake();
	}

	function getSubjectCommitteeStatus(address[] memory committee, bool[] memory certification, address addr) private pure returns (bool inCommittee, bool inCertifiedCommittee) {
		for (uint i = 0; i < committee.length; i++) {
			if (addr == committee[i]) {
				inCommittee = true;
				if (certification[i]) {
					inCertifiedCommittee = true;
				}
			}
		}
	}

	function getVoteUnreadyStatus(address subjectAddr) external view returns 
		(address[] memory committee, uint256[] memory weights, bool[] memory certification, bool[] memory votes, bool subjectInCommittee, bool subjectInCertifiedCommittee) {
		(committee, weights, certification) = committeeContract.getCommittee();

		votes = new bool[](committee.length);
		for (uint i = 0; i < committee.length; i++) {
			address memberAddr = committee[i];
			if (now < votedUnreadyVotes[memberAddr][subjectAddr]) {
				votes[i] = true;
			}
		}

		(subjectInCommittee, subjectInCertifiedCommittee) = getSubjectCommitteeStatus(committee, certification, subjectAddr);
	}

	function getSettings() external view returns (
		uint32 minSelfStakePercentMille,
		uint32 voteUnreadyPercentMilleThreshold,
		uint32 voteOutPercentMilleThreshold
	) {
		Settings memory _settings = settings;
		minSelfStakePercentMille = _settings.minSelfStakePercentMille;
		voteUnreadyPercentMilleThreshold = _settings.voteUnreadyPercentMilleThreshold;
		voteOutPercentMilleThreshold = _settings.voteOutPercentMilleThreshold;
	}

	ICommittee committeeContract;
	IDelegations delegationsContract;
	IGuardiansRegistration guardianRegistrationContract;
	IStakingContract stakingContract;
	ICertification certificationContract;
	function refreshContracts() external {
		committeeContract = ICommittee(getCommitteeContract());
		delegationsContract = IDelegations(getDelegationsContract());
		guardianRegistrationContract = IGuardiansRegistration(getGuardiansRegistrationContract());
		stakingContract = IStakingContract(getStakingContract());
		certificationContract = ICertification(getCertificationContract());
	}

}
