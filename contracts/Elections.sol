pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "./spec_interfaces/ICommitteeListener.sol";
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
		getComplianceCommitteeContract().flush();
		if (committeeChanged) {
			assignRewards(); // todo check both committees
		}

	}

	function notifyReadyToSync() external onlyNotBanned {
		address sender = getMainAddrFromOrbsAddr(msg.sender);
		(bool committeeChanged,) = getGeneralCommitteeContract().memberReadyToSync(sender, false);
		if (committeeChanged) {
			updateComplianceCommitteeMinimumWeight();
		}
		getComplianceCommitteeContract().memberReadyToSync(sender, false);
		getComplianceCommitteeContract().flush();
		if (committeeChanged) {
			assignRewards(); // todo check both committees
		}

	}

	function notifyDelegationChange(address newDelegatee, address prevDelegatee, uint256 newStakePrevDelegatee, uint256 newStakeNewDelegatee, uint256 prevGovStakePrevDelegatee, uint256 prevGovStakeNewDelegatee) onlyDelegationsContract external {

        _applyDelegatedStake(prevDelegatee, newStakePrevDelegatee);
		_applyDelegatedStake(newDelegatee, newStakeNewDelegatee);

		_applyStakesToBanningBy(prevDelegatee, prevGovStakePrevDelegatee);
		_applyStakesToBanningBy(newDelegatee, prevGovStakeNewDelegatee);
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
			getComplianceCommitteeContract().flush();
			if (committeeChanged) {
				assignRewards(); // todo check both committees
			}

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

	function assignRewards() public {
		(address[] memory generalCommittee, uint256[] memory generalCommitteeWeights) = getGeneralCommitteeContract().getCommittee();
		(address[] memory complianceCommittee,) = getComplianceCommitteeContract().getCommittee();
		getRewardsContract().assignRewards(generalCommittee, generalCommitteeWeights, complianceCommittee);
	}

	function getTotalGovernanceStake() internal view returns (uint256) {
		return getDelegationsContract().getTotalGovernanceStake();
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
        bool shouldBan = getTotalGovernanceStake() > 0 && banningStake.mul(100).div(getTotalGovernanceStake()) >= banningPercentageThreshold;

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

	function notifyStakeChange(address stakeOwner, uint256 newUncappedStake, uint256 prevGovStakeOwner, address delegatee, uint256 prevGovStakeDelegatee) external onlyDelegationsContract {
		_applyDelegatedStake(delegatee, newUncappedStake);

		_applyStakesToBanningBy(stakeOwner, prevGovStakeOwner); // totalGovernanceStake must be updated by now
		_applyStakesToBanningBy(delegatee, prevGovStakeDelegatee); // totalGovernanceStake must be updated by now
	}

	function notifyStakeChangeBatch(address[] calldata stakeOwners, uint256[] calldata newUncappedStakes, uint256[] calldata prevGovStakeOwners, address[] calldata delegatees, uint256[] calldata prevGovStakeDelegatees) external onlyDelegationsContract {
		require(stakeOwners.length == newUncappedStakes.length, "arrays must be of same length");
		require(stakeOwners.length == prevGovStakeOwners.length, "arrays must be of same length");
		require(stakeOwners.length == delegatees.length, "arrays must be of same length");
		require(stakeOwners.length == prevGovStakeDelegatees.length, "arrays must be of same length");

		address curDelegatee;
		uint totalNewUncapped;
		uint prevGovStake;
		for (uint i = 0; i < stakeOwners.length + 1; i++) {
			if (i == stakeOwners.length || delegatees[i] != curDelegatee) {
				if (curDelegatee != address(0)) {
					// this mimics notifyStakeChange
					_applyDelegatedStake(curDelegatee, totalNewUncapped);
					_applyStakesToBanningBy(curDelegatee, prevGovStake); // totalGovernanceStake must be updated by now // TODO check prevGovStake is correct
				}
				if (i == stakeOwners.length) {
					break;
				}
				curDelegatee = delegatees[i];
				totalNewUncapped = 0;
				prevGovStake = prevGovStakeOwners[i];
			}
			totalNewUncapped += newUncappedStakes[i];
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
		emit StakeChanged(addr, getStakingContract().getStakeBalanceOf(addr), newUncappedStake, getGovernanceEffectiveStake(addr), getCommitteeEffectiveStake(addr), getTotalGovernanceStake());

		uint gl01 = gasleft();
		(bool committeeChanged,) = getGeneralCommitteeContract().memberWeightChange(addr, getCommitteeEffectiveStake(addr));
		emit GasReport("committee call (1)", gl01-gasleft());
		if (committeeChanged) {
			updateComplianceCommitteeMinimumWeight();
		}
		gl01 = gasleft();
		getComplianceCommitteeContract().memberWeightChange(addr, getCommitteeEffectiveStake(addr));
		emit GasReport("committee call (3)", gl01-gasleft());

		gl01 = gasleft();
		getComplianceCommitteeContract().flush();
		emit GasReport("committee call (4)", gl01-gasleft());
//		uint gl02 = gasleft();
//		emit GasReport("committee calls: all", gl01-gasleft());
		if (committeeChanged) {
			assignRewards(); // todo check both committees
		}
	}

	function getCommitteeEffectiveStake(address v) private view returns (uint256) {
		uint256 ownStake =  getStakingContract().getStakeBalanceOf(v);
		if (ownStake == 0) {
			return 0;
		}

		uint256 uncappedStake = getGovernanceEffectiveStake(v);
		uint256 maxRatio = maxDelegationRatio;
		if (uncappedStake.div(ownStake) < maxRatio) {
			return uncappedStake;
		}
		return ownStake.mul(maxRatio); // never overflows
	}
	event GasReport(string label, uint gas);

	function getUncappedStakes(address addr) internal view returns (uint256) {
		return getDelegationsContract().getDelegatedStakes(addr);
	}

	function getGovernanceEffectiveStake(address addr) internal view returns (uint256) {
		return getDelegationsContract().getGovernanceEffectiveStake(addr);
	}

	function removeMemberFromCommittees(address addr) private {
		(bool committeeChanged,) = getGeneralCommitteeContract().removeMember(addr);
		if (committeeChanged) {
			updateComplianceCommitteeMinimumWeight();
		}
		getComplianceCommitteeContract().removeMember(addr);
		getComplianceCommitteeContract().flush();
		if (committeeChanged) {
			assignRewards(); // todo check both committees
		}

	}

	function addMemberToCommittees(address addr) private {
		(bool committeeChanged,) = getGeneralCommitteeContract().addMember(addr, getCommitteeEffectiveStake(addr));
		if (committeeChanged) {
			updateComplianceCommitteeMinimumWeight();
		}
		if (getComplianceContract().isValidatorCompliant(addr)) {
			getComplianceCommitteeContract().addMember(addr, getCommitteeEffectiveStake(addr));
		}
		getComplianceCommitteeContract().flush();
		if (committeeChanged) {
			assignRewards(); // todo check both committees
		}

	}

	function updateComplianceCommitteeMinimumWeight() private {
		address lowestMember = getGeneralCommitteeContract().getLowestCommitteeMember();
		uint256 lowestWeight = getCommitteeEffectiveStake(lowestMember);
		uint gl01 = gasleft();
		getComplianceCommitteeContract().setMinimumWeight(lowestWeight, lowestMember, minCommitteeSize, true);
		emit GasReport("committee call (2)", gl01-gasleft());
	}

	function compareStrings(string memory a, string memory b) private pure returns (bool) { // TODO find a better way
		return keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b)));
	}

}
