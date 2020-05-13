pragma solidity 0.5.16;

import "./spec_interfaces/ICommittee.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "./spec_interfaces/IValidatorsRegistration.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "./ContractRegistryAccessor.sol";

/// @title Elections contract interface
contract Committee is ICommittee, ContractRegistryAccessor {
	event GasReport(string label, uint gas);

	address[] participants;

	struct MemberData { // TODO can be reduced to 1 state entry
		bool isMember; // exists
		bool readyForCommittee;
		uint32 readyToSyncTimestamp;
		uint128 weight;

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
		uint128 minimumWeight;
		address minimumAddress;
		uint32 readyToSyncTimeout;
		uint8 minCommitteeSize;
		uint8 maxCommitteeSize;
		uint8 maxStandbys;
	}
	Settings settings;

	// Derived properties (TODO can be reduced to 2-3 state entries)
	struct CommitteeInfo {
		uint256 weightSortIndicesBytes;
		address minCommitteeMemberAddress;
		uint64 committeeBitmap;
		uint8 standbysCount;
		uint8 committeeSize;
	}
	CommitteeInfo committeeInfo;

	modifier onlyElectionsContract() {
		require(msg.sender == address(getElectionsContract()), "caller is not the elections");

		_;
	}

	constructor(uint _minCommitteeSize, uint _maxCommitteeSize, uint _minimumWeight, uint _maxStandbys, uint256 _readyToSyncTimeout) public {
		require(_maxCommitteeSize > 0, "maxCommitteeSize must be larger than 0");
		require(_maxStandbys > 0, "maxStandbys must be larger than 0");
		require(_readyToSyncTimeout > 0, "readyToSyncTimeout must be larger than 0");
		require(_maxStandbys > 0, "maxStandbys must be larger than 0");
		settings = Settings({
			minCommitteeSize: uint8(_minCommitteeSize),
			maxCommitteeSize: uint8(_maxCommitteeSize),
			minimumWeight: uint128(_minimumWeight), // TODO do we need minimumWeight here in the constructor?
			minimumAddress: address(0), // TODO if we pass minimum weight, need to also pass min address
			maxStandbys: uint8(_maxStandbys),
			readyToSyncTimeout: uint32(_readyToSyncTimeout)
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
			memberData.weight = uint128(weight);
			return _rankAndUpdateMember(Member({
				addr: addr,
				data: memberData
				}));
		}
		return (false, false);
	}

	function memberReadyToSync(address addr, bool readyForCommittee) external onlyElectionsContract returns (bool committeeChanged, bool standbysChanged) {
		MemberData memory memberData = membersData[addr];
		if (memberData.isMember) {
			memberData.readyToSyncTimestamp = uint32(now);
			memberData.readyForCommittee = readyForCommittee;
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
					weight: uint128(weight),
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
		CommitteeInfo memory _committeeInfo = committeeInfo;
		uint bitmap = uint(_committeeInfo.committeeBitmap);
		uint committeeSize = _committeeInfo.committeeSize;

		addrs = new address[](committeeSize);
		weights = new uint[](committeeSize);
		bitmap = uint(_committeeInfo.committeeBitmap);
		uint i = 0;
		while (bitmap != 0) {
			if (bitmap & 1 == 1) {
				addrs[i] = participants[i];
				weights[i] = uint(membersData[addrs[i]].weight);
				i++;
			}
			bitmap = bitmap >> 1;
		}
	}

	/// @dev Returns the standby (out of committee) members and their weights
	function _getStandbys() public view returns (address[] memory addrs, uint256[] memory weights) {
		CommitteeInfo memory _committeeInfo = committeeInfo;
		uint bitmap = uint(_committeeInfo.committeeBitmap);
		uint standbysCount = uint(_committeeInfo.standbysCount);

		addrs = new address[](standbysCount);
		weights = new uint[](standbysCount);
		bitmap = uint(_committeeInfo.committeeBitmap);
		uint i = 0;
		uint ind;
		address addr;
		while (i < standbysCount) {
			if (bitmap & 1 == 0) {
				addr = participants[ind];
				if (addr != address(0)) {
					addrs[i] = addr;
					weights[i] = uint(membersData[addr].weight);
					i++;
				}
			}
			bitmap = bitmap >> 1;
			ind++;
		}
	}

	/// @dev Called by: Elections contract
	/// Sets the minimal weight, and committee members
	/// Every member with sortingWeight >= minimumWeight OR in top minimumN is included in the committee
	function setMinimumWeight(uint256 _minimumWeight, address _minimumAddress, uint _minCommitteeSize) external onlyElectionsContract {
		Settings memory _settings = settings;
		_settings.minimumWeight = uint128(_minimumWeight);
		_settings.minimumAddress = _minimumAddress;
		_settings.minCommitteeSize = uint8(_minCommitteeSize);
		settings = _settings;

		updateOnMemberChange(NullMember(), _settings);
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

	function _loadOrbsAddresses(address[] memory addrs) private view returns (address[] memory) {
		address[] memory orbsAddresses = new address[](addrs.length);
		IValidatorsRegistration validatorsRegistrationContract = getValidatorsRegistrationContract();
		for (uint i = 0; i < addrs.length; i++) {
			require(addrs[i] != address(0), "zero address 0");
			orbsAddresses[i] = validatorsRegistrationContract.getValidatorOrbsAddress(addrs[i]);
		}
		return orbsAddresses;
	}

	function _loadIps(address[] memory addrs) private view returns (bytes4[] memory) {
		bytes4[] memory ips = new bytes4[](addrs.length);
		IValidatorsRegistration validatorsRegistrationContract = getValidatorsRegistrationContract();
		for (uint i = 0; i < addrs.length; i++) {
			ips[i] = validatorsRegistrationContract.getValidatorIp(addrs[i]);
		}
		return ips;
	}

	function _rankAndUpdateMember(Member memory member) private returns (bool committeeChanged, bool standbysChanged) {
		uint gl01 = gasleft();
		(committeeChanged, standbysChanged) = _rankMember(member);
		membersData[member.addr] = member.data;
		uint gl02 = gasleft();
		emit GasReport("rankdAndUpdate: all", gl01-gl02);
	}

	function _rankMember(Member memory member) private returns (bool committeeChanged, bool standbysChanged) {
		Settings memory _settings = settings;

		bool isParticipant = member.data.inCommittee || member.data.isStandby;
		if (!isParticipant) {
			if (!member.data.isMember || member.data.readyToSyncTimestamp == 0 || member.data.weight == 0) {
				return (false, false);
			}
		}

		return updateOnMemberChange(member, _settings);
	}

	function isReadyToSyncStale(uint32 timestamp, bool currentlyInCommittee, Settings memory _settings) private view returns (bool) {
		return timestamp == 0 || !currentlyInCommittee && timestamp <= uint32(now) - _settings.readyToSyncTimeout;
	}

	function qualifiesAsStandby(Member memory member) private pure returns (bool) {
		return member.data.isMember && member.data.readyToSyncTimestamp != 0 && member.data.weight != 0; // TODO should we check for isReadyToSyncStale instead? this means that timed-out nodes are evicted on any change, instead of only when being replaced.
	}

	function isAboveCommitteeEntryThreshold(Member memory member, Settings memory _settings) private view returns (bool) {
		return compareMembersPerCommitteeCriteria(
			member,
			Member({
			addr: _settings.minimumAddress,
			data: MemberData({
				isMember: true,
				readyForCommittee: true,
				readyToSyncTimestamp: uint32(now),
				weight: uint128(_settings.minimumWeight),

				isStandby: false,
				inCommittee: true
				})
			}),
			_settings
		) >= 0;
	}

	function qualifiesForCommittee(Member memory member, Settings memory _settings, uint committeeSize) private view returns (bool) {
		return (
		member.data.isMember &&
		member.data.weight > 0 &&
		member.data.readyForCommittee &&
		!isReadyToSyncStale(member.data.readyToSyncTimestamp, member.data.inCommittee, _settings) &&
		(
		committeeSize < _settings.minCommitteeSize ||
		committeeSize < _settings.maxCommitteeSize && isAboveCommitteeEntryThreshold(member, _settings)
		)
		);
	}

	function repositionParticipantAccordingToWeight(Participant[] memory members, uint pos) private pure {
		while (pos < members.length - 1 && (members[pos].data.weight < members[pos + 1].data.weight || members[pos].data.weight == members[pos + 1].data.weight && uint(members[pos].addr) < uint(members[pos + 1].addr))) {
			(members[pos], members[pos + 1]) = (members[pos + 1], members[pos]);
			pos++;
		}
		while (pos > 0 && (members[pos - 1].data.weight < members[pos].data.weight || members[pos - 1].data.weight == members[pos].data.weight && uint(members[pos - 1].addr) < uint(members[pos].addr))) {
			(members[pos - 1], members[pos]) = (members[pos], members[pos - 1]);
			pos--;
		}
	}

	struct UpdateVars {
		uint maxPos;
		Participant p;
		uint128 minCommitteeWeight;
	}
	function updateOnMemberChange(Member memory member, Settings memory _settings) private returns (bool committeeChanged, bool standbysChanged) { // TODO this is sometimes called with a member with address 0 indicating no member changed
		committeeChanged = member.data.inCommittee;
		standbysChanged = member.data.isStandby;

		address[] memory _participants = participants;
		Participant[] memory _members = loadParticipantsSortedByWeights(_participants, member); // override stored member with preloaded one

		CommitteeInfo memory newCommitteeInfo = CommitteeInfo({
			standbysCount: 0,
			committeeSize: 0,
			minCommitteeMemberAddress: address(-1),
			committeeBitmap: 0,
			weightSortIndicesBytes: 0
			});

		UpdateVars memory s = UpdateVars({
			maxPos: 0,
			p: Participant({
				addr: member.addr,
				data: member.data,
				pos: 0
				}),
			minCommitteeWeight: uint128(-1)
			});
		for (uint pass = 0; pass < 2; pass++) {
			uint seenStandbys;
			uint seenCommittee;
			for (uint i = 0; i < _members.length; i++) {
				require(i == 0 || _members[i].data.weight <= _members[i-1].data.weight, "weights are not sorted");
				bool shouldBeInCommittee;
				bool shouldBeStandby;

				s.p = _members[i];
				if (qualifiesForCommittee(Member({addr: s.p.addr, data: s.p.data}), _settings, seenCommittee)) {
					shouldBeInCommittee = true;
					seenCommittee++;
					if (pass == 0) {
						newCommitteeInfo.committeeBitmap = uint64(newCommitteeInfo.committeeBitmap | (1 << s.p.pos));
						newCommitteeInfo.committeeSize++;
						if (s.p.data.weight < s.minCommitteeWeight) {
							s.minCommitteeWeight = s.p.data.weight;
							newCommitteeInfo.minCommitteeMemberAddress = s.p.addr;
						} else if (s.p.data.weight == s.minCommitteeWeight && uint(s.p.addr) < uint(newCommitteeInfo.minCommitteeMemberAddress)) {
							newCommitteeInfo.minCommitteeMemberAddress = s.p.addr;
						}
					}
				} else if (
					seenStandbys < _settings.maxStandbys &&
					qualifiesAsStandby(Member({addr: s.p.addr, data: s.p.data}))
				) {
					if (!isReadyToSyncStale(s.p.data.readyToSyncTimestamp, s.p.data.inCommittee, _settings)) {
						shouldBeStandby = true;
						if (pass == 0) newCommitteeInfo.standbysCount++;
					} else if (pass == 1 && newCommitteeInfo.standbysCount < _settings.maxStandbys) {
						shouldBeStandby = true;
						newCommitteeInfo.standbysCount++;
					}
					if (shouldBeStandby) seenStandbys++;
				}

				if (pass == 1) {
					bool changed;
					if (shouldBeStandby != s.p.data.isStandby) {
						s.p.data.isStandby = shouldBeStandby;
						if (shouldBeStandby && s.p.data.inCommittee) {
							s.p.data.readyToSyncTimestamp = uint32(now);
						}
						changed = true;
						standbysChanged = true;
					}
					if (shouldBeInCommittee != s.p.data.inCommittee) {
						s.p.data.inCommittee = shouldBeInCommittee;
						changed = true;
						committeeChanged = true;
					}
					if (changed) {
						membersData[s.p.addr] = s.p.data;
					}
					if (!s.p.data.inCommittee && !s.p.data.isStandby) {
						// no longer a participant
						if (s.p.pos < _participants.length) {
							participants[s.p.pos] = address(0);
						}
					} else {
						newCommitteeInfo.weightSortIndicesBytes = (newCommitteeInfo.weightSortIndicesBytes << 8) | uint8(s.p.pos + 1);
						if (_participants.length == s.p.pos || _participants[s.p.pos] != s.p.addr) { // new participant
							if (_participants.length == s.p.pos) {
								participants.length++;
							}
							participants[s.p.pos] = s.p.addr;
						}
						s.maxPos = Math.max(s.maxPos, s.p.pos);
					}
				}
			}
		}


		if (_participants.length > s.maxPos + 1) {
			participants.length = s.maxPos + 1;
		}

		committeeInfo = newCommitteeInfo;

		notifyChanges(_members, newCommitteeInfo.committeeSize, newCommitteeInfo.standbysCount, committeeChanged, standbysChanged);
	}

	function notifyChanges(Participant[] memory members, uint committeeSize, uint standbysCount, bool committeeChanged, bool standbysChanged) private {
		address[] memory committeeAddrs = new address[](committeeSize);
		uint[] memory committeeWeights = new uint[](committeeSize);
		uint cInd;
		address[] memory standbyAddrs = new address[](standbysCount);
		uint[] memory standbyWeights = new uint[](standbysCount);
		uint sInd;

		Participant memory p;
		for (uint i = 0; i < members.length; i++) {
			p = members[i];
			if (p.data.inCommittee) {
				committeeAddrs[cInd] = p.addr;
				committeeWeights[cInd++] = p.data.weight;
			} else if (p.data.isStandby) {
				standbyAddrs[sInd] = p.addr;
				standbyWeights[sInd++] = p.data.weight;
			}
		}

		if (committeeChanged) _notifyCommitteeChanged(committeeAddrs, committeeWeights);
		if (standbysChanged) _notifyStandbysChanged(standbyAddrs, standbyWeights);
	}

	function loadParticipantsSortedByWeights(address[] memory participantsAddrs, Member memory preloadedMember) private returns (Participant[] memory _participants) {
		uint nParticipants;
		bool foundMember;
		uint firstFreeSlot = participantsAddrs.length;
		for (uint i = 0; i < participantsAddrs.length; i++) {
			if (participantsAddrs[i] != address(0)) {
				nParticipants++;
				if (participantsAddrs[i] == preloadedMember.addr) {
					foundMember = true;
				}
			} else{
				if (firstFreeSlot == participantsAddrs.length) {
					firstFreeSlot = i;
				}
			}
		}
		if (!foundMember) nParticipants++;

		uint memberPos;
		uint sortBytes = committeeInfo.weightSortIndicesBytes;
		_participants = new Participant[](nParticipants);
		uint pind = nParticipants - 1;
		while (sortBytes != 0) {
			uint ind = uint(sortBytes & 0xFF) - 1;
			sortBytes = sortBytes >> 8;
			_participants[pind] = Participant({
				addr: participantsAddrs[ind],
				data: participantsAddrs[ind] == preloadedMember.addr ? preloadedMember.data : membersData[participantsAddrs[ind]], // load data unless overridden
				pos: ind
				});
			if (participantsAddrs[ind] == preloadedMember.addr) {
				memberPos = pind;
			}
			pind--;
		}

		if (!foundMember) {
			_participants[0] = Participant({
				addr: preloadedMember.addr,
				data: preloadedMember.data,
				pos: firstFreeSlot
				});
			memberPos = 0; // todo redundant, already 0
		}

		repositionParticipantAccordingToWeight(_participants, memberPos);
	}

	function compareMembersPerCommitteeCriteria(Member memory v1, Member memory v2, Settings memory _settings) private view returns (int) {
		bool v1TimedOut = isReadyToSyncStale(v1.data.readyToSyncTimestamp, v1.data.inCommittee, _settings);
		bool v2TimedOut = isReadyToSyncStale(v2.data.readyToSyncTimestamp, v2.data.inCommittee, _settings);

		bool v1Qualified = qualifiesAsStandby(v1);
		bool v2Qualified = qualifiesAsStandby(v2);

		if (v1Qualified && !v2Qualified) return 1;
		if (!v1Qualified && v2Qualified) return -1;

		// v1Qualified == v2Qualified

		if (v1.data.readyForCommittee && !v2.data.readyForCommittee) return 1;
		if (!v1.data.readyForCommittee && v2.data.readyForCommittee) return -1;

		// v1.data.readyForCommittee == !v2.data.readyForCommittee

		if (!v1TimedOut && v2TimedOut) return 1;
		if (v1TimedOut && !v2TimedOut) return -1;

		// v1TimedOut == v2TimedOut

		if (v1.data.weight > v2.data.weight) return 1;
		if (v1.data.weight < v2.data.weight) return -1;

		// v1.data.weight == v2.data.weight

		if (uint256(v1.addr) > uint256(v2.addr)) return 1;
		if (uint256(v1.addr) < uint256(v2.addr)) return -1;

		// v1.addr == v2.addr

		return 0;
	}

	function _notifyStandbysChanged(address[] memory addrs, uint256[] memory weights) private {
		emit StandbysChanged(addrs, _loadOrbsAddresses(addrs), weights);
	}

	function _notifyCommitteeChanged(address[] memory addrs, uint256[] memory weights) private {
		emit CommitteeChanged(addrs, _loadOrbsAddresses(addrs), weights);
	}

}
