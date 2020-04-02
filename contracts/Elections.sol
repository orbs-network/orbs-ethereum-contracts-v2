pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";

import "./spec_interfaces/ICommitteeListener.sol";
import "./interfaces/IElections.sol";
import "./spec_interfaces/IContractRegistry.sol";
import "./spec_interfaces/IValidatorsRegistration.sol";
import "./IStakingContract.sol";
import "./spec_interfaces/ICommittee.sol";
import "./spec_interfaces/ICompliance.sol";


contract Elections is IElections, IStakeChangeNotifier, Ownable {
	using SafeMath for uint256;

    uint256 constant BANNING_LOCK_TIMEOUT = 1 weeks;

	// TODO consider using structs instead of multiple mappings
	mapping (address => uint256) ownStakes;
	mapping (address => uint256) uncappedStakes;
	uint256 totalGovernanceStake;

	mapping (address => address) delegations;
	mapping (address => mapping (address => uint256)) voteOuts; // by => to => timestamp
	mapping (address => address[]) banningVotes; // by => to[]]
	mapping (address => uint256) accumulatedStakesForBanning; // addr => total stake
	mapping (address => uint256) bannedValidators; // addr => timestamp

	uint minCommitteeSize; // TODO only used as an argument to committee.setMinimumWeight(), should probably not be here
	uint maxDelegationRatio; // TODO consider using a hardcoded constant instead.
	uint8 voteOutPercentageThreshold;
	uint256 voteOutTimeoutSeconds;
	uint256 banningPercentageThreshold;

	modifier onlyStakingContract() {
		require(msg.sender == contractRegistry.get("staking"), "caller is not the staking contract");

		_;
	}

	modifier onlyValidatorsRegistrationContract() {
		require(msg.sender == contractRegistry.get("validatorsRegistration"), "caller is not the validator registrations contract");

		_;
	}

	modifier onlyComplianceContract() {
		require(msg.sender == contractRegistry.get("compliance"), "caller is not the validator registrations contract");

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
	function validatorConformanceChanged(address addr, string calldata conformanceType) external onlyComplianceContract {
		if (_isBanned(addr)) {
			return;
		}

		if (isComplianceType(conformanceType)) {
			complianceCommitteeContract().addMember(addr, getCommitteeEffectiveStake(addr));
		} else {
			complianceCommitteeContract().removeMember(addr);
		}
	}

	function notifyReadyForCommittee() external onlyNotBanned {
		address sender = getMainAddrFromOrbsAddr(msg.sender);
		(bool committeeChanged,) = generalCommitteeContract().memberReadyForCommittee(sender);
		if (committeeChanged) {
			updateComplianceCommitteeMinimumWeight();
		}
		complianceCommitteeContract().memberReadyForCommittee(sender);
	}

	function notifyReadyToSync() external onlyNotBanned {
		address sender = getMainAddrFromOrbsAddr(msg.sender);
		(bool committeeChanged,) = generalCommitteeContract().memberReadyToSync(sender);
		if (committeeChanged) {
			updateComplianceCommitteeMinimumWeight();
		}
		complianceCommitteeContract().memberReadyToSync(sender);
	}

	function delegate(address to) external {
		address prevDelegatee = delegations[msg.sender];
        if (prevDelegatee == address(0)) {
            prevDelegatee = msg.sender;
        }

		uint256 prevGovStakePrevDelegatee = getGovernanceEffectiveStake(prevDelegatee);
		uint256 prevGovStakeNewDelegatee = getGovernanceEffectiveStake(to);

		delegations[msg.sender] = to; // delegation!
		emit Delegated(msg.sender, to);

		uint256 stake = ownStakes[msg.sender];

        _applyDelegatedStake(prevDelegatee, uncappedStakes[prevDelegatee].sub(stake), prevGovStakePrevDelegatee);
		_applyDelegatedStake(to, uncappedStakes[to].add(stake), prevGovStakeNewDelegatee);

		_applyStakesToBanningBy(prevDelegatee, prevGovStakePrevDelegatee);
		_applyStakesToBanningBy(to, prevGovStakeNewDelegatee);
	}

	function clearCommitteeVoteOuts(address[] memory committee, address votee) private {
		for (uint i = 0; i < committee.length; i++) {
			voteOuts[committee[i]][votee] = 0; // clear vote-outs
		}
	}

	function isCommitteeVoteOutThresholdReached(address[] memory committee, uint256[] memory weights, address votee) private  returns (bool) {
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

		(address[] memory generalCommittee, uint256[] memory generalWeights) = generalCommitteeContract().getCommittee();

		bool votedOut = isCommitteeVoteOutThresholdReached(generalCommittee, generalWeights, addr);
		if (votedOut) {
			clearCommitteeVoteOuts(generalCommittee, addr);
		} else if (isComplianceValidator(addr)) {
			(address[] memory complianceCommittee, uint256[] memory complianceWeights) = complianceCommitteeContract().getCommittee();
			votedOut = isCommitteeVoteOutThresholdReached(complianceCommittee, complianceWeights, addr);
			if (votedOut) {
				clearCommitteeVoteOuts(complianceCommittee, addr);
			}
		}

		if (votedOut) {
			emit VotedOutOfCommittee(addr);

			(bool committeeChanged,) = generalCommitteeContract().memberNotReadyToSync(addr);
			if (committeeChanged) {
				updateComplianceCommitteeMinimumWeight();
			}
			complianceCommitteeContract().memberNotReadyToSync(addr);
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

	event AccForBan(uint256 acc, uint256 total);
    function _applyBanningVotesFor(address addr) private {
        uint256 banningTimestamp = bannedValidators[addr];
        bool isBanned = banningTimestamp != 0;

        if (isBanned && now.sub(banningTimestamp) >= BANNING_LOCK_TIMEOUT) { // no unbanning after 7 days
            return;
        }

        uint256 banningStake = accumulatedStakesForBanning[addr];
		emit AccForBan(banningStake, totalGovernanceStake);
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

    function stakeChangeBatch(address[] calldata _stakeOwners, uint256[] calldata _amounts, bool[] calldata _signs,
		uint256[] calldata _updatedStakes) external onlyStakingContract {
		require(_stakeOwners.length == _amounts.length, "_stakeOwners, _amounts - array length mismatch");
		require(_stakeOwners.length == _signs.length, "_stakeOwners, _signs - array length mismatch");
		require(_stakeOwners.length == _updatedStakes.length, "_stakeOwners, _updatedStakes - array length mismatch");

		for (uint i = 0; i < _stakeOwners.length; i++) {
			_stakeChange(_stakeOwners[i], _amounts[i], _signs[i], _updatedStakes[i]);
		}
	}

	function getDelegation(address delegator) external view returns (address) {
		if (_isSelfDelegating(delegator)) {
			return delegator;
		}
		return delegations[delegator];
	}

	function stakeChange(address _stakeOwner, uint256 _amount, bool _sign, uint256 _updatedStake) external onlyStakingContract {
		_stakeChange(_stakeOwner, _amount, _sign, _updatedStake);
	}

	function _stakeChange(address _stakeOwner, uint256 _amount, bool _sign, uint256 /* _updatedStake */) private {
		address delegatee = delegations[_stakeOwner];
		if (delegatee == address(0)) {
			delegatee = _stakeOwner;
		}

		uint256 prevGovStakeOwner = getGovernanceEffectiveStake(_stakeOwner);
		uint256 prevGovStakeDelegatee = getGovernanceEffectiveStake(delegatee);

		uint256 newUncappedStake;
		uint256 newOwnStake;
		if (_sign) {
			newOwnStake = ownStakes[_stakeOwner].add(_amount);
			newUncappedStake = uncappedStakes[delegatee].add(_amount);
		} else {
			newOwnStake = ownStakes[_stakeOwner].sub(_amount);
			newUncappedStake = uncappedStakes[delegatee].sub(_amount);
		}
		ownStakes[_stakeOwner] = newOwnStake;

		_applyDelegatedStake(delegatee, newUncappedStake, prevGovStakeDelegatee);

		_applyStakesToBanningBy(_stakeOwner, prevGovStakeOwner); // totalGovernanceStake must be updated by now
		_applyStakesToBanningBy(delegatee, prevGovStakeDelegatee); // totalGovernanceStake must be updated by now
	}

	function stakeMigration(address _stakeOwner, uint256 _amount) external onlyStakingContract {}

	function refreshStakes(address[] calldata addrs) external {
		IStakingContract staking = IStakingContract(contractRegistry.get("staking"));

		for (uint i = 0; i < addrs.length; i++) {
			address staker = addrs[i];
			uint256 newOwnStake = staking.getStakeBalanceOf(staker);
			uint256 oldOwnStake = ownStakes[staker];
			if (newOwnStake > oldOwnStake) {
				_stakeChange(staker, newOwnStake - oldOwnStake, true, newOwnStake);
			} else if (oldOwnStake > newOwnStake) {
				_stakeChange(staker, oldOwnStake - newOwnStake, false, newOwnStake);
			}
		}
	}

	function getMainAddrFromOrbsAddr(address orbsAddr) private view returns (address) {
		address[] memory orbsAddrArr = new address[](1);
		orbsAddrArr[0] = orbsAddr;
		address sender = validatorsRegistration().getEthereumAddresses(orbsAddrArr)[0];
		require(sender != address(0), "unknown orbs address");
		return sender;
	}

	function _isSelfDelegating(address validator) private view returns (bool) {
		return delegations[validator] == address(0) || delegations[validator] == validator;
	}

	function _applyDelegatedStake(address addr, uint256 newStake, uint256 prevGovStake) private {
		uncappedStakes[addr] = newStake;

		uint256 currentGovStake = getGovernanceEffectiveStake(addr);
		totalGovernanceStake = totalGovernanceStake.sub(prevGovStake).add(currentGovStake);

		emit StakeChanged(addr, ownStakes[addr], newStake, getGovernanceEffectiveStake(addr), getCommitteeEffectiveStake(addr), totalGovernanceStake);

		(bool committeeChanged,) = generalCommitteeContract().memberWeightChange(addr, getCommitteeEffectiveStake(addr));
		if (committeeChanged) {
			updateComplianceCommitteeMinimumWeight();
		}
		complianceCommitteeContract().memberWeightChange(addr, getCommitteeEffectiveStake(addr));

	}

	function getCommitteeEffectiveStake(address v) private view returns (uint256) {
		uint256 ownStake = ownStakes[v];
		if (!_isSelfDelegating(v) || ownStake == 0) {
			return 0;
		}

		uint256 uncappedStake = uncappedStakes[v];
		uint256 maxRatio = maxDelegationRatio;
		if (uncappedStake.div(ownStake) < maxRatio) {
			return uncappedStake;
		}
		return ownStake.mul(maxRatio); // never overflows
	}

	function getGovernanceEffectiveStake(address v) public view returns (uint256) {
		if (!_isSelfDelegating(v)) {
			return 0;
		}
		return uncappedStakes[v];
	}

	function removeMemberFromCommittees(address addr) private {
		(bool committeeChanged,) = generalCommitteeContract().removeMember(addr);
		if (committeeChanged) {
			updateComplianceCommitteeMinimumWeight();
		}
		complianceCommitteeContract().removeMember(addr);
	}

	function addMemberToCommittees(address addr) private {
		(bool committeeChanged,) = generalCommitteeContract().addMember(addr, getCommitteeEffectiveStake(addr));
		if (committeeChanged) {
			updateComplianceCommitteeMinimumWeight();
		}
		if (isComplianceValidator(addr)) {
			complianceCommitteeContract().addMember(addr, getCommitteeEffectiveStake(addr));
		}
	}

	function updateComplianceCommitteeMinimumWeight() private {
		address lowestMember = generalCommitteeContract().getLowestCommitteeMember();
		uint256 lowestWeight = getCommitteeEffectiveStake(lowestMember);
		complianceCommitteeContract().setMinimumWeight(lowestWeight, lowestMember, minCommitteeSize);
	}

	function validatorsRegistration() private view returns (IValidatorsRegistration) {
		return IValidatorsRegistration(contractRegistry.get("validatorsRegistration"));
	}

	function generalCommitteeContract() private view returns (ICommittee) {
		return ICommittee(contractRegistry.get("committee-general"));
	}

	function complianceCommitteeContract() private view returns (ICommittee) {
		return ICommittee(contractRegistry.get("committee-compliance"));
	}

	function complianceContract() private view returns (ICompliance) {
		return ICompliance(contractRegistry.get("compliance"));
	}

	IContractRegistry contractRegistry;

	/// @dev Updates the address calldata of the contract registry
	function setContractRegistry(IContractRegistry _contractRegistry) external onlyOwner {
		require(_contractRegistry != IContractRegistry(0), "contractRegistry must not be 0");
		contractRegistry = _contractRegistry;
	}

	function compareStrings(string memory a, string memory b) private pure returns (bool) { // TODO find a better way
		return keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b)));
	}

	function isComplianceType(string memory compliance) private view returns (bool) {
		return compareStrings(compliance, "Compliance"); // TODO where should this constant be?
	}

	function isComplianceValidator(address addr) private view returns (bool) {
		string memory compliance = complianceContract().getValidatorCompliance(addr);
		return isComplianceType(compliance);
	}

}
