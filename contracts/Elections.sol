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

	struct Settings {
		uint32 voteUnreadyTimeoutSeconds;
		uint32 minSelfStakePercentMille;
		uint8 voteUnreadyPercentageThreshold;
		uint8 voteOutPercentageThreshold;
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

	constructor(IContractRegistry _contractRegistry, address _registryManager, uint32 minSelfStakePercentMille, uint8 voteUnreadyPercentageThreshold, uint32 voteUnreadyTimeoutSeconds, uint8 voteOutPercentageThreshold) ManagedContract(_contractRegistry, _registryManager) public {
		setMinSelfStakePercentMille(minSelfStakePercentMille);
		setVoteOutPercentageThreshold(voteOutPercentageThreshold);
		setVoteUnreadyPercentageThreshold(voteUnreadyPercentageThreshold);
		setVoteUnreadyTimeoutSeconds(voteUnreadyTimeoutSeconds);
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

			uint256 votedAt = votedUnreadyVotes[member][votee];
			if (votedAt != 0) {
				if (now.sub(votedAt) < _settings.voteUnreadyTimeoutSeconds) {
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

		return (totalCommitteeStake > 0 && totalVoteUnreadyStake.mul(100).div(totalCommitteeStake) >= _settings.voteUnreadyPercentageThreshold)
			|| (isVoteeCertified && totalCertifiedStake > 0 && totalCertifiedVoteUnreadyStake.mul(100).div(totalCertifiedStake) >= _settings.voteUnreadyPercentageThreshold);
	}

	function voteUnready(address subjectAddr) external onlyWhenActive {
		address sender = guardianRegistrationContract.resolveGuardianAddress(msg.sender);
		votedUnreadyVotes[sender][subjectAddr] = now;
		emit VoteUnreadyCasted(sender, subjectAddr);

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

		bool shouldBeVotedOut = totalGovernanceStake > 0 && accumulated.mul(100).div(totalGovernanceStake) >= _settings.voteOutPercentageThreshold;
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

	function getCommitteeEffectiveStake(uint256 selfStake, uint256 delegatedStake, Settings memory _settings) private pure returns (uint256) {
		if (selfStake.mul(100000) >= delegatedStake.mul(_settings.minSelfStakePercentMille)) {
			return delegatedStake;
		}

		return selfStake.mul(100000).div(_settings.minSelfStakePercentMille); // never overflows or divides by zero
	}

	function getCommitteeEffectiveStake(address v, Settings memory _settings) private view returns (uint256) {
		return getCommitteeEffectiveStake(stakingContract.getStakeBalanceOf(v), delegationsContract.getDelegatedStakes(v), _settings);
	}

	function removeMemberFromCommittees(address addr) private {
		committeeContract.removeMember(addr);
	}

	function addMemberToCommittees(address addr, Settings memory _settings) private {
		committeeContract.addMember(addr, getCommitteeEffectiveStake(addr, _settings), certificationContract.isGuardianCertified(addr));
	}

	function setVoteUnreadyTimeoutSeconds(uint32 voteUnreadyTimeoutSeconds) public onlyFunctionalManager /* todo onlyWhenActive */ {
		emit VoteUnreadyTimeoutSecondsChanged(voteUnreadyTimeoutSeconds, settings.voteUnreadyTimeoutSeconds);
		settings.voteUnreadyTimeoutSeconds = voteUnreadyTimeoutSeconds;
	}

	function setMinSelfStakePercentMille(uint32 minSelfStakePercentMille) public onlyFunctionalManager /* todo onlyWhenActive */ {
		require(minSelfStakePercentMille <= 100000, "minSelfStakePercentMille must be 100000 at most");
		emit MinSelfStakePercentMilleChanged(minSelfStakePercentMille, settings.minSelfStakePercentMille);
		settings.minSelfStakePercentMille = minSelfStakePercentMille;
	}

	function setVoteOutPercentageThreshold(uint8 voteOutPercentageThreshold) public onlyFunctionalManager /* todo onlyWhenActive */ {
		require(voteOutPercentageThreshold <= 100, "voteOutPercentageThreshold must not be larger than 100");
		emit VoteOutPercentageThresholdChanged(voteOutPercentageThreshold, settings.voteOutPercentageThreshold);
		settings.voteOutPercentageThreshold = voteOutPercentageThreshold;
	}

	function setVoteUnreadyPercentageThreshold(uint8 voteUnreadyPercentageThreshold) public onlyFunctionalManager /* todo onlyWhenActive */ {
		require(voteUnreadyPercentageThreshold <= 100, "voteUnreadyPercentageThreshold must not be larger than 100");
		emit VoteUnreadyPercentageThresholdChanged(voteUnreadyPercentageThreshold, settings.voteUnreadyPercentageThreshold);
		settings.voteUnreadyPercentageThreshold = voteUnreadyPercentageThreshold;
	}

	function getVoteUnreadyTimeoutSeconds() external view returns (uint32) {
		return settings.voteUnreadyTimeoutSeconds;
	}

	function getMinSelfStakePercentMille() external view returns (uint32) {
		return settings.minSelfStakePercentMille;
	}

	function getVoteOutPercentageThreshold() external view returns (uint8) {
		return settings.voteOutPercentageThreshold;
	}

	function getVoteUnreadyPercentageThreshold() external view returns (uint8) {
		return settings.voteUnreadyPercentageThreshold;
	}

	function getSettings() external view returns (
		uint32 voteUnreadyTimeoutSeconds,
		uint32 minSelfStakePercentMille,
		uint8 voteUnreadyPercentageThreshold,
		uint8 voteOutPercentageThreshold
	) {
		Settings memory _settings = settings;
		voteUnreadyTimeoutSeconds = _settings.voteUnreadyTimeoutSeconds;
		minSelfStakePercentMille = _settings.minSelfStakePercentMille;
		voteUnreadyPercentageThreshold = _settings.voteUnreadyPercentageThreshold;
		voteOutPercentageThreshold = _settings.voteUnreadyPercentageThreshold;
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
