pragma solidity 0.5.16;

import "./spec_interfaces/IContractRegistry.sol";
import "./spec_interfaces/ICommittee.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "./spec_interfaces/IValidatorsRegistration.sol";

/// @title Elections contract interface
contract Committee is ICommittee, Ownable {
	address[] participants;

	struct MemberData { // can be reduced to 1 state entry
		bool isMember;
		bool readyForCommittee;
		uint256 readyToSyncTimestamp;
		uint256 weight;

		bool isStandby;
		bool inCommittee;
	}
	mapping (address => MemberData) members;

	struct Member {
		address addr;
		MemberData data;
		int pos;
	} // Never in state, only in memory

	struct Settings { // can be reduced to 2-3 state entries
		address minimumAddress;
		uint minimumWeight;
		uint minCommitteeSize;
		uint maxCommitteeSize;
		uint maxStandbys;
		uint readyToSyncTimeout;
	}
	Settings settings;

	// Derived properties (can be reduced to 2-3 state entries)
	struct CommitteeInfo {
		uint freeParticipantSlotPos;

		// Standby entry barrier
		uint oldestStandbyReadyToSyncStandbyTimestamp;
		uint minStandbyWeight;
		address minStandbyAddress;
		uint standbysCount;

		// Committee entry barrier
		uint committeeSize;
		uint minCommitteeMemberWeight;
		address minCommitteeMemberAddress;
	}
	CommitteeInfo committeeInfo;

	modifier onlyElectionsContract() {
		require(msg.sender == contractRegistry.get("elections"), "caller is not the elections");

		_;
	}

	constructor(uint _minCommitteeSize, uint _maxCommitteeSize, uint _minimumWeight, uint _maxStandbys, uint256 _readyToSyncTimeout) public {
		require(_maxCommitteeSize > 0, "maxCommitteeSize must be larger than 0");
		require(_maxStandbys > 0, "maxStandbys must be larger than 0");
		require(_readyToSyncTimeout > 0, "readyToSyncTimeout must be larger than 0");
		require(_maxStandbys > 0, "maxStandbys must be larger than 0");
		settings = Settings({
			minCommitteeSize: _minCommitteeSize,
			maxCommitteeSize: _maxCommitteeSize,
			minimumWeight: _minimumWeight, // TODO do we need minimumWeight here in the constructor?
			minimumAddress: address(0), // TODO if we pass minimum weight, need to also pass min address
			maxStandbys: _maxStandbys,
			readyToSyncTimeout: _readyToSyncTimeout
		});
	}

	/*
	 * Methods restricted to other Orbs contracts
	 */

	/// @dev Called by: Elections contract
	/// Notifies a weight change for sorting to a relevant committee member.
    /// weight = 0 indicates removal of the member from the committee (for example on unregister, voteUnready, voteOut)
	function memberWeightChange(address addr, uint256 weight) external onlyElectionsContract returns (bool committeeChanged, bool standbysChanged) {
		Member memory member = loadMember(addr);
		if (member.data.isMember) {
			member.data.weight = weight;
			return _rankAndUpdateMember(member);
		}
		return (false, false);
	}

	function memberReadyToSync(address addr) external onlyElectionsContract returns (bool committeeChanged, bool standbysChanged) {
		Member memory member = loadMember(addr);
		if (member.data.isMember) {
			member.data.readyToSyncTimestamp = now;
			member.data.readyForCommittee = false;
			return _rankAndUpdateMember(member);
		}
		return (false, false);
	}

	function memberReadyForCommittee(address addr) external onlyElectionsContract returns (bool committeeChanged, bool standbysChanged) {
		Member memory member = loadMember(addr);
		if (member.data.isMember) {
			member.data.readyToSyncTimestamp = now;
			member.data.readyForCommittee = true;
			return _rankAndUpdateMember(member);
		}
		return (false, false);
	}

	function memberNotReadyToSync(address addr) external onlyElectionsContract returns (bool committeeChanged, bool standbysChanged) {
		Member memory member = loadMember(addr);
		if (member.data.isMember) {
			member.data.readyToSyncTimestamp = 0;
			member.data.readyForCommittee = false;
			return _rankAndUpdateMember(member);
		}
		return (false, false);
	}

	function addMember(address addr, uint256 weight) external onlyElectionsContract returns (bool committeeChanged, bool standbysChanged) {
		if (!members[addr].isMember) {
			Member memory member = Member({
				addr: addr,
				data: MemberData({
					isMember: true,
					readyForCommittee: false,
					readyToSyncTimestamp: 0,
					weight: weight,
					isStandby: false,
					inCommittee: false
				}),
				pos: -1
			});
			return _rankAndUpdateMember(member);
		}
		return (false, false);
	}

	/// @dev Called by: Elections contract
	/// Notifies a a member removal for example due to voteOut / voteUnready
	function removeMember(address addr) external onlyElectionsContract returns (bool committeeChanged, bool standbysChanged) {
		Member memory member = loadMember(addr);
		member.data.isMember = false;
		(committeeChanged, standbysChanged) = _rankAndUpdateMember(member);
		delete members[addr];
	}

	/// @dev Called by: Elections contract
	/// Returns the weight of the committee member with the lowest weight
	function getLowestCommitteeMember() external view returns (address addr) {
		return committeeInfo.minCommitteeMemberAddress;
	}

	// TODO getCommittee and getStandbys can be cheaper by saving a committee and standbys bitmaps on changes

	/// @dev Called by: Elections contract
	/// Returns the committee members and their weights
	function getCommittee() public view returns (address[] memory addrs, uint256[] memory weights) {
		Settings memory _settings = settings;
		address[] memory _participants = participants;

		Member[] memory _members = loadMembers(_participants, NullMember());
		(Member[] memory committee,,) = computeCommitteeAndStandbys(_members, _settings);

		address[] memory committeeAddrs = new address[](committee.length);
		uint[] memory _weights = new uint[](committee.length);
		for (uint i = 0; i < committee.length; i++) {
			committeeAddrs[i] = committee[i].addr;
			weights[i] = committee[i].data.weight;
		}
		return (committeeAddrs, _weights);
	}

	/// @dev Returns the standy (out of committee) members and their weights
	function getStandbys() public view returns (address[] memory addrs, uint256[] memory weights) {
		Settings memory _settings = settings;
		address[] memory _participants = participants;

		Member[] memory _members = loadMembers(_participants, NullMember());
		(,Member[] memory standbys,) = computeCommitteeAndStandbys(_members, _settings);

		address[] memory standbysAddrs = new address[](standbys.length);
		uint[] memory _weights = new uint[](standbys.length);
		for (uint i = 0; i < standbys.length; i++) {
			standbysAddrs[i] = standbys[i].addr;
			weights[i] = standbys[i].data.weight;
		}
		return (standbysAddrs, _weights);
	}

	/// @dev Called by: Elections contract
	/// Sets the minimal weight, and committee members
    /// Every member with sortingWeight >= minimumWeight OR in top minimumN is included in the committee
	function setMinimumWeight(uint256 _minimumWeight, address _minimumAddress, uint _minCommitteeSize) external onlyElectionsContract {
		settings.minimumWeight = _minimumWeight;
		settings.minimumAddress = _minimumAddress;
		settings.minCommitteeSize = _minCommitteeSize;

		updateOnParticipantChange(NullMember());
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
		(address[] memory _committee, uint256[] memory _weights) = getCommittee();
		return (_committee, _weights, _loadOrbsAddresses(_committee), _loadIps(_committee));
	}

    /// @dev returns the current standbys (out of commiteee) topology
	function getStandbysInfo() external view returns (address[] memory addrs, uint256[] memory weights, address[] memory orbsAddrs, bytes4[] memory ips) {
		(address[] memory _standbys, uint256[] memory _weights) = getStandbys();
		return (_standbys, _weights, _loadOrbsAddresses(_standbys), _loadIps(_standbys));
	}

	/*
	 * Private
	 */

	function NullMember() private pure returns (Member memory nullMember) {
		return Member({
			addr: address(0),
			pos: -1,
			data: MemberData({
				isMember: false,
				readyForCommittee: false,
				readyToSyncTimestamp: 0,
				weight: 0,
				isStandby: false,
				inCommittee: false
			})
		});
	}

	function isNullMember(Member memory member) private pure returns (bool) {
		return member.addr == address(0);
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

	function loadMember(address addr) private returns (Member memory) {
		return Member({
			addr: addr,
			data: members[addr],
			pos: -1 // TODO inconsistent as it ay be in participants list
		});
	}

	function _rankAndUpdateMember(Member memory member) private returns (bool committeeChanged, bool standbysChanged) {
		(committeeChanged, standbysChanged) = _rankMember(member);
		members[member.addr] = member.data;
	}

	function _rankMember(Member memory member) private returns (bool committeeChanged, bool standbysChanged) {
		bool isParticipant = member.data.inCommittee || member.data.isStandby;
		if (!isParticipant) {
			if (!qualifiedToJoin(member)) {
				return (false, false);
			}
			joinParticipant(member);
		}

		return updateOnParticipantChange(member);
	}

	function qualifiedToJoin(Member memory member) private view returns (bool) {
		return qualifiedToJoinAsStandby(member) || qualifiedToJoinCommittee(member);
	}

	function isReadyToSyncStale(Member memory member, Settings memory _settings) private view returns (bool) {
		return member.data.readyToSyncTimestamp <= now - _settings.readyToSyncTimeout;
	}

	function qualifiedToJoinAsStandby(Member memory member) private view returns (bool) {
		Settings memory _settings = settings;

		if (_settings.maxStandbys == 0) {
			return false;
		}

		if (isReadyToSyncStale(member, _settings)) {
			return false;
		}

		CommitteeInfo memory _committeeInfo = committeeInfo;

		// Room in standbys
		if (_committeeInfo.standbysCount < _settings.maxStandbys) {
			return true;
		}

		// A standby timed out
		if (member.data.readyToSyncTimestamp > _committeeInfo.oldestStandbyReadyToSyncStandbyTimestamp) {
			return true;
		}

		// A standby can be outranked by weight
		if (member.data.weight > _committeeInfo.minStandbyWeight) {
			return true;
		}

		return false;
	}

	function _compareMembersDataByCommitteeCriteria(
		address v1, uint256 v1Weight, bool v1Ready, bool v1InCommittee, bool v1TimedOut,
		address v2, uint256 v2Weight, bool v2Ready, bool v2InCommittee, bool v2TimedOut
	) private pure returns (int) {
		bool v1Stale = !v1InCommittee && v1TimedOut;
		bool v2Stale = !v2InCommittee && v2TimedOut;

		return v1Ready && !v2Ready ||
		v1Ready == v2Ready && !v1Stale && v2Stale ||
		v1Ready == v2Ready && v1Stale == v2Stale && v1Weight > v2Weight ||
		v1Ready == v2Ready && v1Stale == v2Stale && v1Weight == v2Weight && uint256(v1) > uint256(v2)
		? int(1) :
			v1Ready == v2Ready && v1Stale == v2Stale && v1Weight == v2Weight && uint256(v1) == uint256(v2) ? int(0)
		: int(-1);
	}

	function isAboveCommitteeEntryThreshold(Member memory member, Settings memory _settings) private view returns (bool) {
		return _compareMembersDataByCommitteeCriteria(member.addr, member.data.weight, true, true, false, _settings.minimumAddress, settings.minimumWeight, true, true, false) >= 0;
	}

	function outranksLowestCommitteeMember(Member memory member, CommitteeInfo memory _committeeInfo, Settings memory _settings) private view returns (bool) {
		return _compareMembersDataByCommitteeCriteria(
			member.addr, member.data.weight, member.data.readyForCommittee, member.data.inCommittee, isReadyToSyncStale(member, _settings), // TODO - in current usages member is never stale here, isReadyToSyncStale is redundant
			_committeeInfo.minCommitteeMemberAddress, _committeeInfo.minCommitteeMemberWeight, true, true, false) == 1;
	}

	function qualifiedToJoinCommittee(Member memory member) private view returns (bool) {
		if (!member.data.readyForCommittee) {
			return false;
		}

		Settings memory _settings = settings;

		if (isReadyToSyncStale(member, _settings)) {
			return false;
		}

		CommitteeInfo memory _committeeInfo = committeeInfo;

		if (_settings.minCommitteeSize > 0 && _committeeInfo.committeeSize < _settings.minCommitteeSize) {
			// Join due to min-committee requirement
			return true;
		}

		if (_committeeInfo.committeeSize < _settings.maxCommitteeSize && isAboveCommitteeEntryThreshold(member, _settings)) {
			return true;
		}

		if (_committeeInfo.committeeSize > 0 && outranksLowestCommitteeMember(member, _committeeInfo, _settings)) {
			return true;
		}

		return false;
	}

	function joinParticipant(Member memory member) private {
		CommitteeInfo memory _committeeInfo = committeeInfo; // TODO get as argument?
		if (_committeeInfo.freeParticipantSlotPos > participants.length) {
			participants.length++;
		}
		participants[_committeeInfo.freeParticipantSlotPos] = member.addr;
		member.pos = int(_committeeInfo.freeParticipantSlotPos);
	}

	function removeParticipant(Member memory member) private returns (bool removed) {
		if (member.pos == -1) {
			return false;
		}
		participants[uint(member.pos)] = address(0);
		member.pos = -1;
		return true;
	}

	function updateOnParticipantChange(Member memory member) private returns (bool committeeChanged, bool standbysChanged) { // TODO this is sometimes called with a member with address 0 indicating no member changed
		// TODO in all the state writes below, can skip the write for the given member as it will be written anyway

		committeeChanged = false;
		standbysChanged = false;

		Settings memory _settings = settings;
		address[] memory _participants = participants;

		Member[] memory _members = loadMembers(_participants, member);
		(Member[] memory committee,
		Member[] memory standbys,
		Member[] memory evicted) = computeCommitteeAndStandbys(_members, _settings);

		uint256 minCommitteeMemberWeight = uint256(-1);
		address minCommitteeMemberAddress = address(-1);
		for (uint i = 0; i < committee.length; i++) {
			if (!committee[i].data.inCommittee) {
				committee[i].data.inCommittee = true;
				committeeChanged = true;
				if (committee[i].data.isStandby) {
					committee[i].data.isStandby = false;
					standbysChanged = true;
				}

				members[committee[i].addr] = committee[i].data; // TODO we write the entire struct under the assumption that it takes one entry, if it doesn't it can be optimized
			}

			if (committee[i].data.weight < minCommitteeMemberWeight) {
				minCommitteeMemberWeight = committee[i].data.weight;
				minCommitteeMemberAddress = committee[i].addr;
			} else if (committee[i].data.weight == minCommitteeMemberWeight && uint(committee[i].addr) < uint(minCommitteeMemberAddress)) {
				minCommitteeMemberAddress = committee[i].addr;
			}
		}

		uint256 minStandbyTimestamp = uint256(-1);
		uint256 minStandbyWeight = uint256(-1);
		address minStandbyAddress = address(-1);
		for (uint i = 0; i < standbys.length; i++) {
			if (!standbys[i].data.isStandby) {
				committee[i].data.isStandby = true;
				standbysChanged = true;
				if (standbys[i].data.inCommittee) {
					standbys[i].data.inCommittee = false;
					standbys[i].data.readyToSyncTimestamp = now;
					committeeChanged = true;
				}
				members[standbys[i].addr] = standbys[i].data; // TODO we write the entire struct under the assumption that it takes one entry, if it doesn't it can be optimized
			}

			if (standbys[i].data.readyToSyncTimestamp < minStandbyTimestamp) {
				minStandbyTimestamp = standbys[i].data.readyToSyncTimestamp;
			}

			if (standbys[i].data.weight < minStandbyWeight) {
				minStandbyWeight = standbys[i].data.weight;
				minStandbyAddress = standbys[i].addr;
			} else if (standbys[i].data.weight == minStandbyWeight && uint(standbys[i].addr) < uint(minStandbyAddress)) {
				minStandbyAddress = standbys[i].addr;
			}
		}

		// Find a free slot in the participants list
		// Must run before eviction, as eviction clears the pos field of each evicted member
		uint freeSlot = _participants.length;
		if (evicted.length > 0) {
			freeSlot = uint(evicted[0].pos);
		}

		for (uint i = 0; i < evicted.length; i++) {
			bool changed = false;
			if (evicted[i].data.isStandby) {
				evicted[i].data.isStandby = false;
				standbysChanged = true;

				changed = true;
			} else if (evicted[i].data.inCommittee) {
				evicted[i].data.inCommittee = false;
				committeeChanged = true;

				changed = true;
			}

			bool removed = removeParticipant(evicted[i]);
			changed = changed || removed;
			if (changed) {
				members[evicted[i].addr] = evicted[i].data; // TODO we write the entire struct under the assumption that it takes one entry, if it doesn't it can be optimized
			}
		}

		committeeInfo = CommitteeInfo({
			freeParticipantSlotPos: freeSlot,

			// Standby entry barrier
			oldestStandbyReadyToSyncStandbyTimestamp: minStandbyTimestamp,
			minStandbyWeight: minStandbyWeight,
			minStandbyAddress: minStandbyAddress,
			standbysCount: standbys.length,

			// Committee entry barrier
			committeeSize: committee.length,
			minCommitteeMemberWeight: minCommitteeMemberWeight,
			minCommitteeMemberAddress: minCommitteeMemberAddress
		});

		if (!isNullMember(member)) {
			committeeChanged = committeeChanged || member.data.inCommittee;
			standbysChanged = standbysChanged || member.data.isStandby;
		}

		if (committeeChanged) {
			_notifyCommitteeChanged(committee);
		}

		if (standbysChanged) {
			_notifyStandbysChanged(standbys);
		}
	}

	function loadMembers(address[] memory _participants, Member memory preloadedMember) private view returns (Member[] memory _members) {
		uint nMembers = 0;
		for (uint i = 0; i < _participants.length; i++) { // TODO can be replaced by getting number from committee info (which is read anyway)
			if (_participants[i] != address(0)) {
				nMembers++;
			}
		}

		_members = new Member[](nMembers);
		for (uint i = 0; i < _participants.length; i++) {
			address addr = _participants[i];
			if (addr != address(0)) {
				if (!isNullMember(preloadedMember) && addr == preloadedMember.addr) {
					_members[i] = preloadedMember;
					preloadedMember.pos = int(i); // TODO ugly hack - when we load it, we don't know where it is in the participants list
				} else {
					_members[i] = Member({
						addr: addr,
						data: members[addr],
						pos: int(i)
					});
				}
			}
		}
	}

	function computeCommitteeAndStandbys(Member[] memory _members, Settings memory _settings) private view returns (Member[] memory committee,
		Member[] memory standbys,
		Member[] memory evicted) {

		Member[] memory list = new Member[](_members.length);
		for (uint i = 0; i < list.length; i++) {
			list[i] = _members[i];
		}

		quickSortPerCommitteeCriteria(list, _settings);

		uint committeeSize = 0;
		uint nStandbys = 0;

		for (uint i = 0; i < list.length; i++) {
			MemberData memory data = list[i].data;
			if (data.isMember && data.readyForCommittee && data.weight > 0 &&
				(data.inCommittee || !isReadyToSyncStale(list[i], _settings)) &&
				(committeeSize < _settings.minCommitteeSize || (
					committeeSize < _settings.maxCommitteeSize && isAboveCommitteeEntryThreshold(list[i], _settings)
				))
			) {
				committeeSize++;
			}
		}

		for (uint i = committeeSize; i < list.length; i++) {
			MemberData memory data = list[i].data;
			if (nStandbys < _settings.maxStandbys && data.isMember && !isReadyToSyncStale(list[i], _settings) && data.weight > 0) {
				nStandbys++;
			}
		}

		uint nEvicted = list.length - nStandbys - committeeSize;

		committee = new Member[](committeeSize);
		for (uint i = 0; i < committeeSize; i++) {
			committee[i] = list[i];
		}

		standbys = new Member[](nStandbys);
		for (uint i = 0; i < nStandbys; i++) {
			standbys[i] = list[committeeSize + i];
		}

		evicted = new Member[](nEvicted);
		for (uint i = 0; i < nEvicted; i++) {
			evicted[i] = list[committeeSize + nStandbys + i];
		}
	}

	function quickSortPerCommitteeCriteria(Member[] memory list, Settings memory _settings) private view {
		quickSort(list, int(0), int(list.length - 1), _settings);
	}

	function quickSort(Member[] memory arr, int left, int right, Settings memory _settings) private view {
		int i = left;
		int j = right;
		if(i==j) return;
		Member memory pivot = arr[uint(left + (right - left) / 2)];
		while (i <= j) {
			while (compareMembersPerCommitteeCriteria(arr[uint(i)], pivot, _settings) < 0) i++;
			while (compareMembersPerCommitteeCriteria(pivot, arr[uint(j)], _settings) < 0) j--;
			if (i <= j) {
				(arr[uint(i)], arr[uint(j)]) = (arr[uint(j)], arr[uint(i)]);
				i++;
				j--;
			}
		}
		if (left < j)
			quickSort(arr, left, j, _settings);
		if (i < right)
			quickSort(arr, i, right, _settings);
	}

	function compareMembersPerCommitteeCriteria(Member memory a, Member memory b, Settings memory _settings) private view returns (int) {
		return _compareMembersDataByCommitteeCriteria(
			a.addr, a.data.weight, a.data.readyForCommittee, a.data.inCommittee, isReadyToSyncStale(a, _settings),
			b.addr, b.data.weight, b.data.readyForCommittee, b.data.inCommittee, isReadyToSyncStale(b, _settings)
		);
	}

	function _notifyStandbysChanged(Member[] memory standbys) private {
		address[] memory standbysAddrs = new address[](standbys.length);
		uint[] memory weights = new uint[](standbys.length);
		for (uint i = 0; i < standbys.length; i++) {
			standbysAddrs[i] = standbys[i].addr;
			weights[i] = standbys[i].data.weight;
		}
		emit StandbysChanged(standbysAddrs, _loadOrbsAddresses(standbysAddrs), weights);
	}

	function _notifyCommitteeChanged(Member[] memory committee) private {
		address[] memory committeeAddrs = new address[](committee.length);
		uint[] memory weights = new uint[](committee.length);
		for (uint i = 0; i < committee.length; i++) {
			committeeAddrs[i] = committee[i].addr;
			weights[i] = committee[i].data.weight;
		}
		emit CommitteeChanged(committeeAddrs, _loadOrbsAddresses(committeeAddrs), weights);
	}

	// OLD CODE STARTS HERE
//
//	function _appendToTopology(address validator, uint entryPos) private returns (bool committeeChanged, bool standbysChanged) {
//		assert(entryPos <= participants.length);
//		if (entryPos == participants.length) {
//			participants.length++;
//		}
//		participants[entryPos] = validator;
//
//		(uint newPos, uint prevCommitteeSize, uint newCommitteeSize, uint newStandbySize) = _repositionTopologyMember(entryPos);
//
//		bool joinedCommittee = newPos < newCommitteeSize;
//		bool joinedStandbys = !joinedCommittee && newPos < participants.length;
//		bool otherCommitteeMemberBecameStandby = joinedCommittee && prevCommitteeSize == newCommitteeSize;
//
//		committeeChanged = joinedCommittee;
//		if (committeeChanged) {
//			_notifyCommitteeChanged();
//		}
//
//		standbysChanged = joinedStandbys || otherCommitteeMemberBecameStandby;
//		if (standbysChanged) {
//			_notifyStandbysChanged();
//		}
//	}
//
//	function _onTopologyModification() private returns (uint prevCommitteeSize, uint newCommitteeSize) {
//		newCommitteeSize = committeeSize;
//		prevCommitteeSize = newCommitteeSize;
//		while (newCommitteeSize > 0 && (participants.length < newCommitteeSize || !isReadyForCommittee(participants[newCommitteeSize - 1]) || getValidatorWeight(participants[newCommitteeSize - 1]) == 0 || newCommitteeSize - 1 >= minCommitteeSize && (getValidatorWeight(participants[newCommitteeSize - 1]) < minimumWeight || getValidatorWeight(participants[newCommitteeSize - 1]) == minimumWeight && uint256(participants[newCommitteeSize - 1]) < uint256(minimumAddress)))) {
//			newCommitteeSize--;
//		}
//		while (participants.length > newCommitteeSize && newCommitteeSize < maxCommitteeSize && isReadyForCommittee(participants[newCommitteeSize]) && getValidatorWeight(participants[newCommitteeSize]) > 0 && (newCommitteeSize < minCommitteeSize || getValidatorWeight(participants[newCommitteeSize]) > minimumWeight || getValidatorWeight(participants[newCommitteeSize]) == minimumWeight && uint256(participants[newCommitteeSize]) >= uint256(minimumAddress))) {
//			newCommitteeSize++;
//		}
//		committeeSize = newCommitteeSize;
//		_refreshReadyForCommitteeCount();
//		_refreshOldestReadyToSyncStandbyPos();
//		return (prevCommitteeSize, newCommitteeSize);
//	}
//
//	function _refreshReadyForCommitteeCount() private returns (uint, uint) {
//		uint newCount = readyForCommitteeCount;
//		uint prevCount = newCount;
//		while (newCount > 0 && (participants.length < newCount || !isReadyForCommittee(participants[newCount - 1]))) {
//			newCount--;
//		}
//		while (participants.length > newCount && isReadyForCommittee(participants[newCount])) {
//			newCount++;
//		}
//		readyForCommitteeCount = newCount;
//		return (prevCount, newCount);
//	}
//
//	function _refreshOldestReadyToSyncStandbyPos() private {
//		uint256 oldestTimestamp = uint(-1);
//		uint oldestPos = uint(-1);
//		for (uint i = committeeSize; i < participants.length; i++) {
//			uint t = members[participants[i]].readyToSyncTimestamp;
//			if (t < oldestTimestamp) {
//				oldestTimestamp = t;
//				oldestPos = i;
//			}
//		}
//		oldestReadyToSyncStandbyPos = int(oldestPos);
//	}
//
//	function _compareValidators(address v1, address v2) private view returns (int) {
//		bool v1Ready = isReadyForCommittee(v1);
//		uint256 v1Weight = getValidatorWeight(v1);
//		bool v2Ready = isReadyForCommittee(v2);
//		uint256 v2Weight = getValidatorWeight(v2);
//		return _compareMembersDataByCommitteeCriteria(v1, v1Weight, v1Ready, v2, v2Weight, v2Ready);
//	}
//
//	function _replace(uint p1, uint p2) private {
//		address tempValidator = participants[p1];
//		participants[p1] = participants[p2];
//		participants[p2] = tempValidator;
//	}
//
//	function _repositionTopologyMember(uint memberPos) private returns (uint newPos, uint prevCommitteeSize, uint newCommitteeSize, uint newStandbySize) {
//		uint topologySize = participants.length;
//		assert(topologySize > memberPos);
//
//		while (memberPos > 0 && _compareValidators(participants[memberPos], participants[memberPos - 1]) > 0) {
//			_replace(memberPos-1, memberPos);
//			memberPos--;
//		}
//
//		while (memberPos < topologySize - 1 && _compareValidators(participants[memberPos + 1], participants[memberPos]) > 0) {
//			_replace(memberPos, memberPos+1);
//			memberPos++;
//		}
//
//		newPos = memberPos;
//
//		(prevCommitteeSize, newCommitteeSize) = _onTopologyModification();
//
//		newStandbySize = topologySize - newCommitteeSize;
//		if (newStandbySize > maxStandbys){
//			// need to evict exactly one standby - todo assert?
//			(bool found, uint pos) = findTimedOutStandby();
//			if (found) {
//				_evict(pos); // evict timed-out
//			} else {
//				(bool lowestWeightFound, uint lowestWeightPos, uint256 lowestWeight) = findLowestWeightStandby();
//				_evict(lowestWeightPos); // evict lowest weight
//			}
//			_onTopologyModification();
//			newStandbySize = maxStandbys;
//		}
//	}
//
//	function _adjustPositionInTopology(uint pos) private returns (bool committeeChanged, bool standbysChanged) {
//		// TODO if a validator leaves committee it may be replaced by a timed-out, ready-for-committee standby
//		(uint newPos, uint prevCommitteeSize, uint newCommitteeSize, uint newStandbySize) = _repositionTopologyMember(pos);
//
//		bool inCommitteeBefore = pos < prevCommitteeSize;
//		bool isStandbyBefore = !inCommitteeBefore;
//
//		bool inCommitteeAfter = newPos < newCommitteeSize;
//		bool isStandbyAfter = !inCommitteeAfter;
//
//		committeeChanged = inCommitteeBefore || inCommitteeAfter;
//		if (committeeChanged) {
//			_notifyCommitteeChanged();
//		}
//
//		standbysChanged = isStandbyBefore || isStandbyAfter;
//		if (standbysChanged) {
//			_notifyStandbysChanged();
//		}
//	}
//
//	function findTimedOutStandby() private view returns (bool found, uint pos) {
//		pos = uint(oldestReadyToSyncStandbyPos);
//		found = int(pos) >= 0 && pos < participants.length && isReadyToSyncStale(participants[pos]);
//	}
//
//	function findLowestWeightStandby() private view returns (bool found, uint pos, uint weight) {
//		if (participants.length == committeeSize) {
//			return (false, 0, 0);
//		}
//
//		address v1 = participants[participants.length - 1];
//		uint256 v1Weight = getValidatorWeight(v1);
//		if (readyForCommitteeCount <= committeeSize) {
//			return (true, participants.length - 1, v1Weight);
//		}
//
//		address v2 = participants[readyForCommitteeCount - 1];
//		uint256 v2Weight = getValidatorWeight(v2);
//		if (v2Weight < v1Weight) {
//			return (true, readyForCommitteeCount - 1, v2Weight);
//		}
//
//		return (true, participants.length - 1, v1Weight);
//	}
//
//	function _findInTopology(address v) private view returns (uint, bool) {
//		uint l =  participants.length;
//		for (uint i=0; i < l; i++) {
//			if (participants[i] == v) {
//				return (i, true);
//			}
//		}
//		return (0, false);
//	}
//
//	function _removeFromTopology(address addr) private returns (bool committeeChanged, bool standbysChanged) {
//		(uint pos, bool inTopology) = _findInTopology(addr);
//		if (!inTopology) {
//			return (false, false);
//		}
//
//		_evict(pos);
//
//		(uint prevCommitteeSize, uint currentCommitteeSize) = _onTopologyModification();
//
//		bool committeeSizeChanged = prevCommitteeSize != currentCommitteeSize;
//		bool wasInCommittee = committeeSizeChanged || pos < prevCommitteeSize;
//		bool standbyJoinedCommittee = wasInCommittee && !committeeSizeChanged;
//
//		committeeChanged = wasInCommittee;
//		if (committeeChanged) {
//			_notifyCommitteeChanged();
//		}
//
//		standbysChanged = !wasInCommittee || standbyJoinedCommittee;
//		if (standbysChanged) {
//			_notifyStandbysChanged();
//		}
//	}
//
//	function _evict(uint pos) private {
//		assert(participants.length > 0);
//		assert(pos < participants.length);
//
//		for (uint p = pos; p < participants.length - 1; p++) {
//			participants[p] = participants[p + 1];
//		}
//
//		participants.length = participants.length - 1;
//	}
//
//	function _loadWeights(address[] memory addrs) private view returns (uint256[] memory) {
//		uint256[] memory weights = new uint256[](addrs.length);
//		for (uint i = 0; i < addrs.length; i++) {
//			weights[i] = getValidatorWeight(addrs[i]);
//		}
//		return weights;
//	}
//
//	function _loadStandbys() private view returns (address[] memory) {
//		uint _committeeSize = committeeSize;
//		uint standbysCount = participants.length - _committeeSize;
//		address[] memory standbys = new address[](standbysCount);
//		for (uint i = 0; i < standbysCount; i++) {
//			standbys[i] = participants[_committeeSize + i];
//		}
//		return standbys;
//	}
//
//	function _loadCommittee() private view returns (address[] memory) {
//		uint _committeeSize = committeeSize;
//		address[] memory committee = new address[](_committeeSize);
//		for (uint i = 0; i < _committeeSize; i++) {
//			committee[i] = participants[i];
//		}
//		return committee;
//	}
//
//	function getValidatorWeight(address addr) private view returns (uint256 weight) {
//		return members[addr].weight;
//	}
//
	function validatorsRegistration() private view returns (IValidatorsRegistration) {
		return IValidatorsRegistration(contractRegistry.get("validatorsRegistration"));
	}
//
//	function getTopology() external view returns (address[] memory) { // TODO remove
//		return participants;
//	}
//
//	function isReadyToSync(address addr) private view returns (bool) {
//		return members[addr].readyToSyncTimestamp != 0;
//	}
//
//	function isReadyForCommittee(address addr) private view returns (bool) {
//		return members[addr].readyForCommittee;
//	}
}
