pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "./spec_interfaces/ICommitteeListener.sol";
import "./spec_interfaces/IDelegation.sol";
import "./interfaces/IElections.sol";
import "./spec_interfaces/IValidatorsRegistration.sol";
import "./IStakingContract.sol";
import "./spec_interfaces/ICommittee.sol";
import "./spec_interfaces/ICompliance.sol";
import "./ContractRegistryAccessor.sol";
import "./WithClaimableFunctionalOwnership.sol";


contract Elections is IElections, ContractRegistryAccessor, WithClaimableFunctionalOwnership, Lockable {
	using SafeMath for uint256;

	mapping (address => mapping (address => uint256)) votedUnreadyVotes; // by => to => timestamp
	mapping (address => address[]) voteOutVotes; // by => to[]]
	mapping (address => uint256) accumulatedStakesForVoteOut; // addr => total stake
	mapping (address => uint256) bannedValidators; // addr => timestamp

	uint256 totalGovernanceStake;

	struct Settings {
		uint32 voteUnreadyTimeoutSeconds;
		uint32 maxDelegationRatio;
		uint32 voteOutLockTimeoutSeconds;
		uint8 voteUnreadyPercentageThreshold;
		uint8 voteOutPercentageThreshold;
	}
	Settings settings;

	modifier onlyDelegationsContract() {
		require(msg.sender == address(getDelegationsContract()), "caller is not the delegations contract");

		_;
	}

	modifier onlyValidatorsRegistrationContract() {
		require(msg.sender == address(getValidatorsRegistrationContract()), "caller is not the validator registrations contract");

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
			voteOutPercentageThreshold: _voteOutPercentageThreshold,
			voteOutLockTimeoutSeconds: 1 weeks
		});
	}

	/// @dev Called by: validator registration contract
	/// Notifies a new validator was registered
	function validatorRegistered(address addr) external onlyValidatorsRegistrationContract {
	}

	/// @dev Called by: validator registration contract
	/// Notifies a new validator was unregistered
	function validatorUnregistered(address addr) external onlyValidatorsRegistrationContract {
		emit ValidatorStatusUpdated(addr, false, false);
		getCommitteeContract().removeMember(addr);
	}

	/// @dev Called by: validator registration contract
	/// Notifies on a validator compliance change
	function validatorComplianceChanged(address addr, bool isCompliant) external {
		getCommitteeContract().memberComplianceChange(addr, isCompliant);
	}

	function requireNotVotedOut(address addr) private view {
		require(!_isBanned(addr), "caller is voted-out");
	}

	function readyForCommittee() external {
		address guardianAddr = getValidatorsRegistrationContract().resolveGuardianAddress(msg.sender); // this validates registration
		require(!_isBanned(guardianAddr), "caller is voted-out");

		emit ValidatorStatusUpdated(guardianAddr, true, true);
		getCommitteeContract().addMember(guardianAddr, getCommitteeEffectiveStake(guardianAddr, settings), getComplianceContract().isValidatorCompliant(guardianAddr));
	}

	function readyToSync() external {
		address guardianAddr = getValidatorsRegistrationContract().resolveGuardianAddress(msg.sender); // this validates registration
		require(!_isBanned(guardianAddr), "caller is voted-out");

		emit ValidatorStatusUpdated(guardianAddr, true, false);
		getCommitteeContract().removeMember(guardianAddr);
	}

	function clearCommitteeUnreadyVotes(address[] memory committee, address votee) private {
		for (uint i = 0; i < committee.length; i++) {
			votedUnreadyVotes[committee[i]][votee] = 0; // clear vote-outs
		}
	}

	function isCommitteeVoteUnreadyThresholdReached(address[] memory committee, uint256[] memory weights, bool[] memory compliance, address votee) private view returns (bool) {
		Settings memory _settings = settings;

		uint256 totalCommitteeStake = 0;
		uint256 totalVoteUnreadyStake = 0;
		uint256 totalCompliantStake = 0;
		uint256 totalCompliantVoteUnreadyStake = 0;

		address member;
		uint256 memberStake;
		bool isVoteeCompliant;
		for (uint i = 0; i < committee.length; i++) {
			member = committee[i];
			memberStake = weights[i];

			if (member == votee && compliance[i]) {
				isVoteeCompliant = true;
			}

			totalCommitteeStake = totalCommitteeStake.add(memberStake);
			if (compliance[i]) {
				totalCompliantStake = totalCompliantStake.add(memberStake);
			}

			uint256 votedAt = votedUnreadyVotes[member][votee];
			if (votedAt != 0 && now.sub(votedAt) < _settings.voteUnreadyTimeoutSeconds) {
				totalVoteUnreadyStake = totalVoteUnreadyStake.add(memberStake);
				if (compliance[i]) {
					totalCompliantVoteUnreadyStake = totalCompliantVoteUnreadyStake.add(memberStake);
				}
			}

			// TODO - consider clearing up stale votes from the state (gas efficiency)
		}

		return (totalCommitteeStake > 0 && totalVoteUnreadyStake.mul(100).div(totalCommitteeStake) >= _settings.voteUnreadyPercentageThreshold)
			|| (isVoteeCompliant && totalCompliantStake > 0 && totalCompliantVoteUnreadyStake.mul(100).div(totalCompliantStake) >= _settings.voteUnreadyPercentageThreshold);
	}

	function voteUnready(address subjectAddr) external onlyWhenActive {
		address sender = getMainAddrFromOrbsAddr(msg.sender);
		votedUnreadyVotes[sender][subjectAddr] = now;
		emit VoteUnreadyCasted(sender, subjectAddr);

		(address[] memory generalCommittee, uint256[] memory generalWeights, bool[] memory compliance) = getCommitteeContract().getCommittee();

		bool votedUnready = isCommitteeVoteUnreadyThresholdReached(generalCommittee, generalWeights, compliance, subjectAddr);
		if (votedUnready) {
			clearCommitteeUnreadyVotes(generalCommittee, subjectAddr);
			emit ValidatorVotedUnready(subjectAddr);
			emit ValidatorStatusUpdated(subjectAddr, false, false);
            getCommitteeContract().removeMember(subjectAddr);
		}
	}

	function voteOut(address[] calldata subjectAddrs) external onlyWhenActive {
		require(subjectAddrs.length <= 3, "up to 3 concurrent votes are supported");
		for (uint i = 0; i < subjectAddrs.length; i++) {
			require(subjectAddrs[i] != address(0), "all votes must non zero addresses");
		}
        _voteOut(msg.sender, subjectAddrs);
		emit VoteOutCasted(msg.sender, subjectAddrs);
	}

	function calcGovernanceEffectiveStake(bool selfDelegating, uint256 totalDelegatedStake) private pure returns (uint256) {
		return selfDelegating ? totalDelegatedStake : 0;
	}

	function getVoteOutVotes(address addrs) external view returns (address[] memory) {
		return voteOutVotes[addrs];
	}

	function getAccumulatedStakesForVoteOut(address addrs) external view returns (uint256) {
		return accumulatedStakesForVoteOut[addrs];
	}

	function _applyStakesToVoteOutBy(address voter, uint256 previousStake, uint256 _totalGovernanceStake, Settings memory _settings) private { // TODO pass currentStake in. use pure version of getGovernanceEffectiveStake where applicable
		address[] memory votes = voteOutVotes[voter];
		uint256 currentStake = getGovernanceEffectiveStake(voter);

		for (uint i = 0; i < votes.length; i++) {
			address validator = votes[i];
			accumulatedStakesForVoteOut[validator] = accumulatedStakesForVoteOut[validator].
				sub(previousStake).
				add(currentStake);
			_applyVoteOutVotesFor(validator, _totalGovernanceStake, _settings);
		}
	}

    function _voteOut(address voter, address[] memory validators) private {
		Settings memory _settings = settings;

		address[] memory prevAddrs = voteOutVotes[voter];
		voteOutVotes[voter] = validators;
		uint256 _totalGovernanceStake = getDelegationsContract().getTotalDelegatedStake();

		for (uint i = 0; i < prevAddrs.length; i++) {
			address addr = prevAddrs[i];
			bool isRemoved = true;
			for (uint j = 0; j < validators.length; j++) {
				if (addr == validators[j]) {
					isRemoved = false;
					break;
				}
			}
			if (isRemoved) {
				accumulatedStakesForVoteOut[addr] = accumulatedStakesForVoteOut[addr].sub(getGovernanceEffectiveStake(msg.sender));
				_applyVoteOutVotesFor(addr, _totalGovernanceStake, _settings);
			}
		}

		for (uint i = 0; i < validators.length; i++) {
			address addr = validators[i];
			bool isAdded = true;
			for (uint j = 0; j < prevAddrs.length; j++) {
				if (prevAddrs[j] == addr) {
					isAdded = false;
					break;
				}
			}
			if (isAdded) {
				accumulatedStakesForVoteOut[addr] = accumulatedStakesForVoteOut[addr].add(getGovernanceEffectiveStake(msg.sender));
			}
			_applyVoteOutVotesFor(addr, _totalGovernanceStake, _settings); // recheck also if not new
		}
    }

    function _applyVoteOutVotesFor(address addr, uint256 _totalGovernanceStake, Settings memory _settings) private {
        uint256 voteOutTimestamp = bannedValidators[addr];
        bool isBanned = voteOutTimestamp != 0;

        if (isBanned && now.sub(voteOutTimestamp) >= _settings.voteOutLockTimeoutSeconds) { // no unvoteOut after 7 days
            return;
        }

        uint256 voteOutStake = accumulatedStakesForVoteOut[addr];
        bool shouldBan = _totalGovernanceStake > 0 && voteOutStake.mul(100).div(_totalGovernanceStake) >= _settings.voteOutPercentageThreshold;

        if (isBanned != shouldBan) {
			if (shouldBan) {
                bannedValidators[addr] = now;
				emit ValidatorVotedOut(addr);

				emit ValidatorStatusUpdated(addr, false, false);
				getCommitteeContract().removeMember(addr);
			} else {
                bannedValidators[addr] = 0;
				emit ValidatorVotedIn(addr);
			}
        }
    }

	function _isBanned(address addr) private view returns (bool) {
		return bannedValidators[addr] != 0;
	}

	function delegatedStakeChange(address addr, uint256 selfStake, uint256 totalDelegated, uint256 deltaTotalDelegated, bool signDeltaTotalDelegated) external onlyDelegationsContract onlyWhenActive {
		uint256 _totalGovernanceStake = getDelegationsContract().getTotalDelegatedStake();

		Settings memory _settings = settings;
		_applyDelegatedStake(addr, totalDelegated, _settings);
		_applyStakesToVoteOutBy(addr, signDeltaTotalDelegated ? totalDelegated.sub(deltaTotalDelegated) : totalDelegated.add(deltaTotalDelegated), _totalGovernanceStake, _settings);
	}

	function getMainAddrFromOrbsAddr(address orbsAddr) private view returns (address) {
		address[] memory orbsAddrArr = new address[](1);
		orbsAddrArr[0] = orbsAddr;
		address sender = getValidatorsRegistrationContract().getEthereumAddresses(orbsAddrArr)[0];
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

		uint256 uncappedStake = getUncappedStakes(v);
		uint256 maxRatio = _settings.maxDelegationRatio;
		if (uncappedStake.div(ownStake) < maxRatio) {
			return uncappedStake;
		}
		return ownStake.mul(maxRatio); // never overflows
	}

	function getUncappedStakes(address addr) internal view returns (uint256) {
		return getDelegationsContract().getDelegatedStakes(addr);
	}

	// TODO remove use of this function where possible - use pure function with bool and stake instead
	function getGovernanceEffectiveStake(address addr) internal view returns (uint256) {
		IDelegations d = getDelegationsContract();
		uint256 stakes = d.getDelegatedStakes(addr);
		bool isSelfDelegating = d.getDelegation(addr) == addr;
		return calcGovernanceEffectiveStake(isSelfDelegating, stakes);
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

	function setVoteOutLockTimeoutSeconds(uint32 voteOutLockTimeoutSeconds) external onlyFunctionalOwner /* todo onlyWhenActive */ {
		emit VoteOutLockTimeoutSecondsChanged(voteOutLockTimeoutSeconds, settings.voteOutLockTimeoutSeconds);
		settings.voteOutLockTimeoutSeconds = voteOutLockTimeoutSeconds;
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
		uint32 voteOutLockTimeoutSeconds,
		uint8 voteUnreadyPercentageThreshold,
		uint8 voteOutPercentageThreshold
	) {
		Settings memory _settings = settings;
		voteUnreadyTimeoutSeconds = _settings.voteUnreadyTimeoutSeconds;
		maxDelegationRatio = _settings.maxDelegationRatio;
		voteOutLockTimeoutSeconds = _settings.voteOutLockTimeoutSeconds;
		voteUnreadyPercentageThreshold = _settings.voteUnreadyPercentageThreshold;
		voteOutPercentageThreshold = _settings.voteUnreadyPercentageThreshold;
	}

}
