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
		bool readyToSync;
		uint256 weight;
	}
	mapping (address => Member) members;

	uint maxCommitteeSize;
	uint maxStandbys;

	uint committeeSize;
	uint readyForCommitteeCount;

	modifier onlyElectionsContract() {
		require(msg.sender == contractRegistry.get("elections"), "caller is not the elections");

		_;
	}

	constructor(uint _maxCommitteeSize, uint _maxStandbys) public {
		require(_maxCommitteeSize > 0, "maxCommitteeSize must be larger than 0");
		require(_maxStandbys > 0, "maxStandbys must be larger than 0");
		maxCommitteeSize = _maxCommitteeSize;
		maxStandbys = _maxStandbys;
	}

	/*
	 * Methods restricted to other Orbs contracts
	 */

	/// @dev Called by: Elections contract
	/// Notifies a weight change for sorting to a relevant committee member.
    /// weight = 0 indicates removal of the member from the committee (for exmaple on unregister, voteUnready, voteOut)
	function memberWeightChange(address addr, uint256 weight) external onlyElectionsContract returns (bool committeeChanged, bool standbysChanged) {
		committeeChanged = false;
		standbysChanged = false;
		if (isMember(addr)) {
			members[addr].weight = weight;
			return _rankValidator(addr);
		}
	}

	function memberReadyToSync(address addr) external onlyElectionsContract returns (bool committeeChanged, bool standbysChanged) {
		committeeChanged = false;
		standbysChanged = false;
		if (isMember(addr)) {
			members[addr].readyToSync = true;
			return _rankValidator(addr);
		}
	}

	function memberReadyForCommittee(address addr) external onlyElectionsContract returns (bool committeeChanged, bool standbysChanged) {
		committeeChanged = false;
		standbysChanged = false;
		if (isMember(addr)) {
			members[addr].readyToSync = true;
			members[addr].readyForCommittee = true;
			return _rankValidator(addr);
		}
	}

	function memberNotReadyToSync(address addr) external onlyElectionsContract returns (bool committeeChanged, bool standbysChanged) {
		committeeChanged = false;
		standbysChanged = false;
		if (isMember(addr)) {
			members[addr].readyToSync = false;
			members[addr].readyForCommittee = false;
			return _rankValidator(addr);
		}
	}

	function addMember(address addr, uint256 weight) external onlyElectionsContract returns (bool committeeChanged, bool standbysChanged) {
		members[addr] = Member({
			member: true,
			readyForCommittee: false,
			readyToSync: false,
			weight: weight
		});
		return _rankValidator(addr);
	}

	/// @dev Called by: Elections contract
	/// Notifies a a member removal for example due to voteOut / voteUnready
	function removeMember(address addr) external onlyElectionsContract returns (bool committeeChanged, bool standbysChanged) {
		(committeeChanged, standbysChanged) = _removeFromTopology(addr);
		delete members[addr];
	}

	/// @dev Called by: Elections contract
	/// Returns the weight of
	function getWeight(uint N) external view returns (uint256 weight) { revert("not implemented"); }

	/// @dev Called by: Elections contract
	/// Returns the committee members and their weights
	function getCommittee() external view returns (address[] memory addrs, uint256[] memory weights) {
		weights = _loadCommitteeWeights();
		addrs = new address[](weights.length);
		for (uint i = 0; i < weights.length; i++) {
			addrs[i] = topology[i];
		}
	}

	/// @dev Returns the standy (out of commiteee) members and their weights
	function getStandbys(uint N) external view returns (address[] memory addrs, uint256[] memory weights) { revert("not implemented"); }

	/// @dev Called by: Elections contract
	/// Sets the mimimal weight, and committee members
    /// Every member with sortingWeight >= mimimumWeight OR in top minimumN is included in the committee
	function setMinimumWeight(uint256 mimimumWeight, uint minimumN) external /* onlyElectionsContract */ { revert("not implemented"); }

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
	function getCommitteeInfo() external view returns (address[] memory addrs, uint256[] memory weights, address[] memory orbsAddrs, uint32[] memory ips) { revert("not implemented"); }

    /// @dev returns the current standbys (out of commiteee) topology
	function getStandbysInfo() external view returns (address[] memory addrs, uint256[] memory weights, address[] memory orbsAddrs, uint32[] memory ips) { revert("not implemented"); }

	/*
	 * Private
	 */

	event Debug(string s);
	event Debug2(int256 n);

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

		(uint newPos, uint prevCommitteeSize, uint newCommitteeSize, uint prevStandbySize, uint newStandbySize) = _repositionTopologyMember(entryPos);

		bool joinedCommittee = newPos < newCommitteeSize;
		bool joinedStandbys = !joinedCommittee && newPos < topology.length;
		bool previousCommitteeFull = prevCommitteeSize == maxCommitteeSize;

		committeeChanged = false;
		if (joinedCommittee) {
			committeeChanged = true;
			_notifyCommitteeChanged();
		}

		standbysChanged = false;
		if (joinedStandbys || joinedCommittee && previousCommitteeFull) {
			standbysChanged = true;
			_notifyStandbysChanged();
		}
	}

	function _refreshCommitteeSize() private returns (uint, uint) {
		uint newSize = committeeSize;
		uint prevSize = newSize;
		while (newSize > 0 && (topology.length < newSize || !isReadyForCommittee(topology[newSize - 1]) || getValidatorWeight(topology[newSize - 1]) == 0)) {
			newSize--;
		}
		while (topology.length > newSize && newSize < maxCommitteeSize && isReadyForCommittee(topology[newSize]) && getValidatorWeight(topology[newSize]) > 0) {
			newSize++;
		}
		committeeSize = newSize;
		return (prevSize, newSize);
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

	function _compareValidators(address v1, address v2) private  returns (int) {
		bool v1Ready = isReadyForCommittee(v1);
		uint256 v1Weight = getValidatorWeight(v1);
		bool v2Ready = isReadyForCommittee(v2);
		uint256 v2Weight = getValidatorWeight(v2);

		return v1Ready && !v2Ready ||
				v1Ready == v2Ready  && v1Weight > v2Weight ? int(1) : -1;
	}

	function _replace(uint p1, uint p2) private {
		address tempValidator = topology[p1];
		topology[p1] = topology[p2];
		topology[p2] = tempValidator;
	}

	function _repositionTopologyMember(uint memberPos) private returns (uint newPos, uint prevCommitteeSize, uint newCommitteeSize, uint prevStandbySize, uint newStandbySize) {
		uint topologySize = topology.length;
		assert(topologySize > memberPos);

		while (memberPos > 0 && _compareValidators(topology[memberPos], topology[memberPos - 1]) > 0) {
			_replace(memberPos-1, memberPos);
			memberPos--;
		}

		while (memberPos < topologySize - 1 && _compareValidators(topology[memberPos], topology[memberPos + 1]) < 0) {
			_replace(memberPos, memberPos+1);
			memberPos++;
		}

		newPos = memberPos;

		_refreshReadyForCommitteeCount();
		(prevCommitteeSize, newCommitteeSize) = _refreshCommitteeSize();

		prevStandbySize = topologySize - prevCommitteeSize;
		if (prevStandbySize > maxStandbys){
			prevStandbySize = maxStandbys;
		}

		newStandbySize = topologySize - newCommitteeSize;
		if (newStandbySize > maxStandbys){
			newStandbySize = maxStandbys;
		}

		topology.length = newCommitteeSize + newStandbySize;
	}

	function _adjustPositionInTopology(uint pos) private returns (bool committeeChanged, bool standbysChanged) {
		(uint newPos, uint prevCommitteeSize, uint newCommitteeSize, uint prevStandbySize, uint newStandbySize) = _repositionTopologyMember(pos);

		bool inCommitteeBefore = pos < prevCommitteeSize;
		bool inStandbyBefore = !inCommitteeBefore;

		bool inCommitteeAfter = newPos < newCommitteeSize;
		bool inStandbyAfter = !inCommitteeAfter;

		committeeChanged = false;
		if (inCommitteeBefore || inCommitteeAfter) {
			committeeChanged = true;
			_notifyCommitteeChanged();
		}

		standbysChanged = false;
		if (inStandbyBefore || inStandbyAfter) {
			standbysChanged = true;
			_notifyStandbysChanged();
		}
	}

	function _isQualifiedForTopologyByRank(address validator) private view returns (bool qualified, uint entryPos) {
		// this assumes maxTopologySize > maxCommitteeSize, otherwise a non ready-for-committee validator may override one that is ready.
		(qualified, entryPos) = _isQualifiedForCommitteeByRank(validator);
		if (qualified) {
			return (qualified, entryPos);
		}
		(qualified, entryPos) = _isQualifiedAsStandbyByRank(validator);
	}

	function _isQualifiedAsStandbyByRank(address validator) private view returns (bool qualified, uint entryPos) {
		// this assumes maxTopologySize > maxCommitteeSize, otherwise a non ready-for-committee validator may override one that is ready.
		if (!isReadyToSync(validator)) {
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

	function _isQualifiedForCommitteeByRank(address validator) private view returns (bool qualified, uint entryPos) {
		// this assumes maxTopologySize > maxCommitteeSize, otherwise a non ready-for-committee validator may override one that is ready.
		if (!isReadyForCommittee(validator) || !isReadyToSync(validator)) {
			return (false, 0);
		}

		if (committeeSize < maxCommitteeSize || getValidatorWeight(validator) > getValidatorWeight(topology[committeeSize - 1])) {
			return (true, topology.length);
		}

		return (false, 0);
	}

	function findTimedOutStandby() private view returns (bool found, uint pos) {
		return (false, 0); // TODO
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
		standbysChanged = false;
		committeeChanged = false;
		(uint pos, bool inTopology) = _findInTopology(addr);
		if (inTopology) {
			assert(topology.length > 0);
			assert(pos < topology.length);

			for (uint p = pos; p < topology.length - 1; p++) {
				topology[p] = topology[p + 1];
			}

			topology.length = topology.length - 1;
			(uint prevSize, uint currentSize) = _refreshCommitteeSize();

			if (prevSize != currentSize || pos < currentSize) { // was in committee
				committeeChanged = true;
				_notifyCommitteeChanged();
			} else { // was a standby
				standbysChanged = true;
				_notifyStandbysChanged();
			}
		}
	}

	function _notifyStandbysChanged() private {
		uint256[] memory standbysWeights = _loadStandbysWeights();
		address[] memory standbysOrbsAddresses = new address[](standbysWeights.length);
		address[] memory standbys = new address[](standbysWeights.length);

		IValidatorsRegistration validatorsRegistrationContract = validatorsRegistration();
		uint _committeeSize = committeeSize;
		for (uint i = 0; i < standbysWeights.length; i++) {
			standbys[i] = topology[_committeeSize + i];
			standbysOrbsAddresses[i] = validatorsRegistrationContract.getValidatorOrbsAddress(standbys[i]);
		}
		emit StandbysChanged(standbys, standbysOrbsAddresses, standbysWeights);
	}

	function _notifyCommitteeChanged() private {
		uint256[] memory committeeWeights = _loadCommitteeWeights();
		address[] memory committeeOrbsAddresses = new address[](committeeWeights.length);
		address[] memory committee = new address[](committeeWeights.length);

		IValidatorsRegistration validatorsRegistrationContract = validatorsRegistration();
		for (uint i = 0; i < committeeWeights.length; i++) {
			committee[i] = topology[i];
			committeeOrbsAddresses[i] = validatorsRegistrationContract.getValidatorOrbsAddress(committee[i]);
		}
		emit CommitteeChanged(committee, committeeOrbsAddresses, committeeWeights);
	}

	function _loadWeights(uint offset, uint limit) private view returns (uint256[] memory) {
		uint256[] memory weights = new uint256[](limit);
		for (uint i = 0; i < limit; i++) {
			weights[i] = getValidatorWeight(topology[offset + i]);
		}
		return weights;
	}

	function _loadStandbysWeights() private view returns (uint256[] memory) {
		return _loadWeights(committeeSize, topology.length - committeeSize);
	}

	function _loadCommitteeWeights() private view returns (uint256[] memory) {
		return _loadWeights(0, committeeSize);
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

	function isReadyToSync(address addr) private view returns (bool) {
		return members[addr].readyToSync; // todo timeout
	}

	function isReadyForCommittee(address addr) private view returns (bool) {
		return members[addr].readyForCommittee;
	}

	function isMember(address addr) private view returns (bool) {
		return members[addr].member;
	}
}
