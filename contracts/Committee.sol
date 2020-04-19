pragma solidity 0.5.16;

import "./spec_interfaces/IContractRegistry.sol";
import "./spec_interfaces/ICommittee.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "./spec_interfaces/IValidatorsRegistration.sol";

/// @title Elections contract interface
contract Committee is ICommittee, Ownable {
	address[] topology;

	struct Member {
		bool member;
		bool readyForCommittee;
		uint256 readyToSyncTimestamp;
		uint256 weight;
	}
	mapping (address => Member) members;

	uint minimumWeight;
	address minimumAddress;
	uint minCommitteeSize;
	uint maxCommitteeSize;
	uint maxStandbys;
	uint readyToSyncTimeout;

	// Derived properties
	uint committeeSize;
	uint readyForCommitteeCount;
	int oldestReadyToSyncStandbyPos;

	modifier onlyElectionsContract() {
		require(msg.sender == contractRegistry.get("elections"), "caller is not the elections");

		_;
	}

	constructor(uint _minCommitteeSize, uint _maxCommitteeSize, uint _minimumWeight, uint _maxStandbys, uint256 _readyToSyncTimeout) public {
		require(_maxCommitteeSize > 0, "maxCommitteeSize must be larger than 0");
		require(_maxStandbys > 0, "maxStandbys must be larger than 0");
		require(_readyToSyncTimeout > 0, "readyToSyncTimeout must be larger than 0");
		require(_maxStandbys > 0, "maxStandbys must be larger than 0");
		minCommitteeSize = _minCommitteeSize;
		maxCommitteeSize = _maxCommitteeSize;
		minimumWeight = _minimumWeight;
		maxStandbys = _maxStandbys;
		readyToSyncTimeout = _readyToSyncTimeout;
	}

	/*
	 * Methods restricted to other Orbs contracts
	 */

	/// @dev Called by: Elections contract
	/// Notifies a weight change for sorting to a relevant committee member.
    /// weight = 0 indicates removal of the member from the committee (for exmaple on unregister, voteUnready, voteOut)
	function memberWeightChange(address addr, uint256 weight) external onlyElectionsContract returns (bool committeeChanged, bool standbysChanged) {
		if (isMember(addr)) {
			members[addr].weight = weight;
			return _rankValidator(addr);
		}
		return (false, false);
	}

	function memberReadyToSync(address addr) external onlyElectionsContract returns (bool committeeChanged, bool standbysChanged) {
		if (isMember(addr)) {
			members[addr].readyToSyncTimestamp = now;
			return _rankValidator(addr);
		}
		return (false, false);
	}

	function memberReadyForCommittee(address addr) external onlyElectionsContract returns (bool committeeChanged, bool standbysChanged) {
		if (isMember(addr)) {
			members[addr].readyToSyncTimestamp = now;
			members[addr].readyForCommittee = true;
			return _rankValidator(addr);
		}
		return (false, false);
	}

	function memberNotReadyToSync(address addr) external onlyElectionsContract returns (bool committeeChanged, bool standbysChanged) {
		if (isMember(addr)) {
			members[addr].readyToSyncTimestamp = 0;
			members[addr].readyForCommittee = false;
			return _rankValidator(addr);
		}
		return (false, false);
	}

	function addMember(address addr, uint256 weight) external onlyElectionsContract returns (bool committeeChanged, bool standbysChanged) {
		if (!isMember(addr)) {
			members[addr] = Member({
				member: true,
				readyForCommittee: false,
				readyToSyncTimestamp: 0,
				weight: weight
				});
			return _rankValidator(addr);
		}
		return (false, false);
	}

	/// @dev Called by: Elections contract
	/// Notifies a a member removal for example due to voteOut / voteUnready
	function removeMember(address addr) external onlyElectionsContract returns (bool committeeChanged, bool standbysChanged) {
		(committeeChanged, standbysChanged) = _removeFromTopology(addr);
		delete members[addr];
	}

	/// @dev Called by: Elections contract
	/// Returns the weight of the committee member with the lowest weight
	function getLowestCommitteeMember() external view returns (address addr) {
		if (committeeSize == 0) {
			return address(0);
		}
		return topology[committeeSize - 1];
	}

	/// @dev Called by: Elections contract
	/// Returns the committee members and their weights
	function getCommittee() external view returns (address[] memory addrs, uint256[] memory weights) {
		address[] memory committee = _loadCommittee();
		return (committee, _loadWeights(committee));
	}

	/// @dev Returns the standy (out of committee) members and their weights
	function getStandbys() external view returns (address[] memory addrs, uint256[] memory weights) {
		address[] memory standbys = _loadStandbys();
		return (standbys, _loadWeights(standbys));
	}

	/// @dev Called by: Elections contract
	/// Sets the minimal weight, and committee members
    /// Every member with sortingWeight >= mimimumWeight OR in top minimumN is included in the committee
	function setMinimumWeight(uint256 _mimimumWeight, address _minimumAddress, uint _minCommitteeSize) external onlyElectionsContract {

		minimumWeight = _mimimumWeight;
		minimumAddress = _minimumAddress;
		minCommitteeSize = _minCommitteeSize;

		(uint prevCommitteeSize, uint newCommitteeSize) = _onTopologyModification();
		if (prevCommitteeSize != newCommitteeSize) {
			_notifyCommitteeChanged();
			_notifyStandbysChanged();
		}
	}

	/*
	 * Governance
	 */

	IContractRegistry contractRegistry;

    /// @dev Updates the address calldata of the contract registry
	function setContractRegistry(IContractRegistry _contractRegistry) external onlyOwner {
		require(_contractRegistry != IContractRegistry(0), "contractRegistry must not be 0");
		contractRegistry = _contractRegistry;
	}

	/*
     * Getters
     */

    /// @dev returns the current committee
    /// used also by the rewards and fees contracts
	function getCommitteeInfo() external view returns (address[] memory addrs, uint256[] memory weights, address[] memory orbsAddrs, bytes4[] memory ips) {
		address[] memory committee = _loadCommittee();
		return (committee, _loadWeights(committee), _loadOrbsAddresses(committee), _loadIps(committee));
	}

    /// @dev returns the current standbys (out of commiteee) topology
	function getStandbysInfo() external view returns (address[] memory addrs, uint256[] memory weights, address[] memory orbsAddrs, bytes4[] memory ips) {
		address[] memory standbys = _loadStandbys();
		return (standbys, _loadWeights(standbys), _loadOrbsAddresses(standbys), _loadIps(standbys));
	}

	/*
	 * Private
	 */

	function _rankValidator(address validator) private returns (bool committeeChanged, bool standbysChanged) {
		// Removal
		if (!isReadyToSync(validator)) {
			return _removeFromTopology(validator);
		}

		// Modification
		(uint pos, bool inTopology) = _findInTopology(validator);
		if (inTopology) {
			return _adjustPositionInTopology(pos);
		}

		// Addition
		(bool qualified, uint entryPos) = _isQualifiedForTopologyByRank(validator);
		if (qualified) {
			return _appendToTopology(validator, entryPos);
		}

		return (false, false);
	}

	function _appendToTopology(address validator, uint entryPos) private returns (bool committeeChanged, bool standbysChanged) {
		assert(entryPos <= topology.length);
		if (entryPos == topology.length) {
			topology.length++;
		}
		topology[entryPos] = validator;

		(uint newPos, uint prevCommitteeSize, uint newCommitteeSize, uint newStandbySize) = _repositionTopologyMember(entryPos);

		bool joinedCommittee = newPos < newCommitteeSize;
		bool joinedStandbys = !joinedCommittee && newPos < topology.length;
		bool otherCommitteeMemberBecameStandby = joinedCommittee && prevCommitteeSize == newCommitteeSize;

		committeeChanged = joinedCommittee;
		if (committeeChanged) {
			_notifyCommitteeChanged();
		}

		standbysChanged = joinedStandbys || otherCommitteeMemberBecameStandby;
		if (standbysChanged) {
			_notifyStandbysChanged();
		}
	}

	function _onTopologyModification() private returns (uint prevCommitteeSize, uint newCommitteeSize) {
		newCommitteeSize = committeeSize;
		prevCommitteeSize = newCommitteeSize;
		while (newCommitteeSize > 0 && (topology.length < newCommitteeSize || !isReadyForCommittee(topology[newCommitteeSize - 1]) || getValidatorWeight(topology[newCommitteeSize - 1]) == 0 || newCommitteeSize - 1 >= minCommitteeSize && (getValidatorWeight(topology[newCommitteeSize - 1]) < minimumWeight || getValidatorWeight(topology[newCommitteeSize - 1]) == minimumWeight && uint256(topology[newCommitteeSize - 1]) < uint256(minimumAddress)))) {
			newCommitteeSize--;
		}
		while (topology.length > newCommitteeSize && newCommitteeSize < maxCommitteeSize && isReadyForCommittee(topology[newCommitteeSize]) && getValidatorWeight(topology[newCommitteeSize]) > 0 && (newCommitteeSize < minCommitteeSize || getValidatorWeight(topology[newCommitteeSize]) > minimumWeight || getValidatorWeight(topology[newCommitteeSize]) == minimumWeight && uint256(topology[newCommitteeSize]) >= uint256(minimumAddress))) {
			newCommitteeSize++;
		}
		committeeSize = newCommitteeSize;
		_refreshReadyForCommitteeCount();
		_refreshOldestReadyToSyncStandbyPos();
		return (prevCommitteeSize, newCommitteeSize);
	}

	function _refreshReadyForCommitteeCount() private returns (uint, uint) {
		uint newCount = readyForCommitteeCount;
		uint prevCount = newCount;
		while (newCount > 0 && (topology.length < newCount || !isReadyForCommittee(topology[newCount - 1]))) {
			newCount--;
		}
		while (topology.length > newCount && isReadyForCommittee(topology[newCount])) {
			newCount++;
		}
		readyForCommitteeCount = newCount;
		return (prevCount, newCount);
	}

	function _refreshOldestReadyToSyncStandbyPos() private {
		uint256 oldestTimestamp = uint(-1);
		uint oldestPos = uint(-1);
		for (uint i = committeeSize; i < topology.length; i++) {
			uint t = members[topology[i]].readyToSyncTimestamp;
			if (t < oldestTimestamp) {
				oldestTimestamp = t;
				oldestPos = i;
			}
		}
		oldestReadyToSyncStandbyPos = int(oldestPos);
	}

	function _compareValidatorsByData(address v1, uint256 v1Weight, bool v1Ready, address v2, uint256 v2Weight, bool v2Ready) private pure returns (int) {
		return v1Ready && !v2Ready ||
				v1Ready == v2Ready  && v1Weight > v2Weight ||
				v1Ready == v2Ready  && v1Weight == v2Weight && uint256(v1) > uint256(v2)
		? int(1) : -1;
	}

	function _compareValidators(address v1, address v2) private view returns (int) {
		bool v1Ready = isReadyForCommittee(v1);
		uint256 v1Weight = getValidatorWeight(v1);
		bool v2Ready = isReadyForCommittee(v2);
		uint256 v2Weight = getValidatorWeight(v2);
		return _compareValidatorsByData(v1, v1Weight, v1Ready, v2, v2Weight, v2Ready);
	}

	function _replace(uint p1, uint p2) private {
		address tempValidator = topology[p1];
		topology[p1] = topology[p2];
		topology[p2] = tempValidator;
	}

	function _repositionTopologyMember(uint memberPos) private returns (uint newPos, uint prevCommitteeSize, uint newCommitteeSize, uint newStandbySize) {
		uint topologySize = topology.length;
		assert(topologySize > memberPos);

		while (memberPos > 0 && _compareValidators(topology[memberPos], topology[memberPos - 1]) > 0) {
			_replace(memberPos-1, memberPos);
			memberPos--;
		}

		while (memberPos < topologySize - 1 && _compareValidators(topology[memberPos + 1], topology[memberPos]) > 0) {
			_replace(memberPos, memberPos+1);
			memberPos++;
		}

		newPos = memberPos;

		(prevCommitteeSize, newCommitteeSize) = _onTopologyModification();

		newStandbySize = topologySize - newCommitteeSize;
		if (newStandbySize > maxStandbys){
			// need to evict exactly one standby - todo assert?
			(bool found, uint pos) = findTimedOutStandby();
			if (found) {
				_evict(pos); // evict timed-out
			} else {
				(bool lowestWeightFound, uint lowestWeightPos, uint256 lowestWeight) = findLowestWeightStandby();
				_evict(lowestWeightPos); // evict lowest weight
			}
			_onTopologyModification();
			newStandbySize = maxStandbys;
		}
	}

	function _adjustPositionInTopology(uint pos) private returns (bool committeeChanged, bool standbysChanged) {
		// TODO if a validator leaves committee it may be replaced by a timed-out, ready-for-committee standby
		(uint newPos, uint prevCommitteeSize, uint newCommitteeSize, uint newStandbySize) = _repositionTopologyMember(pos);

		bool inCommitteeBefore = pos < prevCommitteeSize;
		bool isStandbyBefore = !inCommitteeBefore;

		bool inCommitteeAfter = newPos < newCommitteeSize;
		bool isStandbyAfter = !inCommitteeAfter;

		committeeChanged = inCommitteeBefore || inCommitteeAfter;
		if (committeeChanged) {
			_notifyCommitteeChanged();
		}

		standbysChanged = isStandbyBefore || isStandbyAfter;
		if (standbysChanged) {
			_notifyStandbysChanged();
		}
	}

	function _isQualifiedForTopologyByRank(address validator) private view returns (bool qualified, uint entryPos) {
		if (_isQualifiedForCommitteeByRank(validator)) {
			return (true, topology.length);
		}
		return _isQualifiedAsStandbyByRank(validator);
	}

	function _isQualifiedAsStandbyByRank(address validator) private view returns (bool qualified, uint entryPos) {
		if (isReadyToSyncStale(validator)) {
			return (false, 0);
		}

		(bool found, uint atPos) = findTimedOutStandby();
		if (found) {
			return (true, atPos);
		}

		uint standbyCount = topology.length - committeeSize;
		if (standbyCount < maxStandbys) {
			return (true, topology.length);
		}

		(bool foundLowest, uint lowestRankedStandbyPos, uint lowestRankedStandbyWeight) = findLowestWeightStandby();
		if (foundLowest && lowestRankedStandbyWeight < getValidatorWeight(validator)) {
			return (true, lowestRankedStandbyPos);
		}

		return (false, 0);
	}

	function isAboveCommitteeEntryThreshold(address validator) private view returns (bool) {
		return _compareValidatorsByData(minimumAddress, minimumWeight, true, validator, getValidatorWeight(validator), true) < 1;
	}

	function _isQualifiedForCommitteeByRank(address validator) private view returns (bool qualified) {
		// this assumes maxTopologySize > maxCommitteeSize, otherwise a non ready-for-committee validator may override one that is ready.
		if (isReadyForCommittee(validator) && !isReadyToSyncStale(validator) && (
			minCommitteeSize > 0 && committeeSize < minCommitteeSize ||
			committeeSize < maxCommitteeSize && isAboveCommitteeEntryThreshold(validator) ||
			committeeSize > 0 && _compareValidators(topology[committeeSize - 1], validator) < 0
		)) {
			return true;
		}

		return false;
	}

	function findTimedOutStandby() private view returns (bool found, uint pos) {
		pos = uint(oldestReadyToSyncStandbyPos);
		found = int(pos) >= 0 && pos < topology.length && isReadyToSyncStale(topology[pos]);
	}

	function findLowestWeightStandby() private view returns (bool found, uint pos, uint weight) {
		if (topology.length == committeeSize) {
			return (false, 0, 0);
		}

		address v1 = topology[topology.length - 1];
		uint256 v1Weight = getValidatorWeight(v1);
		if (readyForCommitteeCount <= committeeSize) {
			return (true, topology.length - 1, v1Weight);
		}

		address v2 = topology[readyForCommitteeCount - 1];
		uint256 v2Weight = getValidatorWeight(v2);
		if (v2Weight < v1Weight) {
			return (true, readyForCommitteeCount - 1, v2Weight);
		}

		return (true, topology.length - 1, v1Weight);
	}

	function _findInTopology(address v) private view returns (uint, bool) {
		uint l =  topology.length;
		for (uint i=0; i < l; i++) {
			if (topology[i] == v) {
				return (i, true);
			}
		}
		return (0, false);
	}

	function _removeFromTopology(address addr) private returns (bool committeeChanged, bool standbysChanged) {
		(uint pos, bool inTopology) = _findInTopology(addr);
		if (!inTopology) {
			return (false, false);
		}

		_evict(pos);

		(uint prevCommitteeSize, uint currentCommitteeSize) = _onTopologyModification();

		bool committeeSizeChanged = prevCommitteeSize != currentCommitteeSize;
		bool wasInCommittee = committeeSizeChanged || pos < prevCommitteeSize;
		bool standbyJoinedCommittee = wasInCommittee && !committeeSizeChanged;

		committeeChanged = wasInCommittee;
		if (committeeChanged) {
			_notifyCommitteeChanged();
		}

		standbysChanged = !wasInCommittee || standbyJoinedCommittee;
		if (standbysChanged) {
			_notifyStandbysChanged();
		}
	}

	function _evict(uint pos) private {
		assert(topology.length > 0);
		assert(pos < topology.length);

		for (uint p = pos; p < topology.length - 1; p++) {
			topology[p] = topology[p + 1];
		}

		topology.length = topology.length - 1;
	}

	function _notifyStandbysChanged() private {
		address[] memory standbys = _loadStandbys();
		emit StandbysChanged(standbys, _loadOrbsAddresses(standbys), _loadWeights(standbys));
	}

	function _notifyCommitteeChanged() private {
		address[] memory committee = _loadCommittee();
		emit CommitteeChanged(committee, _loadOrbsAddresses(committee), _loadWeights(committee));
	}

	function _loadWeights(address[] memory addrs) private view returns (uint256[] memory) {
		uint256[] memory weights = new uint256[](addrs.length);
		for (uint i = 0; i < addrs.length; i++) {
			weights[i] = getValidatorWeight(addrs[i]);
		}
		return weights;
	}

	function _loadOrbsAddresses(address[] memory addrs) private view returns (address[] memory) {
		address[] memory orbsAddresses = new address[](addrs.length);
		IValidatorsRegistration validatorsRegistrationContract = validatorsRegistration();
		for (uint i = 0; i < addrs.length; i++) {
			orbsAddresses[i] = validatorsRegistrationContract.getValidatorOrbsAddress(addrs[i]);
		}
		return orbsAddresses;
	}

	function _loadIps(address[] memory addrs) private view returns (bytes4[] memory) {
		bytes4[] memory ips = new bytes4[](addrs.length);
		IValidatorsRegistration validatorsRegistrationContract = validatorsRegistration();
		for (uint i = 0; i < addrs.length; i++) {
			ips[i] = validatorsRegistrationContract.getValidatorIp(addrs[i]);
		}
		return ips;
	}

	function _loadStandbys() private view returns (address[] memory) {
		uint _committeeSize = committeeSize;
		uint standbysCount = topology.length - _committeeSize;
		address[] memory standbys = new address[](standbysCount);
		for (uint i = 0; i < standbysCount; i++) {
			standbys[i] = topology[_committeeSize + i];
		}
		return standbys;
	}

	function _loadCommittee() private view returns (address[] memory) {
		uint _committeeSize = committeeSize;
		address[] memory committee = new address[](_committeeSize);
		for (uint i = 0; i < _committeeSize; i++) {
			committee[i] = topology[i];
		}
		return committee;
	}

	function getValidatorWeight(address addr) private view returns (uint256 weight) {
		return members[addr].weight;
	}

	function validatorsRegistration() private view returns (IValidatorsRegistration) {
		return IValidatorsRegistration(contractRegistry.get("validatorsRegistration"));
	}

	function getTopology() external view returns (address[] memory) { // TODO remove
		return topology;
	}

	function isReadyToSyncStale(address addr) private view returns (bool) {
		return members[addr].readyToSyncTimestamp <= now - readyToSyncTimeout;
	}

	function isReadyToSync(address addr) private view returns (bool) {
		return members[addr].readyToSyncTimestamp != 0;
	}

	function isReadyForCommittee(address addr) private view returns (bool) {
		return members[addr].readyForCommittee;
	}

	function isMember(address addr) private view returns (bool) {
		return members[addr].member;
	}
}
