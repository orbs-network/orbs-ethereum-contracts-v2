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

	uint256 totalGovernanceStake;

	struct Settings {
		uint32 voteUnreadyTimeoutSeconds;
		uint32 maxDelegationRatio;
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

	constructor(uint32 _maxDelegationRatio, uint8 _voteUnreadyPercentageThreshold, uint32 _voteUnreadyTimeoutSeconds, uint8 _voteOutPercentageThreshold) public {
		require(_maxDelegationRatio >= 1, "max delegation ration must be at least 1");
		require(_voteUnreadyPercentageThreshold >= 0 && _voteUnreadyPercentageThreshold <= 100, "voteUnreadyPercentageThreshold must be between 0 and 100");
		require(_voteOutPercentageThreshold >= 0 && _voteOutPercentageThreshold <= 100, "voteOutPercentageThreshold must be between 0 and 100");

		settings = Settings({
			maxDelegationRatio: _maxDelegationRatio,
			voteUnreadyPercentageThreshold: _voteUnreadyPercentageThreshold,
			voteUnreadyTimeoutSeconds: _voteUnreadyTimeoutSeconds,
			voteOutPercentageThreshold: _voteOutPercentageThreshold
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
			accumulatedStakesForVoteOut[prevSubject] = accumulatedStakesForVoteOut[prevSubject].sub(voterStake);
			_applyVoteOutVotesFor(prevSubject, totalStake, _settings);
		}

		if (subject != address(0)) {
			if (prevSubject != subject) {
				accumulatedStakesForVoteOut[subject] = accumulatedStakesForVoteOut[subject].add(voterStake);
			}
			_applyVoteOutVotesFor(subject, totalStake, _settings); // recheck also if not new
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

	function _applyStakesToVoteOutBy(address voter, uint256 currentVoterStake, uint256 _totalGovernanceStake, Settings memory _settings) private { // TODO pass currentStake in. use pure version of getGovernanceEffectiveStake where applicable
		address subjectAddr = voteOutVotes[voter];
		if (subjectAddr == address(0)) return;

		uint256 prevVoterStake = votersStake[voter];
		votersStake[voter] = currentVoterStake;

		accumulatedStakesForVoteOut[subjectAddr] = accumulatedStakesForVoteOut[subjectAddr].
		sub(prevVoterStake).
		add(currentVoterStake);

		_applyVoteOutVotesFor(subjectAddr, _totalGovernanceStake, _settings);
	}

    function _applyVoteOutVotesFor(address addr, uint256 _totalGovernanceStake, Settings memory _settings) private {
        if (isVotedOut(addr)) {
            return;
        }

        uint256 voteOutStake = accumulatedStakesForVoteOut[addr];
        bool shouldBeVotedOut = _totalGovernanceStake > 0 && voteOutStake.mul(100).div(_totalGovernanceStake) >= _settings.voteOutPercentageThreshold;
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

	function delegatedStakeChange(address addr, uint256 selfStake, uint256 totalDelegated) external onlyDelegationsContract onlyWhenActive {
		uint256 _totalGovernanceStake = getDelegationsContract().getTotalDelegatedStake();

		Settings memory _settings = settings;
		_applyDelegatedStake(addr, totalDelegated, _settings);
		_applyStakesToVoteOutBy(addr, totalDelegated, _totalGovernanceStake, _settings);
	}

	function getMainAddrFromOrbsAddr(address orbsAddr) private view returns (address) {
		address[] memory orbsAddrArr = new address[](1);
		orbsAddrArr[0] = orbsAddr;
		address sender = getGuardiansRegistrationContract().getEthereumAddresses(orbsAddrArr)[0];
		require(sender != address(0), "unknown orbs address");
		return sender;
	}

	function _applyDelegatedStake(address addr, uint256 newUncappedStake, Settings memory _settings) private { // TODO governance and committee "effective" stakes, as well as stakingBalance can be passed in
		uint effectiveStake = getCommitteeEffectiveStake(addr, _settings);
		emit StakeChanged(addr, getStakingContract().getStakeBalanceOf(addr), newUncappedStake, effectiveStake);

		getCommitteeContract().memberWeightChange(addr, effectiveStake);
	}

	function getCommitteeEffectiveStake(address v, Settings memory _settings) private view returns (uint256) { // TODO reduce number of calls to other contracts
		uint256 ownStake =  getStakingContract().getStakeBalanceOf(v);
		bool isSelfDelegating = getDelegationsContract().getDelegation(v) == v;
		if (!isSelfDelegating || ownStake == 0) {
			return 0;
		}

		uint256 uncappedStake = getDelegationsContract().getDelegatedStakes(v);
		uint256 maxRatio = _settings.maxDelegationRatio;
		if (uncappedStake.div(ownStake) < maxRatio) {
			return uncappedStake;
		}
		return ownStake.mul(maxRatio); // never overflows
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

	function setMaxDelegationRatio(uint32 maxDelegationRatio) external onlyFunctionalOwner /* todo onlyWhenActive */ {
		require(maxDelegationRatio >= 1, "max delegation ration must be at least 1");
		emit MaxDelegationRatioChanged(maxDelegationRatio, settings.maxDelegationRatio);
		settings.maxDelegationRatio = maxDelegationRatio;
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
		uint32 maxDelegationRatio,
		uint8 voteUnreadyPercentageThreshold,
		uint8 voteOutPercentageThreshold
	) {
		Settings memory _settings = settings;
		voteUnreadyTimeoutSeconds = _settings.voteUnreadyTimeoutSeconds;
		maxDelegationRatio = _settings.maxDelegationRatio;
		voteUnreadyPercentageThreshold = _settings.voteUnreadyPercentageThreshold;
		voteOutPercentageThreshold = _settings.voteUnreadyPercentageThreshold;
	}

}
