pragma solidity 0.5.16;

import "./spec_interfaces/IContractRegistry.sol";
import "./spec_interfaces/ICommittee.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "./spec_interfaces/IValidatorsRegistration.sol";
import "@openzeppelin/contracts/math/Math.sol";

/// @title Elections contract interface
contract Committee is ICommittee, Ownable {
	address[] participants;

	struct MemberData { // TODO can be reduced to 1 state entry
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

	struct Settings { // TODO can be reduced to 2-3 state entries
		address minimumAddress;
		uint minimumWeight;
		uint minCommitteeSize;
		uint maxCommitteeSize;
		uint maxStandbys;
		uint readyToSyncTimeout;
	}
	Settings settings;

	// Derived properties (TODO can be reduced to 2-3 state entries)
	struct CommitteeInfo {
		uint freeParticipantSlotPos;

		// Standby entry barrier
		uint oldestReadyToSyncStandbyTimestamp; // todo 4 bytes?
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
		(Participant[] memory members,) = loadParticipants(participants, NullMember());
		Participant[] memory committee = computeCommittee(members, settings).committee;
		return toAddrsWeights(committee);
	}

	/// @dev Returns the standby (out of committee) members and their weights
	function _getStandbys() public view returns (address[] memory addrs, uint256[] memory weights) {
		(Participant[] memory members,) = loadParticipants(participants, NullMember());
		Participant[] memory standbys = computeCommittee(members, settings).standbys;
		return toAddrsWeights(standbys);
	}

	/// @dev Called by: Elections contract
	/// Sets the minimal weight, and committee members
    /// Every member with sortingWeight >= minimumWeight OR in top minimumN is included in the committee
	function setMinimumWeight(uint256 _minimumWeight, address _minimumAddress, uint _minCommitteeSize) external onlyElectionsContract {
		Settings memory _settings = settings;
		_settings.minimumWeight = _minimumWeight;
		_settings.minimumAddress = _minimumAddress;
		_settings.minCommitteeSize = _minCommitteeSize;
		settings = _settings;

		updateOnMemberChange(NullMember(), _settings);
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
		Settings memory _settings = settings;

		bool isParticipant = member.data.inCommittee || member.data.isStandby;
		if (!isParticipant) {
			CommitteeInfo memory _committeeInfo = committeeInfo;
			if (!qualifiedToJoin(member, _settings, _committeeInfo)) {
				return (false, false);
			}
			joinMemberAsParticipant(member, _committeeInfo);
		}

		return updateOnMemberChange(member, _settings);
	}

	function qualifiedToJoin(Member memory member, Settings memory _settings, CommitteeInfo memory _committeeInfo) private view returns (bool) {
		return qualifiedToJoinAsStandby(member, _settings, _committeeInfo) || qualifiedToJoinCommittee(member, _settings, _committeeInfo);
	}

	function isReadyToSyncStale(uint256 timestamp, bool currentlyInCommittee, Settings memory _settings) private view returns (bool) {
		return timestamp == 0 || !currentlyInCommittee && timestamp <= now - _settings.readyToSyncTimeout;
	}

	function qualifiesAsStandby(Member memory member) private pure returns (bool) {
		return member.data.isMember && member.data.readyToSyncTimestamp != 0 && member.data.weight != 0;
	}

	function qualifiedToJoinAsStandby(Member memory member, Settings memory _settings, CommitteeInfo memory _committeeInfo) private view returns (bool) {
		if (!qualifiesAsStandby(member)) {
			return false;
		}

		return _committeeInfo.standbysCount < _settings.maxStandbys || // Room in standbys
			_committeeInfo.standbysCount > 0 && member.data.readyToSyncTimestamp > _committeeInfo.oldestReadyToSyncStandbyTimestamp || // A standby timed out
			outranksLowestStandby(member, _committeeInfo, _settings); // A standby can be outranked by weight
	}

	function isAboveCommitteeEntryThreshold(Member memory member, Settings memory _settings) private view returns (bool) {
		return compareMembersPerCommitteeCriteria(
			member,
			Member({
				addr: _settings.minimumAddress,
				data: MemberData({
					isMember: true,
					readyForCommittee: true,
					readyToSyncTimestamp: now,
					weight: _settings.minimumWeight,

					isStandby: false,
					inCommittee: true
				})
			}),
			_settings
		) >= 0;
	}

	function outranksLowestCommitteeMember(Member memory member, CommitteeInfo memory _committeeInfo, Settings memory _settings) private view returns (bool) {
		return _committeeInfo.committeeSize > 0 && compareMembersPerCommitteeCriteria(
			member,
			Member({
				addr: _settings.minimumAddress,
				data: MemberData({
					isMember: true,
					readyForCommittee: true,
					readyToSyncTimestamp: now,
					weight: _committeeInfo.minCommitteeMemberWeight,

					isStandby: false,
					inCommittee: true
				})
			}),
			_settings
		) > 0;
	}

	function outranksLowestStandby(Member memory member, CommitteeInfo memory _committeeInfo, Settings memory _settings) private view returns (bool) {
		return _committeeInfo.standbysCount > 0 && compareMembersPerStandbyCriteria(
			member,
			Member({
				addr: _committeeInfo.minStandbyAddress,
				data: MemberData({
					isMember: true,
					readyForCommittee: false,
					readyToSyncTimestamp: now,
					weight: _committeeInfo.minStandbyWeight,

					isStandby: true,
					inCommittee: false
				})
			}),
		_settings) > 0;
	}

	function qualifiesForCommittee(Member memory member, Settings memory _settings, uint committeeSize, bool _outranksLowestCommitteeMember) private view returns (bool) {
		return (
			member.data.isMember &&
			member.data.weight > 0 &&
			member.data.readyForCommittee &&
			!isReadyToSyncStale(member.data.readyToSyncTimestamp, member.data.inCommittee, _settings) &&
			(
				_outranksLowestCommitteeMember ||
				committeeSize < _settings.minCommitteeSize ||
				committeeSize < _settings.maxCommitteeSize && isAboveCommitteeEntryThreshold(member, _settings)
			)
		);
	}

	function qualifiedToJoinCommittee(Member memory member, Settings memory _settings, CommitteeInfo memory _committeeInfo) private view returns (bool) {
		return qualifiesForCommittee(member, _settings, _committeeInfo.committeeSize, outranksLowestCommitteeMember(member, _committeeInfo, _settings));
	}

	function joinMemberAsParticipant(Member memory member, CommitteeInfo memory _committeeInfo) private {
		participants.length = Math.max(participants.length, _committeeInfo.freeParticipantSlotPos + 1);
		participants[_committeeInfo.freeParticipantSlotPos] = member.addr;
	}

	function updateOnMemberChange(Member memory member, Settings memory _settings) private returns (bool committeeChanged, bool standbysChanged) { // TODO this is sometimes called with a member with address 0 indicating no member changed
		// TODO in all the state writes below, can skip the write for the given member as it will be written anyway

		CommitteeInfo memory ci = CommitteeInfo({
			freeParticipantSlotPos: 0,
			oldestReadyToSyncStandbyTimestamp: 0,
			minStandbyWeight: 0,
			minStandbyAddress: address(0),
			standbysCount: 0,
			committeeSize: 0,
			minCommitteeMemberWeight: 0,
			minCommitteeMemberAddress: address(0)
		});

		committeeChanged = member.data.inCommittee;
		standbysChanged = member.data.isStandby;

		address[] memory _participants = participants;
		Participant[] memory _members;
		uint maxPos;

		(_members, ci.freeParticipantSlotPos) = loadParticipants(_participants, member); // override stored member with preloaded one
		CommitteeComputationResults memory o = computeCommittee(_members, _settings);
		(ci.committeeSize, ci.standbysCount) = (o.committee.length, o.standbys.length);

		AnalyzisResult memory r = UpdateAndAnalyzeParticipantSet(o.committee, true, false, member.addr);
		(committeeChanged, standbysChanged) = (committeeChanged || r.committeeChanged, standbysChanged || r.standbysChanged);
		(ci.minCommitteeMemberWeight, ci.minCommitteeMemberAddress, maxPos) = (r.minWeight, r.minAddr, r.maxPos);

		r = UpdateAndAnalyzeParticipantSet(o.standbys, false, true, member.addr);
		(committeeChanged, standbysChanged) = (committeeChanged || r.committeeChanged, standbysChanged || r.standbysChanged);
		(ci.minStandbyWeight, ci.minStandbyAddress, ci.oldestReadyToSyncStandbyTimestamp) = (r.minWeight, r.minAddr, r.minTimestamp);
		maxPos = Math.max(maxPos, r.maxPos);

		r = UpdateAndAnalyzeParticipantSet(o.evicted, false, false, member.addr);
		(committeeChanged, standbysChanged) = (committeeChanged || r.committeeChanged, standbysChanged || r.standbysChanged);
		ci.freeParticipantSlotPos = Math.min(ci.freeParticipantSlotPos, r.minPos);

		participants.length = Math.min(_participants.length, maxPos + 1);

		committeeInfo = ci;

		if (committeeChanged) _notifyCommitteeChanged(o.committee);
		if (standbysChanged) _notifyStandbysChanged(o.standbys);
	}

	struct AnalyzisResult {
		bool committeeChanged;
		bool standbysChanged;
		uint minPos;
		uint maxPos;
		uint minWeight;
		address minAddr;
		uint minTimestamp;
	}
	function UpdateAndAnalyzeParticipantSet(Participant[] memory list, bool inCommittee, bool isStandby, address skipSavingMember) private returns (AnalyzisResult memory r) {
		r = AnalyzisResult({
			minWeight: uint256(-1),
			minAddr: address(-1),
			maxPos: 0,
			minPos: uint(-1),
			minTimestamp: uint(-1),
			committeeChanged: false,
			standbysChanged: false
		});
		for (uint i = 0; i < list.length; i++) {
			Participant memory p = list[i];
			bool changed = false;

			if (p.data.isStandby != isStandby) {
				p.data.isStandby = isStandby;
				if (isStandby && p.data.inCommittee) {
					p.data.readyToSyncTimestamp = now;
				}
				changed = true;
				r.standbysChanged = true;
			}

			if (p.data.inCommittee != inCommittee) {
				p.data.inCommittee = inCommittee;
				changed = true;
				r.committeeChanged = true;
			}

			if (!isStandby && !inCommittee) {
				participants[p.pos] = address(0);
			}

			if (changed && p.addr != skipSavingMember) {
				membersData[p.addr] = p.data;
			}

			r.maxPos = Math.max(r.maxPos, p.pos);
			r.minPos = Math.min(r.minPos, p.pos);
			r.minTimestamp = Math.min(r.minTimestamp, p.data.readyToSyncTimestamp);
			if (p.data.weight < r.minWeight) {
				r.minWeight = p.data.weight;
				r.minAddr = p.addr;
			} else if (p.data.weight == r.minWeight && uint(p.addr) < uint(r.minAddr)) {
				r.minAddr = p.addr;
			}
		}
	}

	function loadParticipants(address[] memory participantsAddrs, Member memory overrideMember) private view returns (Participant[] memory _participants, uint firstFreeSlot) {
		uint nParticipants = 0;
		firstFreeSlot = participantsAddrs.length;

		for (uint i = 0; i < participantsAddrs.length; i++) { // TODO can be replaced by getting number from committee info (which is read anyway)
			if (participantsAddrs[i] != address(0)) {
				nParticipants++;
			} else if (firstFreeSlot == participantsAddrs.length) {
				firstFreeSlot = i;
			}
		}

		_participants = new Participant[](nParticipants);
		uint mInd = 0;
		for (uint i = 0; i < participantsAddrs.length; i++) {
			address addr = participantsAddrs[i];
			if (addr != address(0)) {
				_participants[mInd] = Participant({
					addr: addr,
					data: addr == overrideMember.addr ? overrideMember.data : membersData[addr], // load data unless overridden
					pos: i
				});
				mInd++;
			}
		}
	}

	struct CommitteeComputationResults {
		Participant[] committee;
		Participant[] standbys;
		Participant[] evicted;
	}

	function computeCommittee(Participant[] memory _participants, Settings memory _settings) private view returns (CommitteeComputationResults memory out) {

		Participant[] memory list = slice(_participants, 0, _participants.length); // TODO can be omitted?

		sortByCommitteeCriteria(list, _settings);

		uint i = 0;
		uint committeeSize = 0;

		while (
			i < list.length &&
			committeeSize < _settings.maxCommitteeSize &&
			qualifiesForCommittee(Member({addr: list[i].addr, data: list[i].data}), _settings, committeeSize, false)
		) {
			committeeSize++;
			i++;
		}

		sortByStandbysCriteria(list, _settings, committeeSize, list.length);

		uint nStandbys = 0;
		while (
			i < list.length &&
			nStandbys < _settings.maxStandbys &&
			qualifiesAsStandby(Member({addr: list[i].addr, data: list[i].data}))
		) {
			nStandbys++;
			i++;
		}

		uint nEvicted = list.length - nStandbys - committeeSize;

		Participant[] memory committee = slice(list, 0, committeeSize);
		Participant[] memory standbys = slice(list, committeeSize, nStandbys);
		Participant[] memory evicted = slice(list, committeeSize + nStandbys, nEvicted);

		return CommitteeComputationResults({
			committee: committee,
			standbys: standbys,
			evicted: evicted
		});
	}

	enum Comparator {Committee, Standbys}

	function sortByCommitteeCriteria(Participant[] memory list, Settings memory _settings) private view {
		quickSort(list, 0, list.length, _settings, Comparator.Committee);
	}

	function sortByStandbysCriteria(Participant[] memory list, Settings memory _settings, uint from, uint to) private view {
		quickSort(list, from, to, _settings, Comparator.Standbys);
	}

	function quickSort(Participant[] memory arr, uint from, uint to, Settings memory _settings, Comparator comparator) private view {
        // todo: are stack variables initialized to 0? if so, some assignments can be omitted
        Participant memory piv;
        uint i = 0;
        int L;
        int R;
        int[] memory beg = new int[](to - from + 1);
        int[] memory end = new int[](to - from + 1);

		(beg[0], end[0]) = (int(from), int(to));
        while (int(i) >= 0) {
            L = beg[i];
            R = end[i] - 1;
            if (L < R) {
                piv = arr[uint(L)];
                while (L<R) {
                    while (L < R && compareMembers(arr[uint(R)], piv, _settings, comparator) <= 0) {
                        R--;
                    }
                    if (L < R) {
                        arr[uint(L++)] = arr[uint(R)];
                    }
                    while (L < R && compareMembers(arr[uint(L)], piv, _settings, comparator) >= 0) {
                        L++;
                    }
                    if (L < R) {
                        arr[uint(R--)] = arr[uint(L)];
                    }
                }
                arr[uint(L)] = piv;
                beg[i + 1] = L + 1;
                end[i + 1] = end[i];
                end[i++] = L;
            } else {
                i--;
            }
        }
	}

	function compareMembers(Participant memory a, Participant memory b, Settings memory _settings, Comparator comparator) private view returns (int) {
		Member memory ma = Member({addr: a.addr, data: a.data});
		Member memory mb = Member({addr: b.addr, data: b.data});
		if (comparator == Comparator.Committee) {
			return compareMembersPerCommitteeCriteria(ma, mb, _settings);
		} else {
			return compareMembersPerStandbyCriteria(ma, mb, _settings);
		}
	}

	function compareMembersPerCommitteeCriteria(Member memory v1, Member memory v2, Settings memory _settings) private view returns (int) {
		bool v1TimedOut = isReadyToSyncStale(v1.data.readyToSyncTimestamp, v1.data.inCommittee, _settings);
		bool v2TimedOut = isReadyToSyncStale(v2.data.readyToSyncTimestamp, v2.data.inCommittee, _settings);

		bool v1Qualified = qualifiesAsStandby(v1);
		bool v2Qualified = qualifiesAsStandby(v2);

		return v1Qualified && !v2Qualified || v1Qualified == v2Qualified && (
			v1.data.readyForCommittee && !v2.data.readyForCommittee || v1.data.readyForCommittee == v2.data.readyForCommittee && (
				!v1TimedOut && v2TimedOut || v1TimedOut == v2TimedOut && (
					v1.data.weight > v2.data.weight || v1.data.weight == v2.data.weight && (
						uint256(v1.addr) > uint256(v2.addr)
		))))
		? int(1) :
		v1Qualified == v2Qualified && v1.data.readyForCommittee == v2.data.readyForCommittee && v1TimedOut == v2TimedOut && v1.data.weight == v2.data.weight && uint256(v1.addr) == uint256(v2.addr) ? int(0)
		: int(-1);

	}

	function compareMembersPerStandbyCriteria(Member memory v1, Member memory v2, Settings memory _settings) private view returns (int) {
		bool v1TimedOut = isReadyToSyncStale(v1.data.readyToSyncTimestamp, v1.data.inCommittee, _settings);
		bool v2TimedOut = isReadyToSyncStale(v2.data.readyToSyncTimestamp, v2.data.inCommittee, _settings);

		bool v1Qualified = qualifiesAsStandby(v1);
		bool v2Qualified = qualifiesAsStandby(v2);

		return v1Qualified && !v2Qualified || v1Qualified == v2Qualified && (
					!v1TimedOut && v2TimedOut || v1TimedOut == v2TimedOut && (
						v1.data.weight > v2.data.weight || v1.data.weight == v2.data.weight && (
							uint256(v1.addr) > uint256(v2.addr)
		))) ? int(1)
		: v1Qualified == v2Qualified && v1TimedOut == v2TimedOut && v1.data.weight == v2.data.weight && v1.addr == v2.addr ? int(0)
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
