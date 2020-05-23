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


contract Elections is IElections, ContractRegistryAccessor {
	using SafeMath for uint256;

    uint256 constant BANNING_LOCK_TIMEOUT = 1 weeks;

	mapping (address => mapping (address => uint256)) voteOuts; // by => to => timestamp
	mapping (address => address[]) banningVotes; // by => to[]]
	mapping (address => uint256) accumulatedStakesForBanning; // addr => total stake
	mapping (address => uint256) bannedValidators; // addr => timestamp

	uint minCommitteeSize; // TODO only used as an argument to committee.setMinimumWeight(), should probably not be here
	uint maxDelegationRatio; // TODO consider using a hardcoded constant instead.
	uint8 voteOutPercentageThreshold;
	uint256 voteOutTimeoutSeconds;
	uint256 banningPercentageThreshold;
	uint256 totalGovernanceStake;

	modifier onlyDelegationsContract() {
		require(msg.sender == address(getDelegationsContract()), "caller is not the delegations contract");

		_;
	}

	modifier onlyValidatorsRegistrationContract() {
		require(msg.sender == address(getValidatorsRegistrationContract()), "caller is not the validator registrations contract");

		_;
	}

	modifier onlyComplianceContract() {
		require(msg.sender == address(getComplianceContract()), "caller is not the validator registrations contract");

		_;
	}

	modifier onlyNotBanned() {
		require(!_isBanned(msg.sender), "caller is a banned validator");

		_;
	}

	constructor(uint _minCommitteeSize, uint8 _maxDelegationRatio, uint8 _voteOutPercentageThreshold, uint256 _voteOutTimeoutSeconds, uint256 _banningPercentageThreshold) public {
		require(_maxDelegationRatio >= 1, "max delegation ration must be at least 1");
		require(_voteOutPercentageThreshold >= 0 && _voteOutPercentageThreshold <= 100, "voteOutPercentageThreshold must be between 0 and 100");
		require(_banningPercentageThreshold >= 0 && _banningPercentageThreshold <= 100, "banningPercentageThreshold must be between 0 and 100");

		minCommitteeSize = _minCommitteeSize;
	    maxDelegationRatio = _maxDelegationRatio;
		voteOutPercentageThreshold = _voteOutPercentageThreshold;
		voteOutTimeoutSeconds = _voteOutTimeoutSeconds;
		banningPercentageThreshold = _banningPercentageThreshold;
	}

	/// @dev Called by: validator registration contract
	/// Notifies a new validator was registered
	function validatorRegistered(address addr) external onlyValidatorsRegistrationContract {
		if (_isBanned(addr)) {
			return;
		}
		addMemberToCommittees(addr);
	}

	/// @dev Called by: validator registration contract
	/// Notifies a new validator was unregistered
	function validatorUnregistered(address addr) external onlyValidatorsRegistrationContract {
		removeMemberFromCommittees(addr);
	}

	/// @dev Called by: validator registration contract
	/// Notifies on a validator compliance change
	function validatorComplianceChanged(address addr, bool isCompliant) external onlyComplianceContract {
		if (_isBanned(addr)) {
			return;
		}

		if (isCompliant) {
            getComplianceCommitteeContract().addMember(addr, getCommitteeEffectiveStake(addr));
		} else {
			getComplianceCommitteeContract().removeMember(addr);
		}
	}

	function notifyReadyForCommittee() external onlyNotBanned {
		address sender = getMainAddrFromOrbsAddr(msg.sender);
		(bool committeeChanged,) = getGeneralCommitteeContract().memberReadyToSync(sender, true);
		if (committeeChanged) {
			updateComplianceCommitteeMinimumWeight();
		}
		getComplianceCommitteeContract().memberReadyToSync(sender, true);
	}

	function notifyReadyToSync() external onlyNotBanned {
		address sender = getMainAddrFromOrbsAddr(msg.sender);
		(bool committeeChanged,) = getGeneralCommitteeContract().memberReadyToSync(sender, false);
		if (committeeChanged) {
			updateComplianceCommitteeMinimumWeight();
		}
		getComplianceCommitteeContract().memberReadyToSync(sender, false);
	}

	function notifyDelegationChange(address delegator, uint256 delegatorSelfStake, address newDelegate, address prevDelegate, uint256 prevDelegateNewTotalStake, uint256 newDelegateNewTotalStake, uint256 prevDelegatePrevTotalStake, bool prevSelfDelegatingPrevDelegate, uint256 newDelegatePrevTotalStake, bool prevSelfDelegatingNewDelegate) onlyDelegationsContract external {
		require(newDelegate != prevDelegate, "in a delegation change the delegate must change");

		if (delegator == newDelegate) { // delegator != prevDelegate
			if (prevSelfDelegatingPrevDelegate) {
				totalGovernanceStake = totalGovernanceStake.sub(delegatorSelfStake);
			}
			totalGovernanceStake = totalGovernanceStake.add(delegatorSelfStake);
		} else if (delegator == prevDelegate) { // delegator != newDelegate
			totalGovernanceStake = totalGovernanceStake.sub(delegatorSelfStake);
			if (prevSelfDelegatingNewDelegate) {
				totalGovernanceStake = totalGovernanceStake.add(delegatorSelfStake);
			}
		} else { // delegator != newDelegate && delegator != prevDelegate
			if (prevSelfDelegatingPrevDelegate) {
				totalGovernanceStake = totalGovernanceStake.sub(delegatorSelfStake);
			}
			if (prevSelfDelegatingNewDelegate) {
				totalGovernanceStake = totalGovernanceStake.add(delegatorSelfStake);
			}
		}

		_applyDelegatedStake(prevDelegate, prevDelegateNewTotalStake);
		_applyDelegatedStake(newDelegate, newDelegateNewTotalStake);

		_applyStakesToBanningBy(prevDelegate, getGovernanceEffectiveStake(prevSelfDelegatingPrevDelegate, prevDelegatePrevTotalStake));
		_applyStakesToBanningBy(newDelegate, getGovernanceEffectiveStake(prevSelfDelegatingNewDelegate, newDelegatePrevTotalStake));
	}

	function clearCommitteeVoteOuts(address[] memory committee, address votee) private {
		for (uint i = 0; i < committee.length; i++) {
			voteOuts[committee[i]][votee] = 0; // clear vote-outs
		}
	}

	function isCommitteeVoteOutThresholdReached(address[] memory committee, uint256[] memory weights, address votee) private view returns (bool) {
		uint256 totalCommitteeStake = 0;
		uint256 totalVoteOutStake = 0;

		for (uint i = 0; i < committee.length; i++) {
			address member = committee[i];
			uint256 memberStake = weights[i];

			totalCommitteeStake = totalCommitteeStake.add(memberStake);
			uint256 votedAt = voteOuts[member][votee];
			if (votedAt != 0 && now.sub(votedAt) < voteOutTimeoutSeconds) {
				totalVoteOutStake = totalVoteOutStake.add(memberStake);
			}
			// TODO - consider clearing up stale votes from the state (gas efficiency)
		}

		return (totalCommitteeStake > 0 && totalVoteOutStake.mul(100).div(totalCommitteeStake) >= voteOutPercentageThreshold);
	}

	function voteOut(address addr) external {
		address sender = getMainAddrFromOrbsAddr(msg.sender);
		voteOuts[sender][addr] = now;
		emit VoteOut(sender, addr);

		(address[] memory generalCommittee, uint256[] memory generalWeights) = getGeneralCommitteeContract().getCommittee();

		bool votedOut = isCommitteeVoteOutThresholdReached(generalCommittee, generalWeights, addr);
		if (votedOut) {
			clearCommitteeVoteOuts(generalCommittee, addr);
		} else if (getComplianceContract().isValidatorCompliant(addr)) {
			(address[] memory complianceCommittee, uint256[] memory complianceWeights) = getComplianceCommitteeContract().getCommittee();
			votedOut = isCommitteeVoteOutThresholdReached(complianceCommittee, complianceWeights, addr);
			if (votedOut) {
				clearCommitteeVoteOuts(complianceCommittee, addr);
			}
		}

		if (votedOut) {
			emit VotedOutOfCommittee(addr);

			(bool committeeChanged,) = getGeneralCommitteeContract().memberNotReadyToSync(addr);
			if (committeeChanged) {
				updateComplianceCommitteeMinimumWeight();
			}
			getComplianceCommitteeContract().memberNotReadyToSync(addr);
		}
	}

	function setBanningVotes(address[] calldata validators) external {
		require(validators.length <= 3, "up to 3 concurrent votes are supported");
		for (uint i = 0; i < validators.length; i++) {
			require(validators[i] != address(0), "all votes must non zero addresses");
		}
        _setBanningVotes(msg.sender, validators);
		emit BanningVote(msg.sender, validators);
	}

	function getTotalGovernanceStake() external view returns (uint256) {
		return totalGovernanceStake;
	}

	function getGovernanceEffectiveStake(bool selfDelegating, uint256 totalDelegatedStake) private pure returns (uint256) {
		return selfDelegating ? totalDelegatedStake : 0;
	}

	function getBanningVotes(address addrs) external view returns (address[] memory) {
		return banningVotes[addrs];
	}

	function getAccumulatedStakesForBanning(address addrs) external view returns (uint256) {
		return accumulatedStakesForBanning[addrs];
	}

	function _applyStakesToBanningBy(address voter, uint256 previousStake) private {
		address[] memory votes = banningVotes[voter];
		uint256 currentStake = getGovernanceEffectiveStake(voter);

		for (uint i = 0; i < votes.length; i++) {
			address validator = votes[i];
			accumulatedStakesForBanning[validator] = accumulatedStakesForBanning[validator].
				sub(previousStake).
				add(currentStake);
			_applyBanningVotesFor(validator);
		}
	}

    function _setBanningVotes(address voter, address[] memory validators) private {
		address[] memory prevAddrs = banningVotes[voter];
		banningVotes[voter] = validators;

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
				accumulatedStakesForBanning[addr] = accumulatedStakesForBanning[addr].sub(getGovernanceEffectiveStake(msg.sender));
				_applyBanningVotesFor(addr);
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
				accumulatedStakesForBanning[addr] = accumulatedStakesForBanning[addr].add(getGovernanceEffectiveStake(msg.sender));
			}
			_applyBanningVotesFor(addr); // recheck also if not new
		}
    }

    function _applyBanningVotesFor(address addr) private {
        uint256 banningTimestamp = bannedValidators[addr];
        bool isBanned = banningTimestamp != 0;

        if (isBanned && now.sub(banningTimestamp) >= BANNING_LOCK_TIMEOUT) { // no unbanning after 7 days
            return;
        }

        uint256 banningStake = accumulatedStakesForBanning[addr];
        bool shouldBan = totalGovernanceStake > 0 && banningStake.mul(100).div(totalGovernanceStake) >= banningPercentageThreshold;

        if (isBanned != shouldBan) {
			if (shouldBan) {
                bannedValidators[addr] = now;
				emit Banned(addr);

				removeMemberFromCommittees(addr);
			} else {
                bannedValidators[addr] = 0;
				emit Unbanned(addr);

				addMemberToCommittees(addr);
			}
        }
    }

	function _isBanned(address addr) private view returns (bool){
		return bannedValidators[addr] != 0;
	}

	function notifyStakeChange(uint256 prevDelegateTotalStake, uint256 newDelegateTotalStake, address delegate, bool isSelfDelegatingDelegate) external onlyDelegationsContract {

		uint256 prevGovStakeDelegate = getGovernanceEffectiveStake(isSelfDelegatingDelegate, prevDelegateTotalStake);
		uint256 newGovStakeDelegate = getGovernanceEffectiveStake(isSelfDelegatingDelegate, newDelegateTotalStake);

		totalGovernanceStake = totalGovernanceStake.sub(prevGovStakeDelegate).add(newGovStakeDelegate);

		_applyDelegatedStake(delegate, newDelegateTotalStake);

		_applyStakesToBanningBy(delegate, prevGovStakeDelegate);
	}

	function notifyStakeChangeBatch(uint256[] calldata prevDelegateTotalStakes, uint256[] calldata newDelegateTotalStakes, address[] calldata delegates, bool[] calldata isSelfDelegatingDelegates) external onlyDelegationsContract {
		require(prevDelegateTotalStakes.length == newDelegateTotalStakes.length, "arrays must be of same length");
		require(prevDelegateTotalStakes.length == delegates.length, "arrays must be of same length");
		require(prevDelegateTotalStakes.length == isSelfDelegatingDelegates.length, "arrays must be of same length");

		for (uint i = 0; i < prevDelegateTotalStakes.length; i++) {
			uint256 prevGovStakeDelegate = getGovernanceEffectiveStake(isSelfDelegatingDelegates[i], prevDelegateTotalStakes[i]);
			uint256 newGovStakeDelegate = getGovernanceEffectiveStake(isSelfDelegatingDelegates[i], newDelegateTotalStakes[i]);

			totalGovernanceStake = totalGovernanceStake.sub(prevGovStakeDelegate).add(newGovStakeDelegate);

			// TODO aggregate changes for same delegates to minimize calls to committe contract - may assume similar delegates grouped together... CAUTION - check banning votes eveluation is not skewed
			_applyDelegatedStake(delegates[i], newDelegateTotalStakes[i]);

			// TODO avoid accessing delegation contract downstream for this delegate since totalGovernance is not yet fully applied
			_applyStakesToBanningBy(delegates[i], prevGovStakeDelegate);
		}
	}

	function getMainAddrFromOrbsAddr(address orbsAddr) private view returns (address) {
		address[] memory orbsAddrArr = new address[](1);
		orbsAddrArr[0] = orbsAddr;
		address sender = getValidatorsRegistrationContract().getEthereumAddresses(orbsAddrArr)[0];
		require(sender != address(0), "unknown orbs address");
		return sender;
	}

	function _applyDelegatedStake(address addr, uint256 newUncappedStake) private { // TODO newStake is getUncappedStakes(addr) at this point. governance and committee "effective" stakes can also be passed into this method, or alternately, use a getter for newStake also
		emit StakeChanged(addr, getStakingContract().getStakeBalanceOf(addr), newUncappedStake, getGovernanceEffectiveStake(addr), getCommitteeEffectiveStake(addr), totalGovernanceStake);

		(bool committeeChanged,) = getGeneralCommitteeContract().memberWeightChange(addr, getCommitteeEffectiveStake(addr));
		if (committeeChanged) {
			updateComplianceCommitteeMinimumWeight();
		}
		getComplianceCommitteeContract().memberWeightChange(addr, getCommitteeEffectiveStake(addr));

	}

	function getCommitteeEffectiveStake(address v) private view returns (uint256) {
		uint256 ownStake =  getStakingContract().getStakeBalanceOf(v);
		bool isSelfDelegating = getDelegationsContract().getDelegation(v) == v; // TODO optimized three sequential calls to delegations in this function
		if (!isSelfDelegating || ownStake == 0) {
			return 0;
		}

		uint256 uncappedStake = getUncappedStakes(v);
		uint256 maxRatio = maxDelegationRatio;
		if (uncappedStake.div(ownStake) < maxRatio) {
			return uncappedStake;
		}
		return ownStake.mul(maxRatio); // never overflows
	}

	function getUncappedStakes(address addr) internal view returns (uint256) {
		return getDelegationsContract().getDelegatedStakes(addr);
	}

	// TODO remove this function if possible - use pure function with bool and stake
	function getGovernanceEffectiveStake(address addr) internal view returns (uint256) {
		IDelegations d = getDelegationsContract();
		uint256 stakes = d.getDelegatedStakes(addr);
		bool isSelfDelegating = d.getDelegation(addr) == addr;
		return getGovernanceEffectiveStake(isSelfDelegating, stakes);
	}

	function removeMemberFromCommittees(address addr) private {
		(bool committeeChanged,) = getGeneralCommitteeContract().removeMember(addr);
		if (committeeChanged) {
			updateComplianceCommitteeMinimumWeight();
		}
		getComplianceCommitteeContract().removeMember(addr);
	}

	function addMemberToCommittees(address addr) private {
		(bool committeeChanged,) = getGeneralCommitteeContract().addMember(addr, getCommitteeEffectiveStake(addr));
		if (committeeChanged) {
			updateComplianceCommitteeMinimumWeight();
		}
		if (getComplianceContract().isValidatorCompliant(addr)) {
			getComplianceCommitteeContract().addMember(addr, getCommitteeEffectiveStake(addr));
		}
	}

	function updateComplianceCommitteeMinimumWeight() private {
		address lowestMember = getGeneralCommitteeContract().getLowestCommitteeMember();
		uint256 lowestWeight = getCommitteeEffectiveStake(lowestMember);
		getComplianceCommitteeContract().setMinimumWeight(lowestWeight, lowestMember, minCommitteeSize);
	}

	function compareStrings(string memory a, string memory b) private pure returns (bool) { // TODO find a better way
		return keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b)));
	}

}
