pragma solidity 0.5.16;

import "./spec_interfaces/IContractRegistry.sol";
import "./spec_interfaces/ICommittee.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "./spec_interfaces/IValidatorsRegistration.sol";

/// @title Elections contract interface
contract Committee is ICommittee, Ownable {
	address[] participants;

	struct MemberData { // can be reduced to 1 state entry
		bool isMember; // exists
		bool readyForCommittee;
		uint256 readyToSyncTimestamp;
		uint256 weight;

		bool isStandby;
		bool inCommittee;
	}
	mapping (address => MemberData) membersData;

	struct Member {
		address addr;
		MemberData data;
	} // Never in state, only in memory

	struct Participant {
		address addr;
		MemberData data;
		uint pos;
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
		uint oldestStandbyReadyToSyncStandbyTimestamp; // todo 4 bytes?
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
		MemberData memory memberData = membersData[addr];
		if (memberData.isMember) {
			memberData.weight = weight;
			return _rankAndUpdateMember(Member({
				addr: addr,
				data: memberData
			}));
		}
		return (false, false);
	}

	function memberReadyToSync(address addr) external onlyElectionsContract returns (bool committeeChanged, bool standbysChanged) {
		MemberData memory memberData = membersData[addr];
		if (memberData.isMember) {
			memberData.readyToSyncTimestamp = now;
			memberData.readyForCommittee = false;
			return _rankAndUpdateMember(Member({
				addr: addr,
				data: memberData
			}));
		}
		return (false, false);
	}

	function memberReadyForCommittee(address addr) external onlyElectionsContract returns (bool committeeChanged, bool standbysChanged) {
		MemberData memory memberData = membersData[addr];
		if (memberData.isMember) {
			memberData.readyToSyncTimestamp = now;
			memberData.readyForCommittee = true;
			return _rankAndUpdateMember(Member({
				addr: addr,
				data: memberData
			}));
		}
		return (false, false);
	}

	function memberNotReadyToSync(address addr) external onlyElectionsContract returns (bool committeeChanged, bool standbysChanged) {
		MemberData memory memberData = membersData[addr];
		if (memberData.isMember) {
			memberData.readyToSyncTimestamp = 0;
			memberData.readyForCommittee = false;
			return _rankAndUpdateMember(Member({
				addr: addr,
				data: memberData
			}));
		}
		return (false, false);
	}

	function addMember(address addr, uint256 weight) external onlyElectionsContract returns (bool committeeChanged, bool standbysChanged) {
		if (!membersData[addr].isMember) {
			return _rankAndUpdateMember(Member({
				addr: addr,
				data: MemberData({
					isMember: true,
					readyForCommittee: false,
					readyToSyncTimestamp: 0,
					weight: weight,
					isStandby: false,
					inCommittee: false
				})
			}));
		}
		return (false, false);
	}

	/// @dev Called by: Elections contract
	/// Notifies a a member removal for example due to voteOut / voteUnready
	function removeMember(address addr) external onlyElectionsContract returns (bool committeeChanged, bool standbysChanged) {
		MemberData memory memberData = membersData[addr];
		memberData.isMember = false;
		(committeeChanged, standbysChanged) = _rankAndUpdateMember(Member({
			addr: addr,
			data: memberData
		}));
		delete membersData[addr];
	}

	/// @dev Called by: Elections contract
	/// Returns the weight of the committee member with the lowest weight
	function getLowestCommitteeMember() external view returns (address addr) {
		return committeeInfo.minCommitteeMemberAddress;
	}

	// TODO getCommittee and getStandbys can be cheaper by saving a committee and standbys bitmaps on changes

	/// @dev Called by: Elections contract
	/// Returns the committee members and their weights
	function getCommittee() external view returns (address[] memory addrs, uint256[] memory weights) {
		return _getCommittee();
	}

	/// @dev Returns the standy (out of committee) members and their weights
	function getStandbys() external view returns (address[] memory addrs, uint256[] memory weights) {
		return _getStandbys();
	}

	/// @dev Called by: Elections contract
	/// Returns the committee members and their weights
	function _getCommittee() public view returns (address[] memory addrs, uint256[] memory weights) {
		Settings memory _settings = settings;
		address[] memory _participants = participants;

		(Participant[] memory _members,) = loadParticipants(_participants, NullMember());
		Participant[] memory committee = computeCommitteeAndStandbys(_members, _settings).committee;

		addrs = new address[](committee.length);
		weights = new uint[](committee.length);
		for (uint i = 0; i < committee.length; i++) {
			addrs[i] = committee[i].addr;
			weights[i] = committee[i].data.weight;
		}
		return (addrs, weights);
	}

	/// @dev Returns the standby (out of committee) members and their weights
	function _getStandbys() public view returns (address[] memory addrs, uint256[] memory weights) {
		Settings memory _settings = settings;
		address[] memory _participants = participants;

		(Participant[] memory _members,) = loadParticipants(_participants, NullMember());
		Participant[] memory standbys = computeCommitteeAndStandbys(_members, _settings).standbys;

		addrs = new address[](standbys.length);
		weights = new uint[](standbys.length);
		for (uint i = 0; i < standbys.length; i++) {
			addrs[i] = standbys[i].addr;
			weights[i] = standbys[i].data.weight;
		}
		return (addrs, weights);
	}

	/// @dev Called by: Elections contract
	/// Sets the minimal weight, and committee members
    /// Every member with sortingWeight >= minimumWeight OR in top minimumN is included in the committee
	function setMinimumWeight(uint256 _minimumWeight, address _minimumAddress, uint _minCommitteeSize) external onlyElectionsContract {
		settings.minimumWeight = _minimumWeight;
		settings.minimumAddress = _minimumAddress;
		settings.minCommitteeSize = _minCommitteeSize;

		updateOnMemberChange(NullMember());
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
		(address[] memory _committee, uint256[] memory _weights) = _getCommittee();
		return (_committee, _weights, _loadOrbsAddresses(_committee), _loadIps(_committee));
	}

    /// @dev returns the current standbys (out of commiteee) topology
	function getStandbysInfo() external view returns (address[] memory addrs, uint256[] memory weights, address[] memory orbsAddrs, bytes4[] memory ips) {
		(address[] memory _standbys, uint256[] memory _weights) = _getStandbys();
		return (_standbys, _weights, _loadOrbsAddresses(_standbys), _loadIps(_standbys));
	}

	/*
	 * Private
	 */

	function NullMember() private pure returns (Member memory nullMember) {
		return Member({
			addr: address(0),
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

	function _rankAndUpdateMember(Member memory member) private returns (bool committeeChanged, bool standbysChanged) {
		(committeeChanged, standbysChanged) = _rankMember(member);
		membersData[member.addr] = member.data;
	}

	function _rankMember(Member memory member) private returns (bool committeeChanged, bool standbysChanged) {
		bool isParticipant = member.data.inCommittee || member.data.isStandby;
		if (!isParticipant) {
			if (!qualifiedToJoin(member)) {
				return (false, false);
			}
			joinMemberAsParticipant(member);
		}

		return updateOnMemberChange(member);
	}

	function qualifiedToJoin(Member memory member) private view returns (bool) {
		return qualifiedToJoinAsStandby(member) || qualifiedToJoinCommittee(member);
	}

	function isReadyToSyncStale(uint256 timestamp, Settings memory _settings) private view returns (bool) {
		return timestamp <= now - _settings.readyToSyncTimeout;
	}

	function qualifiedToJoinAsStandby(Member memory member) private view returns (bool) {
		Settings memory _settings = settings;

		if (_settings.maxStandbys == 0) {
			return false;
		}

		if (isReadyToSyncStale(member.data.readyToSyncTimestamp, _settings)) {
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
		address v1, MemberData memory v1Data, bool v1TimedOut,
		address v2, MemberData memory v2Data, bool v2TimedOut
	) private pure returns (int) {
		v1TimedOut = !v1Data.inCommittee && v1TimedOut;
		v2TimedOut = !v2Data.inCommittee && v2TimedOut;

		bool v1Member = v1Data.isMember && v1Data.weight != 0 && v1Data.readyToSyncTimestamp != 0;
		bool v2Member = v2Data.isMember && v2Data.weight != 0 && v2Data.readyToSyncTimestamp != 0;

		return v1Member && !v2Member || v1Member == v2Member && (
			v1Data.readyForCommittee && !v2Data.readyForCommittee || v1Data.readyForCommittee == v2Data.readyForCommittee && (
				!v1TimedOut && v2TimedOut || v1TimedOut == v2TimedOut && (
					v1Data.weight > v2Data.weight || v1Data.weight == v2Data.weight && (
						uint256(v1) > uint256(v2)
		))))
		? int(1) :
			v1Member == v2Member && v1Data.readyForCommittee == v2Data.readyForCommittee && v1TimedOut == v2TimedOut && v1Data.weight == v2Data.weight && uint256(v1) == uint256(v2) ? int(0)
		: int(-1);
	}

	function isAboveCommitteeEntryThreshold(Member memory member, Settings memory _settings) private view returns (bool) {
		return _compareMembersDataByCommitteeCriteria(
			member.addr, member.data, false,
			_settings.minimumAddress, MemberData({
				isMember: true,
				readyForCommittee: true,
				readyToSyncTimestamp: now,
				weight: _settings.minimumWeight,

				isStandby: false,
				inCommittee: true
			}), false
		) >= 0;
	}

	function outranksLowestCommitteeMember(Member memory member, CommitteeInfo memory _committeeInfo, Settings memory _settings) private view returns (bool) {
		return _compareMembersDataByCommitteeCriteria(
			member.addr, member.data, isReadyToSyncStale(member.data.readyToSyncTimestamp, _settings), // TODO - in current usages member is never stale here, isReadyToSyncStale is redundant
			_committeeInfo.minCommitteeMemberAddress, MemberData({
				isMember: true,
				readyForCommittee: true,
				readyToSyncTimestamp: now,
				weight: _committeeInfo.minCommitteeMemberWeight,
				isStandby: false,
				inCommittee: true
			}), false
		) == 1;
	}

	function qualifiedToJoinCommittee(Member memory member) private view returns (bool) {
		if (!member.data.readyForCommittee) {
			return false;
		}

		Settings memory _settings = settings;

		if (isReadyToSyncStale(member.data.readyToSyncTimestamp, _settings)) {
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

	function joinMemberAsParticipant(Member memory member) private {
		CommitteeInfo memory _committeeInfo = committeeInfo; // TODO get as argument?
		if (_committeeInfo.freeParticipantSlotPos >= participants.length) {
			participants.length++;
		}
		require(_committeeInfo.freeParticipantSlotPos < participants.length, "freeParticipantSlotPos out of range");
		participants[_committeeInfo.freeParticipantSlotPos] = member.addr;
	}

	function removeParticipant(Participant memory participant) private {
		participants[participant.pos] = address(0);
	}

	function writeParticipantDataToState(Participant memory member) private {
		membersData[member.addr] = member.data;
	}

	function updateOnMemberChange(Member memory member) private returns (bool committeeChanged, bool standbysChanged) { // TODO this is sometimes called with a member with address 0 indicating no member changed
		// TODO in all the state writes below, can skip the write for the given member as it will be written anyway

		committeeChanged = false;
		standbysChanged = false;

		Settings memory _settings = settings;
		address[] memory _participants = participants;

		(Participant[] memory _members, uint firstFreeSlot) = loadParticipants(_participants, member); // override stored member with preloaded one
		(CommitteeAndStandbys memory o) = computeCommitteeAndStandbys(_members, _settings);

		uint256 minCommitteeMemberWeight = uint256(-1);
		address minCommitteeMemberAddress = address(-1);
		uint newParticipantsLength = 0;
		for (uint i = 0; i < o.committee.length; i++) {
			if (!o.committee[i].data.inCommittee) {
				o.committee[i].data.inCommittee = true;
				committeeChanged = true;
				if (o.committee[i].data.isStandby) {
					o.committee[i].data.isStandby = false;
					standbysChanged = true;
				}

				writeParticipantDataToState(o.committee[i]); // TODO we write the entire struct under the assumption that it takes one entry, if it doesn't it can be optimized
			}

			if (o.committee[i].data.weight < minCommitteeMemberWeight) {
				minCommitteeMemberWeight = o.committee[i].data.weight;
				minCommitteeMemberAddress = o.committee[i].addr;
			} else if (o.committee[i].data.weight == minCommitteeMemberWeight && uint(o.committee[i].addr) < uint(minCommitteeMemberAddress)) {
				minCommitteeMemberAddress = o.committee[i].addr;
			}

			if (o.committee[i].pos + 1 >= newParticipantsLength) {
				newParticipantsLength = o.committee[i].pos + 1;
			}
		}

		uint256 minStandbyTimestamp = uint256(-1);
		uint256 minStandbyWeight = uint256(-1);
		address minStandbyAddress = address(-1);
		for (uint i = 0; i < o.standbys.length; i++) {
			if (!o.standbys[i].data.isStandby) {
				o.standbys[i].data.isStandby = true;
				standbysChanged = true;
				if (o.standbys[i].data.inCommittee) {
					o.standbys[i].data.inCommittee = false;
					o.standbys[i].data.readyToSyncTimestamp = now;
					committeeChanged = true;
				}
				writeParticipantDataToState(o.standbys[i]); // TODO we write the entire struct under the assumption that it takes one entry, if it doesn't it can be optimized
			}

			if (o.standbys[i].data.readyToSyncTimestamp < minStandbyTimestamp) {
				minStandbyTimestamp = o.standbys[i].data.readyToSyncTimestamp;
			}

			if (o.standbys[i].data.weight < minStandbyWeight) {
				minStandbyWeight = o.standbys[i].data.weight;
				minStandbyAddress = o.standbys[i].addr;
			} else if (o.standbys[i].data.weight == minStandbyWeight && uint(o.standbys[i].addr) < uint(minStandbyAddress)) {
				minStandbyAddress = o.standbys[i].addr;
			}

			if (o.standbys[i].pos + 1 >= newParticipantsLength) {
				newParticipantsLength = o.standbys[i].pos + 1;
			}
		}

		for (uint i = 0; i < o.evicted.length; i++) {
			bool changed = false;
			if (o.evicted[i].data.isStandby) {
				o.evicted[i].data.isStandby = false;
				standbysChanged = true;

				changed = true;
			} else if (o.evicted[i].data.inCommittee) {
				o.evicted[i].data.inCommittee = false;
				committeeChanged = true;

				changed = true;
			}

			if (o.evicted[i].pos < firstFreeSlot) {
				firstFreeSlot = o.evicted[i].pos;
			}

			removeParticipant(o.evicted[i]);

			if (changed) {
				writeParticipantDataToState(o.evicted[i]); // TODO we write the entire struct under the assumption that it takes one entry, if it doesn't it can be optimized
			}
		}

		if (_participants.length > newParticipantsLength) {
			participants.length = newParticipantsLength;
		}

		committeeInfo = CommitteeInfo({
			freeParticipantSlotPos: firstFreeSlot,

			// Standby entry barrier
			oldestStandbyReadyToSyncStandbyTimestamp: minStandbyTimestamp,
			minStandbyWeight: minStandbyWeight,
			minStandbyAddress: minStandbyAddress,
			standbysCount: o.standbys.length,

			// Committee entry barrier
			committeeSize: o.committee.length,
			minCommitteeMemberWeight: minCommitteeMemberWeight,
			minCommitteeMemberAddress: minCommitteeMemberAddress
		});

		if (!isNullMember(member)) {
			committeeChanged = committeeChanged || member.data.inCommittee;
			standbysChanged = standbysChanged || member.data.isStandby;
		}

		if (committeeChanged) {
			_notifyCommitteeChanged(o.committee);
		}

		if (standbysChanged) {
			_notifyStandbysChanged(o.standbys);
		}
	}

	function loadParticipants(address[] memory participantsAddrs, Member memory preloadedMember) private view returns (Participant[] memory _participants, uint firstFreeSlot) {
		uint nParticipants = 0;
		for (uint i = 0; i < participantsAddrs.length; i++) { // TODO can be replaced by getting number from committee info (which is read anyway)
			if (participantsAddrs[i] != address(0)) {
				nParticipants++;
			}
		}

		firstFreeSlot = participantsAddrs.length;
		_participants = new Participant[](nParticipants);
		uint mInd = 0;
		for (uint i = 0; i < participantsAddrs.length; i++) {
			address addr = participantsAddrs[i];
			if (addr != address(0)) {
				_participants[mInd] = Participant({
					addr: addr,
					data: addr == preloadedMember.addr ? preloadedMember.data : membersData[addr],
					pos: i
				});
				mInd++;
			} else if (firstFreeSlot == 0) {
				firstFreeSlot = i;
			}
		}
	}

	struct CommitteeAndStandbys {
		Participant[] committee;
		Participant[] standbys;
		Participant[] evicted;
	}

	function computeCommitteeAndStandbys(Participant[] memory _participants, Settings memory _settings) private view returns (CommitteeAndStandbys memory out) {

		Participant[] memory list = slice(_participants, 0, _participants.length); // TODO can be omitted?

		quickSortPerCommitteeCriteria(list, _settings);

		uint committeeSize = 0;
		uint nStandbys = 0;

		for (uint i = 0; i < list.length; i++) {
			MemberData memory data = list[i].data;
			if (data.isMember && data.readyForCommittee && data.readyToSyncTimestamp != 0 && data.weight > 0 &&
				(data.inCommittee || !isReadyToSyncStale(list[i].data.readyToSyncTimestamp, _settings)) &&
				(committeeSize < _settings.minCommitteeSize || (
					committeeSize < _settings.maxCommitteeSize && isAboveCommitteeEntryThreshold(Member({addr: list[i].addr, data: list[i].data}), _settings)
				))
			) {
				committeeSize++;
			} else {
				break; // todo refactor this out
			}
		}

		quickSortPerStandbysCriteria(list, _settings, int(committeeSize), int(list.length - 1));

		for (uint i = committeeSize; i < list.length; i++) {
			MemberData memory data = list[i].data;
			if (nStandbys < _settings.maxStandbys && data.isMember && data.readyToSyncTimestamp != 0 && data.weight > 0) {
				nStandbys++;
			} else {
				break;
			}
		}

		uint nEvicted = list.length - nStandbys - committeeSize;

		Participant[] memory committee = slice(list, 0, committeeSize);
		Participant[] memory standbys = slice(list, committeeSize, nStandbys);
		Participant[] memory evicted = slice(list, committeeSize + nStandbys, nEvicted);

		return CommitteeAndStandbys({
			committee: committee,
			standbys: standbys,
			evicted: evicted
		});
	}

	enum Comparator {Committee, Standbys}

	function quickSortPerCommitteeCriteria(Participant[] memory list, Settings memory _settings) private view {
		quickSort(list, int(0), int(list.length - 1), _settings, Comparator.Committee);
	}

	function quickSortPerStandbysCriteria(Participant[] memory list, Settings memory _settings, int from, int to) private view {
		quickSort(list, int(from), int(to), _settings, Comparator.Standbys);
	}

	function quickSort(Participant[] memory arr, int left, int right, Settings memory _settings, Comparator comparator) private view {
		int i = left;
		int j = right;
		if(i>=j) return;
		Participant memory pivot = arr[uint(left + (right - left) / 2)];
		while (i <= j) {
			while (compareMembers(arr[uint(i)], pivot, _settings, comparator) > 0) i++;
			while (compareMembers(pivot, arr[uint(j)], _settings, comparator) > 0) j--;
			if (i <= j) {
				(arr[uint(i)], arr[uint(j)]) = (arr[uint(j)], arr[uint(i)]);
				i++;
				j--;
			}
		}
		if (left < j)
			quickSort(arr, left, j, _settings, comparator);
		if (i < right)
			quickSort(arr, i, right, _settings, comparator);
	}

	function compareMembers(Participant memory a, Participant memory b, Settings memory _settings, Comparator comparator) private view returns (int) {
		if (comparator == Comparator.Committee) {
			return compareMembersPerCommitteeCriteria(a, b, _settings);
		} else {
			return compareMembersPerStandbyCriteria(a, b, _settings);
		}
	}

	function compareMembersPerCommitteeCriteria(Participant memory a, Participant memory b, Settings memory _settings) private view returns (int) {
		return _compareMembersDataByCommitteeCriteria(
			a.addr, a.data, isReadyToSyncStale(a.data.readyToSyncTimestamp, _settings),
			b.addr, b.data, isReadyToSyncStale(b.data.readyToSyncTimestamp, _settings)
		);
	}

	function compareMembersPerStandbyCriteria(Participant memory v1, Participant memory v2, Settings memory _settings) private view returns (int) {
		bool v1TimedOut = isReadyToSyncStale(v1.data.readyToSyncTimestamp, _settings);
		bool v2TimedOut = isReadyToSyncStale(v2.data.readyToSyncTimestamp, _settings);

		bool v1Member = v1.data.isMember && v1.data.weight != 0 && v1.data.readyToSyncTimestamp != 0;
		bool v2Member = v2.data.isMember && v2.data.weight != 0 && v2.data.readyToSyncTimestamp != 0;

		return v1Member && !v2Member || v1Member == v2Member && (
					!v1TimedOut && v2TimedOut || v1TimedOut == v2TimedOut && (
						v1.data.weight > v2.data.weight || v1.data.weight == v2.data.weight && (
							uint256(v1.addr) > uint256(v2.addr)
		))) ? int(1)
		: v1Member == v2Member && v1TimedOut == v2TimedOut && v1.data.weight == v2.data.weight && v1.addr == v2.addr ? int(0)
		: int(-1);
	}

	function _notifyStandbysChanged(Participant[] memory standbys) private {
		(address[] memory addrs, uint256[] memory weights) = toAddrsWeights(standbys);
		emit StandbysChanged(addrs, _loadOrbsAddresses(addrs), weights);
	}

	function _notifyCommitteeChanged(Participant[] memory committee) private {
		(address[] memory addrs, uint256[] memory weights) = toAddrsWeights(committee);
		emit CommitteeChanged(addrs, _loadOrbsAddresses(addrs), weights);
	}

	function toAddrsWeights(Participant[] memory list) private pure returns (address[] memory addrs, uint256[] memory weights) {
		addrs = new address[](list.length);
		weights = new uint256[](list.length);
		for (uint i = 0; i < list.length; i++) {
			addrs[i] = list[i].addr;
			weights[i] = list[i].data.weight;
		}
	}

	function validatorsRegistration() private view returns (IValidatorsRegistration) {
		return IValidatorsRegistration(contractRegistry.get("validatorsRegistration"));
	}

	function slice(Participant[] memory list, uint from, uint count) private pure returns (Participant[] memory sliced) {
		sliced = new Participant[](count);
		for (uint i = 0; i < count; i++) {
			sliced[i] = list[from + i];
		}
	}

}
