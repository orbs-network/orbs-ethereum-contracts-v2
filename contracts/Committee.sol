pragma solidity 0.5.16;

import "./spec_interfaces/ICommittee.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "./spec_interfaces/IValidatorsRegistration.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "./ContractRegistryAccessor.sol";

/// @title Elections contract interface
contract Committee is ICommittee, ContractRegistryAccessor {
	event GasReport(string label, uint gas);

	Participant[] participants;

	struct MemberData { // TODO can be reduced to 1 state entry
		uint48 weight;
		uint32 readyToSyncTimestamp;
		bool isMember; // exists
		bool readyForCommittee;

		bool isStandby;
		bool inCommittee;
	}
	mapping (address => MemberData) membersData;

	struct Member {
		address addr;
		MemberData data;
	} // Never in state, only in memory

	struct Participant {
		MemberData data;
		address addr;
		uint8 pos;

		bool shouldBeInCommittee;
		bool shouldBeStandby;
		bool dirty;
	} // Never in state, only in memory

	struct Settings { // TODO can be reduced to 2-3 state entries
		uint48 minimumWeight;
		address minimumAddress;
		uint32 readyToSyncTimeout;
		uint8 minCommitteeSize;
		uint8 maxCommitteeSize;
		uint8 maxStandbys;
	}
	Settings settings;

	uint256 weightSortIndicesBytes;

	// Derived properties
	struct CommitteeInfo {
		address minCommitteeMemberAddress;
		uint64 committeeBitmap;
		uint8 standbysCount;
		uint8 committeeSize;
		bool pendingChanges;
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
			minimumWeight: uint48(_minimumWeight), // TODO do we need minimumWeight here in the constructor?
			minimumAddress: address(0), // TODO if we pass minimum weight, need to also pass min address
			maxStandbys: uint8(_maxStandbys),
			readyToSyncTimeout: uint32(_readyToSyncTimeout)
			});

		participants.length = 1;
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
			memberData.weight = uint48(weight);
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
					weight: uint48(weight),
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
		// todo in case of committeeInfo.pendingChanges, this is stale
		CommitteeInfo memory _committeeInfo = committeeInfo;
		uint bitmap = uint(_committeeInfo.committeeBitmap);
		uint committeeSize = _committeeInfo.committeeSize;

		addrs = new address[](committeeSize);
		weights = new uint[](committeeSize);
		bitmap = uint(_committeeInfo.committeeBitmap);
		uint i = 0;
		Participant memory p;
		while (bitmap != 0) {
			if (bitmap & 1 == 1) {
				p = participants[i];
				addrs[i] = p.addr;
				weights[i] = uint(p.data.weight);
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
		Participant memory p;
		while (i < standbysCount) {
			if (bitmap & 1 == 0) {
				p = participants[ind];
				if (p.addr != address(0)) {
					addrs[i] = p.addr;
					weights[i] = uint(p.data.weight);
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
	function setMinimumWeight(uint256 _minimumWeight, address _minimumAddress, uint _minCommitteeSize, bool dontComputeCommittee) external onlyElectionsContract {
		Settings memory _settings = settings;
		_settings.minimumWeight = uint48(_minimumWeight);
		_settings.minimumAddress = _minimumAddress;
		_settings.minCommitteeSize = uint8(_minCommitteeSize);
		settings = _settings; // todo check if equal before writing
		if (dontComputeCommittee) {
			committeeInfo.pendingChanges = true;
		} else {
			updateOnMemberChange(NullMember(), _settings);
		}
	}

	function flush() external {
		if (committeeInfo.pendingChanges) {
			updateOnMemberChange(NullMember(), settings);
		}
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
//		address[] memory orbsAddresses = new address[](addrs.length);
//		IValidatorsRegistration validatorsRegistrationContract = getValidatorsRegistrationContract();
//		for (uint i = 0; i < addrs.length; i++) {
//			orbsAddresses[i] = validatorsRegistrationContract.getValidatorOrbsAddress(addrs[i]);
//		}
//		return orbsAddresses;
		return getValidatorsRegistrationContract().getValidatorsOrbsAddress(addrs);
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
//		uint gl01 = gasleft();
		(committeeChanged, standbysChanged) = _rankMember(member);
		membersData[member.addr] = member.data;
//		uint gl02 = gasleft();
// 		emit GasReport("rankdAndUpdate: all", gl01-gl02);
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

	function qualifiesAsStandby(Participant memory member) private pure returns (bool) {
		return member.data.isMember && member.data.readyToSyncTimestamp != 0 && member.data.weight != 0; // TODO should we check for isReadyToSyncStale instead? this means that timed-out nodes are evicted on any change, instead of only when being replaced.
	}

	function qualifiesForCommittee(Participant memory member, Settings memory _settings, uint committeeSize) private view returns (bool) {
		return (
		member.data.isMember &&
		member.data.weight > 0 &&
		member.data.readyForCommittee &&
		!isReadyToSyncStale(member.data.readyToSyncTimestamp, member.data.inCommittee, _settings) &&
		(
		committeeSize < _settings.minCommitteeSize ||
		committeeSize < _settings.maxCommitteeSize && (
			member.data.weight > _settings.minimumWeight || member.data.weight == _settings.minimumWeight && (uint(member.addr) >= uint(_settings.minimumAddress))
		))
		);
	}

	struct UpdateVars {
		uint maxPos;
		Participant p;
		uint48 minCommitteeWeight;
		uint seenStandbys;
		uint seenCommittee;
	}
	function updateOnMemberChange(Member memory changedMember, Settings memory _settings) private returns (bool committeeChanged, bool standbysChanged) { // TODO this is sometimes called with a member with address 0 indicating no member changed
		committeeChanged = changedMember.data.inCommittee;
		standbysChanged = changedMember.data.isStandby;

		Participant[] memory _participants = participants; //25k
		uint256 newWeightSortIndicesBytes = sortParticipantsByWeight(_participants, changedMember); // override stored member with preloaded one //70k

		CommitteeInfo memory newCommitteeInfo;
		newCommitteeInfo.minCommitteeMemberAddress = address(-1);

//		uint gl01 = gasleft();

		UpdateVars memory s;
		s.minCommitteeWeight = uint48(-1);
		Participant memory p;
		uint i;
		for (uint256 indices = newWeightSortIndicesBytes; indices != 0; indices >>= 8) { // first iteration: 29k
			i = (indices & 0xFF) - 1;
			p = _participants[i];
			if (qualifiesForCommittee(p, _settings, newCommitteeInfo.committeeSize)) {
				p.shouldBeInCommittee = true;
				newCommitteeInfo.committeeSize++;
				newCommitteeInfo.committeeBitmap |= uint64(uint(1) << p.pos);
				if (p.data.weight < s.minCommitteeWeight) {
					s.minCommitteeWeight = p.data.weight;
					newCommitteeInfo.minCommitteeMemberAddress = p.addr;
				} else if (p.data.weight == s.minCommitteeWeight && uint(p.addr) < uint(newCommitteeInfo.minCommitteeMemberAddress)) {
					newCommitteeInfo.minCommitteeMemberAddress = p.addr;
				}
			} else if (
				newCommitteeInfo.standbysCount < _settings.maxStandbys &&
				qualifiesAsStandby(p) &&
				!isReadyToSyncStale(p.data.readyToSyncTimestamp, p.data.inCommittee, _settings)
			) {
				p.shouldBeStandby = true;
				newCommitteeInfo.standbysCount++;
			}
		}
		// 		emit GasReport("updateOnMemberChange: first iteration", gl01 - gasleft());
		//		gl01 = gasleft();
		for (uint256 indices = newWeightSortIndicesBytes; indices != 0; indices >>= 8) { // first iteration: 29k
			i = (indices & 0xFF) - 1;
			p = _participants[i];
			if (p.shouldBeStandby != p.data.isStandby) {
				if (
					!p.shouldBeInCommittee && !p.shouldBeStandby &&
				newCommitteeInfo.standbysCount < _settings.maxStandbys &&
				qualifiesAsStandby(p)
				) {
					p.shouldBeStandby = true;
					newCommitteeInfo.standbysCount++;
				}
				if (p.shouldBeStandby != p.data.isStandby) {
					p.data.isStandby = p.shouldBeStandby;
					if (p.shouldBeStandby && p.data.inCommittee) {
						p.data.readyToSyncTimestamp = uint32(now);
					}
					p.dirty = true;
					standbysChanged = true;
				}
			}
			if (p.shouldBeInCommittee != p.data.inCommittee) {
				p.data.inCommittee = p.shouldBeInCommittee;
				p.dirty = true;
				committeeChanged = true;
			}
			if (p.dirty) {
				membersData[p.addr] = p.data;
			}
			if (!p.data.inCommittee && !p.data.isStandby) {
				delete participants[p.pos];
			} else {
				if (s.maxPos < p.pos) s.maxPos = p.pos;
				if (p.dirty) {
					p.dirty = false;
					p.shouldBeInCommittee = false;
					p.shouldBeStandby = false;
					participants[p.pos] = p;
				}
			}
		}

// 		emit GasReport("updateOnMemberChange: second iteration", gl01 - gasleft());

//		gl01 = gasleft();
		if (_participants.length != s.maxPos + 2) { // keep the last element free
			participants.length = s.maxPos + 2;
		}
// 		emit GasReport("updateOnMemberChange: updating participants array length", gl01 - gasleft());

//		gl01 = gasleft();
		weightSortIndicesBytes = newWeightSortIndicesBytes;
		committeeInfo = newCommitteeInfo; // todo check if changed before writing
// 		emit GasReport("updateOnMemberChange: saving committee info", gl01 - gasleft());

//		gl01 = gasleft();
		notifyChanges(_participants, newCommitteeInfo.committeeSize, newCommitteeInfo.standbysCount, committeeChanged, standbysChanged); //130k
// 		emit GasReport("updateOnMemberChange: notifications", gl01 - gasleft());

	}

	function notifyChanges(Participant[] memory _participants, uint committeeSize, uint standbysCount, bool committeeChanged, bool standbysChanged) private {
		address[] memory committeeAddrs = new address[](committeeSize);
		uint[] memory committeeWeights = new uint[](committeeSize);
		uint cInd;
		address[] memory standbyAddrs = new address[](standbysCount);
		uint[] memory standbyWeights = new uint[](standbysCount);
		uint sInd;

		Participant memory p;
		for (uint i = 0; i < _participants.length; i++) {
			p = _participants[i];
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

	function sortParticipantsByWeight(Participant[] memory _participants, Member memory preloadedMember) private returns (uint256 newWeightSortBytes) {
		Participant memory memberAsParticipant;
		Participant memory p;
		bool foundMember = preloadedMember.data.inCommittee || preloadedMember.data.isStandby;
		uint firstFreeSlot = _participants.length - 1; // last slot is always free
		for (uint i = 0; i < _participants.length; i++) {
			if (_participants[i].addr != address(0)) {
				if (_participants[i].addr == preloadedMember.addr) {
					memberAsParticipant = _participants[i];
					memberAsParticipant.data = preloadedMember.data;
					memberAsParticipant.dirty = true;
				}
			} else if (firstFreeSlot == _participants.length - 1) {
				firstFreeSlot = i;
			}
		}
		if (!foundMember) {
			p = _participants[firstFreeSlot];
			p.addr = preloadedMember.addr;
			p.data = preloadedMember.data;
			p.pos = uint8(firstFreeSlot);
			p.dirty = true;
			memberAsParticipant = p;
		}

		uint sortBytes = weightSortIndicesBytes;
		bool memberPlaced;
		uint pos;
		uint shift;
		while (sortBytes != 0) {
			pos = uint(sortBytes & 0xFF) - 1;
			sortBytes = sortBytes >> 8;

			if (pos != memberAsParticipant.pos) {
				p = _participants[pos];
				if (!memberPlaced && (p.data.weight < preloadedMember.data.weight || (p.data.weight == preloadedMember.data.weight && uint(p.addr) < uint(preloadedMember.addr)))) {
					newWeightSortBytes |= (uint(memberAsParticipant.pos + 1) << shift);
					shift += 8;
					memberPlaced = true;
				}
				newWeightSortBytes = newWeightSortBytes | ((pos + 1) << shift);
				shift += 8;
			}
		}

		if (!memberPlaced) {
			newWeightSortBytes |= (uint(memberAsParticipant.pos + 1) << shift);
		}
	}

	function _notifyStandbysChanged(address[] memory addrs, uint256[] memory weights) private {
		emit StandbysChanged(addrs, getValidatorsRegistrationContract().getValidatorsOrbsAddress(addrs), weights);
	}

	function _notifyCommitteeChanged(address[] memory addrs, uint256[] memory weights) private {
		emit CommitteeChanged(addrs, getValidatorsRegistrationContract().getValidatorsOrbsAddress(addrs), weights);
	}

	function tf1(Participant memory p) private {
		emit GasReport("dummy", p.pos);
	}

	function tf2(uint n) private {
		emit GasReport("dummy", n);
	}

	struct AddrWeight {
		address addr;
		uint64 weight;
	}
	mapping (address => AddrWeight) tm;

	function test() external {
		//		CommitteeInfo memory ci = committeeInfo;
		//		Settings memory _settings = settings;
		uint gl01;
		uint gl02;

		gl01 = gasleft();
		Participant[] memory members = participants;
		emit GasReport("reading participants array", gl01 - gasleft());

		gl01 = gasleft();
		sortParticipantsByWeight(members, NullMember());
		gl02 = gasleft();
		emit GasReport("loading participants", gl01 - gl02);

		gl01 = gasleft();
		Participant memory p = members[0];
		gl02 = gasleft();
		emit GasReport("reading participant to new local", gl01 - gl02);

		gl01 = gasleft();
		p = members[0];
		gl02 = gasleft();
		emit GasReport("reading participant to existing local", gl01 - gl02);

		gl01 = gasleft();
		tf1(p);
		gl02 = gasleft();
		emit GasReport("calling func with Participant", gl01 - gl02);

		gl01 = gasleft();
		Participant memory p2 = p;
		gl02 = gasleft();
		emit GasReport("copying from local to new local", gl01 - gl02);

		Participant memory p3;

		gl01 = gasleft();
		p3 = p2;
		gl02 = gasleft();
		emit GasReport("copying from local to existing local", gl01 - gl02);

		uint n = 3;
		gl01 = gasleft();
		tf2(n);
		gl02 = gasleft();
		emit GasReport("calling func with uint", gl01 - gl02);

		MemberData memory md;
		gl01 = gasleft();
		md = membersData[msg.sender];
		gl02 = gasleft();
		emit GasReport("reading one member data", gl01 - gl02);

		AddrWeight memory aw;
		gl01 = gasleft();
		aw = tm[msg.sender];
		gl02 = gasleft();
		emit GasReport("reading addr weight", gl01 - gl02);

	}


}
