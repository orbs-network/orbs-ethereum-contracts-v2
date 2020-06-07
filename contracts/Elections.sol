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


contract Elections is IElections, ContractRegistryAccessor, WithClaimableFunctionalOwnership {
	using SafeMath for uint256;

    uint256 constant BANNING_LOCK_TIMEOUT = 1 weeks;

	mapping (address => mapping (address => uint256)) voteOuts; // by => to => timestamp
	mapping (address => address[]) banningVotes; // by => to[]]
	mapping (address => uint256) accumulatedStakesForBanning; // addr => total stake
	mapping (address => uint256) bannedValidators; // addr => timestamp

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

	modifier onlyNotBanned() {
		require(!_isBanned(msg.sender), "caller is a banned validator");

		_;
	}

	constructor(uint8 _maxDelegationRatio, uint8 _voteOutPercentageThreshold, uint256 _voteOutTimeoutSeconds, uint256 _banningPercentageThreshold) public {
		require(_maxDelegationRatio >= 1, "max delegation ration must be at least 1");
		require(_voteOutPercentageThreshold >= 0 && _voteOutPercentageThreshold <= 100, "voteOutPercentageThreshold must be between 0 and 100");
		require(_banningPercentageThreshold >= 0 && _banningPercentageThreshold <= 100, "banningPercentageThreshold must be between 0 and 100");

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
	function validatorComplianceChanged(address addr, bool isCompliant) external {
		getCommitteeContract().memberComplianceChange(addr, isCompliant);
	}

	function notifyReadyForCommittee() external onlyNotBanned {
		address sender = getMainAddrFromOrbsAddr(msg.sender);
		getCommitteeContract().memberReadyToSync(sender, true);
	}

	function notifyReadyToSync() external onlyNotBanned {
		address sender = getMainAddrFromOrbsAddr(msg.sender);
		getCommitteeContract().memberReadyToSync(sender, false);
	}

	function onlyWhenActive(address delegator, uint256 delegatorSelfStake, address newDelegate, address prevDelegate, uint256 prevDelegateNewTotalStake, uint256 newDelegateNewTotalStake, uint256 prevDelegatePrevTotalStake, bool prevSelfDelegatingPrevDelegate, uint256 newDelegatePrevTotalStake, bool prevSelfDelegatingNewDelegate) onlyDelegationsContract onlyWhenUnlocked external {
		require(newDelegate != prevDelegate, "in a delegation change the delegate must change");

		uint256 tempTotalGovernanceStake = totalGovernanceStake;
		if (delegator == newDelegate) { // delegator != prevDelegate
			tempTotalGovernanceStake = tempTotalGovernanceStake
				.sub(prevSelfDelegatingPrevDelegate ? delegatorSelfStake : 0)
				.add(newDelegateNewTotalStake);
		} else if (delegator == prevDelegate) { // delegator != newDelegate
			tempTotalGovernanceStake = tempTotalGovernanceStake
				.sub(prevDelegatePrevTotalStake)
				.add(prevSelfDelegatingNewDelegate ? delegatorSelfStake : 0);
		} else if (prevSelfDelegatingPrevDelegate != prevSelfDelegatingNewDelegate) { // delegator != newDelegate && delegator != prevDelegate
			if (prevSelfDelegatingPrevDelegate) {
				tempTotalGovernanceStake = tempTotalGovernanceStake.sub(delegatorSelfStake);
			}
			if (prevSelfDelegatingNewDelegate) {
				tempTotalGovernanceStake = tempTotalGovernanceStake.add(delegatorSelfStake);
			}
		}

		_applyDelegatedStake(prevDelegate, prevDelegateNewTotalStake, tempTotalGovernanceStake);
		_applyDelegatedStake(newDelegate, newDelegateNewTotalStake, tempTotalGovernanceStake);

		_applyStakesToBanningBy(prevDelegate, calcGovernanceEffectiveStake(prevSelfDelegatingPrevDelegate, prevDelegatePrevTotalStake), tempTotalGovernanceStake);
		_applyStakesToBanningBy(newDelegate, calcGovernanceEffectiveStake(prevSelfDelegatingNewDelegate, newDelegatePrevTotalStake), tempTotalGovernanceStake);

		totalGovernanceStake = tempTotalGovernanceStake;
	}

	function clearCommitteeVoteOuts(address[] memory committee, address votee) private {
		for (uint i = 0; i < committee.length; i++) {
			voteOuts[committee[i]][votee] = 0; // clear vote-outs
		}
	}

	function isCommitteeVoteOutThresholdReached(address[] memory committee, uint256[] memory weights, bool[] memory compliance, address votee) private view returns (bool) {
		uint256 totalCommitteeStake = 0;
		uint256 totalVoteOutStake = 0;
		uint256 totalCompliantStake = 0;
		uint256 totalCompliantVoteOutStake = 0;

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

			uint256 votedAt = voteOuts[member][votee];
			if (votedAt != 0 && now.sub(votedAt) < voteOutTimeoutSeconds) {
				totalVoteOutStake = totalVoteOutStake.add(memberStake);
				if (compliance[i]) {
					totalCompliantVoteOutStake = totalCompliantVoteOutStake.add(memberStake);
				}
			}

			// TODO - consider clearing up stale votes from the state (gas efficiency)
		}

		return (totalCommitteeStake > 0 && totalVoteOutStake.mul(100).div(totalCommitteeStake) >= voteOutPercentageThreshold)
			|| (isVoteeCompliant && totalCompliantStake > 0 && totalCompliantVoteOutStake.mul(100).div(totalCompliantStake) >= voteOutPercentageThreshold);
	}

	function onlyWhenActive(address addr) external onlyWhenUnlocked {
		address sender = getMainAddrFromOrbsAddr(msg.sender);
		voteOuts[sender][addr] = now;
		emit VoteOut(sender, addr);

		(address[] memory generalCommittee, uint256[] memory generalWeights, bool[] memory compliance) = getCommitteeContract().getCommittee();

		bool votedOut = isCommitteeVoteOutThresholdReached(generalCommittee, generalWeights, compliance, addr);
		if (votedOut) {
			clearCommitteeVoteOuts(generalCommittee, addr);
			emit VotedOutOfCommittee(addr);
			getCommitteeContract().memberNotReadyToSync(addr);
		}
	}

	function onlyWhenActive(address[] calldata validators) external onlyWhenUnlocked {
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

	function calcGovernanceEffectiveStake(bool selfDelegating, uint256 totalDelegatedStake) private pure returns (uint256) {
		return selfDelegating ? totalDelegatedStake : 0;
	}

	function getBanningVotes(address addrs) external view returns (address[] memory) {
		return banningVotes[addrs];
	}

	function getAccumulatedStakesForBanning(address addrs) external view returns (uint256) {
		return accumulatedStakesForBanning[addrs];
	}

	function _applyStakesToBanningBy(address voter, uint256 previousStake, uint256 _totalGovernanceStake) private { // TODO pass currentStake in. use pure version of getGovernanceEffectiveStake where applicable
		address[] memory votes = banningVotes[voter];
		uint256 currentStake = getGovernanceEffectiveStake(voter);

		for (uint i = 0; i < votes.length; i++) {
			address validator = votes[i];
			accumulatedStakesForBanning[validator] = accumulatedStakesForBanning[validator].
				sub(previousStake).
				add(currentStake);
			_applyBanningVotesFor(validator, _totalGovernanceStake);
		}
	}

    function _setBanningVotes(address voter, address[] memory validators) private {
		address[] memory prevAddrs = banningVotes[voter];
		banningVotes[voter] = validators;
		uint256 _totalGovernanceStake = totalGovernanceStake;

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
				_applyBanningVotesFor(addr, _totalGovernanceStake);
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
			_applyBanningVotesFor(addr, _totalGovernanceStake); // recheck also if not new
		}
    }

    function _applyBanningVotesFor(address addr, uint256 _totalGovernanceStake) private {
        uint256 banningTimestamp = bannedValidators[addr];
        bool isBanned = banningTimestamp != 0;

        if (isBanned && now.sub(banningTimestamp) >= BANNING_LOCK_TIMEOUT) { // no unbanning after 7 days
            return;
        }

        uint256 banningStake = accumulatedStakesForBanning[addr];
        bool shouldBan = _totalGovernanceStake > 0 && banningStake.mul(100).div(_totalGovernanceStake) >= banningPercentageThreshold;

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

	function _isBanned(address addr) private view returns (bool) {
		return bannedValidators[addr] != 0;
	}

	function onlyWhenActive(uint256 prevDelegateTotalStake, uint256 newDelegateTotalStake, address delegate, bool isSelfDelegatingDelegate) external onlyDelegationsContract onlyWhenUnlocked {

		uint256 prevGovStakeDelegate = calcGovernanceEffectiveStake(isSelfDelegatingDelegate, prevDelegateTotalStake);
		uint256 newGovStakeDelegate = calcGovernanceEffectiveStake(isSelfDelegatingDelegate, newDelegateTotalStake);

		uint256 _totalGovernanceStake = totalGovernanceStake;
		if (prevGovStakeDelegate != newGovStakeDelegate) {
			_totalGovernanceStake = _totalGovernanceStake.sub(prevGovStakeDelegate).add(newGovStakeDelegate);
		}

		_applyDelegatedStake(delegate, newDelegateTotalStake, _totalGovernanceStake);

		_applyStakesToBanningBy(delegate, prevGovStakeDelegate, _totalGovernanceStake);

		totalGovernanceStake = _totalGovernanceStake;
	}

	function onlyWhenActive(uint256[] calldata prevDelegateTotalStakes, uint256[] calldata newDelegateTotalStakes, address[] calldata delegates, bool[] calldata isSelfDelegatingDelegates) external onlyDelegationsContract onlyWhenUnlocked {
		require(prevDelegateTotalStakes.length == newDelegateTotalStakes.length, "arrays must be of same length");
		require(prevDelegateTotalStakes.length == delegates.length, "arrays must be of same length");
		require(prevDelegateTotalStakes.length == isSelfDelegatingDelegates.length, "arrays must be of same length");

		uint256 tempTotalGovStake = totalGovernanceStake;
		for (uint i = 0; i < prevDelegateTotalStakes.length; i++) {
			uint256 prevGovStakeDelegate = calcGovernanceEffectiveStake(isSelfDelegatingDelegates[i], prevDelegateTotalStakes[i]);
			uint256 newGovStakeDelegate = calcGovernanceEffectiveStake(isSelfDelegatingDelegates[i], newDelegateTotalStakes[i]);

			if (prevGovStakeDelegate != newGovStakeDelegate) {
				tempTotalGovStake = tempTotalGovStake.sub(prevGovStakeDelegate).add(newGovStakeDelegate);
			}

			_applyDelegatedStake(delegates[i], newDelegateTotalStakes[i], tempTotalGovStake);

			// TODO add tests to show banning votes are evaluated equally when stake change is batched and not batched
			_applyStakesToBanningBy(delegates[i], prevGovStakeDelegate, tempTotalGovStake);
		}
		totalGovernanceStake = tempTotalGovStake; // flush
	}

	function getMainAddrFromOrbsAddr(address orbsAddr) private view returns (address) {
		address[] memory orbsAddrArr = new address[](1);
		orbsAddrArr[0] = orbsAddr;
		address sender = getValidatorsRegistrationContract().getEthereumAddresses(orbsAddrArr)[0];
		require(sender != address(0), "unknown orbs address");
		return sender;
	}

	function _applyDelegatedStake(address addr, uint256 newUncappedStake, uint256 _totalGovernanceStake) private { // TODO governance and committee "effective" stakes, as well as stakingBalance can be passed in
		emit StakeChanged(addr, getStakingContract().getStakeBalanceOf(addr), newUncappedStake, getGovernanceEffectiveStake(addr), getCommitteeEffectiveStake(addr), _totalGovernanceStake);

		getCommitteeContract().memberWeightChange(addr, getCommitteeEffectiveStake(addr));
	}

	function getCommitteeEffectiveStake(address v) private view returns (uint256) { // TODO reduce number of calls to other contracts
		uint256 ownStake =  getStakingContract().getStakeBalanceOf(v);
		bool isSelfDelegating = getDelegationsContract().getDelegation(v) == v;
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

	// TODO remove use of this function where possible - use pure function with bool and stake instead
	function getGovernanceEffectiveStake(address addr) internal view returns (uint256) {
		IDelegations d = getDelegationsContract();
		uint256 stakes = d.getDelegatedStakes(addr);
		bool isSelfDelegating = d.getDelegation(addr) == addr;
		return calcGovernanceEffectiveStake(isSelfDelegating, stakes);
	}

	function removeMemberFromCommittees(address addr) private {
		getCommitteeContract().removeMember(addr);
	}

	function addMemberToCommittees(address addr) private {
		getCommitteeContract().addMember(addr, getCommitteeEffectiveStake(addr), getComplianceContract().isValidatorCompliant(addr));
	}
}
