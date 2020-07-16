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
import "./WithClaimableFunctionalOwnership.sol";


contract Elections is IElections, ContractRegistryAccessor, WithClaimableFunctionalOwnership, Lockable {
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
	Settings settings;

	modifier onlyDelegationsContract() {
		require(msg.sender == address(getDelegationsContract()), "caller is not the delegations contract");

		_;
	}

	modifier onlyGuardiansRegistrationContract() {
		require(msg.sender == address(getGuardiansRegistrationContract()), "caller is not the guardian registrations contract");

		_;
	}

	constructor(uint32 minSelfStakePercentMille, uint8 voteUnreadyPercentageThreshold, uint32 voteUnreadyTimeoutSeconds, uint8 voteOutPercentageThreshold) public {
		require(minSelfStakePercentMille <= 100000, "minSelfStakePercentMille must be at most 100000");
		require(voteUnreadyPercentageThreshold >= 0 && voteUnreadyPercentageThreshold <= 100, "voteUnreadyPercentageThreshold must be between 0 and 100");
		require(voteOutPercentageThreshold >= 0 && voteOutPercentageThreshold <= 100, "voteOutPercentageThreshold must be between 0 and 100");

		settings = Settings({
			minSelfStakePercentMille: minSelfStakePercentMille,
			voteUnreadyPercentageThreshold: voteUnreadyPercentageThreshold,
			voteUnreadyTimeoutSeconds: voteUnreadyTimeoutSeconds,
			voteOutPercentageThreshold: voteOutPercentageThreshold
		});
	}

	/// @dev Called by: guardian registration contract
	/// Notifies a new guardian was registered
	function guardianRegistered(address addr) external onlyGuardiansRegistrationContract {
	}

	/// @dev Called by: guardian registration contract
	/// Notifies a new guardian was unregistered
	function guardianUnregistered(address addr) external onlyGuardiansRegistrationContract {
		emit GuardianStatusUpdated(addr, false, false);
		getCommitteeContract().removeMember(addr);
	}

	/// @dev Called by: guardian registration contract
	/// Notifies on a guardian certification change
	function guardianCertificationChanged(address addr, bool isCertified) external {
		getCommitteeContract().memberCertificationChange(addr, isCertified);
	}

	function requireNotVotedOut(address addr) private view {
		require(!isVotedOut(addr), "caller is voted-out");
	}

	function readyForCommittee() external {
		address guardianAddr = getGuardiansRegistrationContract().resolveGuardianAddress(msg.sender); // this validates registration
		require(!isVotedOut(guardianAddr), "caller is voted-out");

		emit GuardianStatusUpdated(guardianAddr, true, true);
		getCommitteeContract().addMember(guardianAddr, getCommitteeEffectiveStake(guardianAddr, settings), getCertificationContract().isGuardianCertified(guardianAddr));
	}

	function readyToSync() external {
		address guardianAddr = getGuardiansRegistrationContract().resolveGuardianAddress(msg.sender); // this validates registration
		require(!isVotedOut(guardianAddr), "caller is voted-out");

		emit GuardianStatusUpdated(guardianAddr, true, false);
		getCommitteeContract().removeMember(guardianAddr);
	}

	function clearCommitteeUnreadyVotes(address[] memory committee, address votee) private {
		for (uint i = 0; i < committee.length; i++) {
			votedUnreadyVotes[committee[i]][votee] = 0; // clear vote-outs
		}
	}

	function isCommitteeVoteUnreadyThresholdReached(address[] memory committee, uint256[] memory weights, bool[] memory certification, address votee) private view returns (bool) {
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
			if (votedAt != 0 && now.sub(votedAt) < _settings.voteUnreadyTimeoutSeconds) {
				totalVoteUnreadyStake = totalVoteUnreadyStake.add(memberStake);
				if (certification[i]) {
					totalCertifiedVoteUnreadyStake = totalCertifiedVoteUnreadyStake.add(memberStake);
				}
			}

			// TODO - consider clearing up stale votes from the state (gas efficiency)
		}

		return (totalCommitteeStake > 0 && totalVoteUnreadyStake.mul(100).div(totalCommitteeStake) >= _settings.voteUnreadyPercentageThreshold)
			|| (isVoteeCertified && totalCertifiedStake > 0 && totalCertifiedVoteUnreadyStake.mul(100).div(totalCertifiedStake) >= _settings.voteUnreadyPercentageThreshold);
	}

	function voteUnready(address subjectAddr) external onlyWhenActive {
		address sender = getMainAddrFromOrbsAddr(msg.sender);
		votedUnreadyVotes[sender][subjectAddr] = now;
		emit VoteUnreadyCasted(sender, subjectAddr);

		(address[] memory generalCommittee, uint256[] memory generalWeights, bool[] memory certification) = getCommitteeContract().getCommittee();

		bool votedUnready = isCommitteeVoteUnreadyThresholdReached(generalCommittee, generalWeights, certification, subjectAddr);
		if (votedUnready) {
			clearCommitteeUnreadyVotes(generalCommittee, subjectAddr);
			emit GuardianVotedUnready(subjectAddr);
			emit GuardianStatusUpdated(subjectAddr, false, false);
            getCommitteeContract().removeMember(subjectAddr);
		}
	}

	function voteOut(address subject) external onlyWhenActive {
		Settings memory _settings = settings;

		address prevSubject = voteOutVotes[msg.sender];
		voteOutVotes[msg.sender] = subject;

		uint256 voterStake = getDelegationsContract().getDelegatedStakes(msg.sender);

		if (prevSubject == address(0)) {
			votersStake[msg.sender] = voterStake;
		}

		if (subject == address(0)) {
			delete votersStake[msg.sender];
		}

		uint totalStake = getDelegationsContract().getTotalDelegatedStake();

		if (prevSubject != address(0) && prevSubject != subject) {
			uint256 accumulated = accumulatedStakesForVoteOut[prevSubject].sub(voterStake);
			accumulatedStakesForVoteOut[prevSubject] = accumulated;
			_applyVoteOutVotesFor(prevSubject, accumulated, totalStake, _settings);
		}

		if (subject != address(0)) {
			uint256 accumulated = accumulatedStakesForVoteOut[subject];
			if (prevSubject != subject) {
				accumulated = accumulated.add(voterStake);
				accumulatedStakesForVoteOut[subject] = accumulated;
			}

			_applyVoteOutVotesFor(subject, accumulated, totalStake, _settings); // recheck also if not new
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

		uint256 accumulated = accumulatedStakesForVoteOut[subjectAddr].
			sub(prevVoterStake).
			add(currentVoterStake);
		accumulatedStakesForVoteOut[subjectAddr] = accumulated;

		_applyVoteOutVotesFor(subjectAddr, accumulated, totalGovernanceStake, _settings);
	}

    function _applyVoteOutVotesFor(address addr, uint256 voteOutStake, uint256 totalGovernanceStake, Settings memory _settings) private {
        if (isVotedOut(addr)) {
            return;
        }

        bool shouldBeVotedOut = totalGovernanceStake > 0 && voteOutStake.mul(100).div(totalGovernanceStake) >= _settings.voteOutPercentageThreshold;
		if (shouldBeVotedOut) {
			votedOutGuardians[addr] = true;
			emit GuardianVotedOut(addr);

			emit GuardianStatusUpdated(addr, false, false);
			getCommitteeContract().removeMember(addr);
		}
    }

	function isVotedOut(address addr) private view returns (bool) {
		return votedOutGuardians[addr];
	}

	function delegatedStakeChange(address addr, uint256 selfStake, uint256 delegatedStake, uint256 totalDelegatedStake) external onlyDelegationsContract onlyWhenActive {
		Settings memory _settings = settings;
		_applyDelegatedStake(addr, selfStake, delegatedStake, _settings);
		_applyStakesToVoteOutBy(addr, delegatedStake, totalDelegatedStake, _settings);
	}

	function getMainAddrFromOrbsAddr(address orbsAddr) private view returns (address) {
		address[] memory orbsAddrArr = new address[](1);
		orbsAddrArr[0] = orbsAddr;
		address sender = getGuardiansRegistrationContract().getEthereumAddresses(orbsAddrArr)[0];
		require(sender != address(0), "unknown orbs address");
		return sender;
	}

	function _applyDelegatedStake(address addr, uint256 selfStake, uint256 delegatedStake, Settings memory _settings) private {
		uint effectiveStake = getCommitteeEffectiveStake(addr, selfStake, delegatedStake, _settings);
		emit StakeChanged(addr, selfStake, delegatedStake, effectiveStake);

		getCommitteeContract().memberWeightChange(addr, effectiveStake);
	}

	function getCommitteeEffectiveStake(address v, uint256 selfStake, uint256 delegatedStake, Settings memory _settings) private view returns (uint256) {
		if (selfStake == 0) {
			return 0;
		}

		if (selfStake.mul(100000) >= delegatedStake.mul(_settings.minSelfStakePercentMille)) {
			return delegatedStake;
		}

		return selfStake.mul(100000).div(_settings.minSelfStakePercentMille); // never overflows or divides by zero
	}

	function getCommitteeEffectiveStake(address v, Settings memory _settings) private view returns (uint256) {
		return getCommitteeEffectiveStake(v, getStakingContract().getStakeBalanceOf(v), getDelegationsContract().getDelegatedStakes(v), _settings);
	}

	function removeMemberFromCommittees(address addr) private {
		getCommitteeContract().removeMember(addr);
	}

	function addMemberToCommittees(address addr, Settings memory _settings) private {
		getCommitteeContract().addMember(addr, getCommitteeEffectiveStake(addr, _settings), getCertificationContract().isGuardianCertified(addr));
	}

	function setVoteUnreadyTimeoutSeconds(uint32 voteUnreadyTimeoutSeconds) external onlyFunctionalOwner /* todo onlyWhenActive */ {
		emit VoteUnreadyTimeoutSecondsChanged(voteUnreadyTimeoutSeconds, settings.voteUnreadyTimeoutSeconds);
		settings.voteUnreadyTimeoutSeconds = voteUnreadyTimeoutSeconds;
	}

	function setMinSelfStakePercentMille(uint32 minSelfStakePercentMille) external onlyFunctionalOwner /* todo onlyWhenActive */ {
		require(minSelfStakePercentMille <= 100000, "minSelfStakePercentMille must be 100000 at most");
		emit MinSelfStakePercentMilleChanged(minSelfStakePercentMille, settings.minSelfStakePercentMille);
		settings.minSelfStakePercentMille = minSelfStakePercentMille;
	}

	function setVoteOutPercentageThreshold(uint8 voteOutPercentageThreshold) external onlyFunctionalOwner /* todo onlyWhenActive */ {
		require(voteOutPercentageThreshold <= 100, "voteOutPercentageThreshold must not be larger than 100");
		emit VoteOutPercentageThresholdChanged(voteOutPercentageThreshold, settings.voteOutPercentageThreshold);
		settings.voteOutPercentageThreshold = voteOutPercentageThreshold;
	}

	function setVoteUnreadyPercentageThreshold(uint8 voteUnreadyPercentageThreshold) external onlyFunctionalOwner /* todo onlyWhenActive */ {
		require(voteUnreadyPercentageThreshold <= 100, "voteUnreadyPercentageThreshold must not be larger than 100");
		emit VoteUnreadyPercentageThresholdChanged(voteUnreadyPercentageThreshold, settings.voteUnreadyPercentageThreshold);
		settings.voteUnreadyPercentageThreshold = voteUnreadyPercentageThreshold;
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

}
