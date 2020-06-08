pragma solidity 0.5.16;

import "./spec_interfaces/ICommittee.sol";
import "./spec_interfaces/IValidatorsRegistration.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "./ContractRegistryAccessor.sol";
import "./WithClaimableFunctionalOwnership.sol";

/// @title Elections contract interface
contract Committee is ICommittee, ContractRegistryAccessor, WithClaimableFunctionalOwnership, Lockable {
	uint constant MAX_TOPOLOGY = 32; // Cannot be greater than 32 (number of bytes in uint256)

	address[] participantAddresses;

	struct MemberData { // TODO can be reduced to 1 state entry
		uint128 weight;
		uint48 readyToSyncTimestamp;
		bool isMember; // exists
		bool readyForCommittee;
		bool isCompliant;

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
	} // Never in state, only in memory

	struct Settings { // TODO can be reduced to 2-3 state entries
		uint48 readyToSyncTimeout;
		uint8 maxCommitteeSize;
		uint8 maxStandbys;
	}
	Settings settings;

	uint256 weightSortIndicesOneBasedBytes;

	// Derived properties
	struct CommitteeInfo {
		uint64 committeeBitmap;
		uint8 standbysCount;
		uint8 committeeSize;
	}
	CommitteeInfo committeeInfo;

	modifier onlyElectionsContract() {
		require(msg.sender == address(getElectionsContract()), "caller is not the elections");

		_;
	}

	constructor(uint _maxCommitteeSize, uint _maxStandbys, uint256 _readyToSyncTimeout) public {
		require(_maxCommitteeSize > 0, "maxCommitteeSize must be larger than 0");
		require(_maxStandbys > 0, "maxStandbys must be larger than 0");
		require(_maxCommitteeSize + _maxStandbys <= MAX_TOPOLOGY, "maxCommitteeSize + maxStandbys must be 32 at most");
		require(_readyToSyncTimeout > 0, "readyToSyncTimeout must be larger than 0");
		settings = Settings({
			maxCommitteeSize: uint8(_maxCommitteeSize),
			maxStandbys: uint8(_maxStandbys),
			readyToSyncTimeout: uint48(_readyToSyncTimeout)
		});
	}

	/*
	 * Methods restricted to other Orbs contracts
	 */

	/// @dev Called by: Elections contract
	/// Notifies a weight change for sorting to a relevant committee member.
	/// weight = 0 indicates removal of the member from the committee (for example on unregister, voteUnready, voteOut)
	function memberWeightChange(address addr, uint256 weight) external onlyElectionsContract onlyWhenActive returns (bool committeeChanged, bool standbysChanged) {
		require(uint256(uint128(weight)) == weight, "weight is out of range");

		MemberData memory memberData = membersData[addr];
		if (!memberData.isMember) {
			return (false, false);
		}
		memberData.weight = uint128(weight);
		return _rankAndUpdateMember(Member({
			addr: addr,
			data: memberData
		}));
	}

	function memberReadyToSync(address addr, bool readyForCommittee) external onlyElectionsContract onlyWhenActive returns (bool committeeChanged, bool standbysChanged) {
		MemberData memory memberData = membersData[addr];
		if (!memberData.isMember) {
			return (false, false);
		}

		memberData.readyToSyncTimestamp = uint48(now);
		memberData.readyForCommittee = readyForCommittee;
		return _rankAndUpdateMember(Member({
			addr: addr,
			data: memberData
		}));
	}

	function memberNotReadyToSync(address addr) external onlyElectionsContract onlyWhenActive returns (bool committeeChanged, bool standbysChanged) {
		MemberData memory memberData = membersData[addr];
		if (!memberData.isMember) {
			return (false, false);
		}

		memberData.readyToSyncTimestamp = 0;
		memberData.readyForCommittee = false;
		return _rankAndUpdateMember(Member({
			addr: addr,
			data: memberData
		}));
	}

	function memberComplianceChange(address addr, bool isCompliant) external onlyElectionsContract onlyWhenActive returns (bool commiteeChanged, bool standbysChanged) {
		MemberData memory memberData = membersData[addr];
		if (!memberData.isMember) {
			return (false, false);
		}

		memberData.isCompliant = isCompliant;
		return _rankAndUpdateMember(Member({
			addr: addr,
			data: memberData
		}));
	}

	function addMember(address addr, uint256 weight, bool isCompliant) external onlyElectionsContract onlyWhenActive returns (bool committeeChanged, bool standbysChanged) {
		require(uint256(uint128(weight)) == weight, "weight is out of range");

		if (membersData[addr].isMember) {
			return (false, false);
		}

		return _rankAndUpdateMember(Member({
			addr: addr,
			data: MemberData({
				isMember: true,
				readyForCommittee: false,
				readyToSyncTimestamp: 0,
				weight: uint128(weight),
				isCompliant: isCompliant,
				isStandby: false,
				inCommittee: false
				})
		}));
	}

	/// @dev Called by: Elections contract
	/// Notifies a a member removal for example due to voteOut / voteUnready
	function removeMember(address addr) external onlyElectionsContract onlyWhenActive returns (bool committeeChanged, bool standbysChanged) {
		MemberData memory memberData = membersData[addr];
		memberData.isMember = false;
		(committeeChanged, standbysChanged) = _rankAndUpdateMember(Member({
			addr: addr,
			data: memberData
		}));
		delete membersData[addr];
	}

	/// @dev Called by: Elections contract
	/// Returns the committee members and their weights
	function getCommittee() external view returns (address[] memory addrs, uint256[] memory weights, bool[] memory compliance) {
		return _getCommittee();
	}

	/// @dev Returns the standy (out of committee) members and their weights
	function getStandbys() external view returns (address[] memory addrs, uint256[] memory weights) {
		return _getStandbys();
	}

	/// @dev Called by: Elections contract
	/// Returns the committee members and their weights
	function _getCommittee() public view returns (address[] memory addrs, uint256[] memory weights, bool[] memory compliance) {
		CommitteeInfo memory _committeeInfo = committeeInfo;
		uint bitmap = uint(_committeeInfo.committeeBitmap);
		uint committeeSize = _committeeInfo.committeeSize;

		addrs = new address[](committeeSize);
		weights = new uint[](committeeSize);
		compliance = new bool[](committeeSize);
		uint aInd = 0;
		uint pInd = 0;
		MemberData memory md;
		bitmap = uint(_committeeInfo.committeeBitmap);
		while (bitmap != 0) {
			if (bitmap & 1 == 1) {
				addrs[aInd] = participantAddresses[pInd];
				md = membersData[addrs[aInd]];
				weights[aInd] = md.weight;
				compliance[aInd] = md.isCompliant;
				aInd++;
			}
			bitmap >>= 1;
			pInd++;
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
		uint aInd = 0;
		uint pInd;
		address addr;
		while (aInd < standbysCount) {
			if (bitmap & 1 == 0) {
				addr = participantAddresses[pInd];
				if (addr != address(0)) {
					addrs[aInd] = addr;
					weights[aInd] = uint(membersData[addr].weight);
					aInd++;
				}
			}
			bitmap = bitmap >> 1;
			pInd++;
		}
	}

	/*
	 * Governance
	 */

	function setReadyToSyncTimeout(uint48 readyToSyncTimeout) external onlyFunctionalOwner /* todo onlyWhenActive */ {
		require(readyToSyncTimeout > 0, "readyToSyncTimeout must be larger than 0");
		emit ReadyToSyncTimeoutChanged(readyToSyncTimeout, settings.readyToSyncTimeout);
		settings.readyToSyncTimeout = readyToSyncTimeout;
	}

	function setMaxCommitteeAndStandbys(uint8 maxCommitteeSize, uint8 maxStandbys) external onlyFunctionalOwner /* todo onlyWhenActive */ {
		require(maxCommitteeSize > 0, "maxCommitteeSize must be larger than 0");
		require(maxStandbys > 0, "maxStandbys must be larger than 0");
		require(maxCommitteeSize + maxStandbys <= MAX_TOPOLOGY, "maxCommitteeSize + maxStandbys must be 32 at most");
		Settings memory _settings = settings;
		if (_settings.maxStandbys != maxStandbys) {
			emit MaxStandbysChanged(maxStandbys, _settings.maxStandbys);
			_settings.maxStandbys = maxStandbys;
		}
		if (_settings.maxCommitteeSize != maxCommitteeSize) {
			emit MaxCommitteeSizeChanged(maxCommitteeSize, _settings.maxCommitteeSize);
			_settings.maxCommitteeSize = maxCommitteeSize;
		}

		settings = _settings;
		updateCommittee(DummyMember(), _settings);
	}

	/*
     * Getters
     */

	/// @dev returns the current committee
	/// used also by the rewards and fees contracts
	function getCommitteeInfo() external view returns (address[] memory addrs, uint256[] memory weights, address[] memory orbsAddrs, bool[] memory compliance, bytes4[] memory ips) {
		(address[] memory _committee, uint256[] memory _weights,) = _getCommittee();
		return (_committee, _weights, _loadOrbsAddresses(_committee), _loadCompliance(_committee), _loadIps(_committee));
	}

	/// @dev returns the current standbys (out of commiteee) topology
	function getStandbysInfo() external view returns (address[] memory addrs, uint256[] memory weights, address[] memory orbsAddrs, bool[] memory compliance, bytes4[] memory ips) {
		(address[] memory _standbys, uint256[] memory _weights) = _getStandbys();
		return (_standbys, _weights, _loadOrbsAddresses(_standbys), _loadCompliance(_standbys) ,_loadIps(_standbys));
	}

	function getSettings() external view returns (uint48 readyToSyncTimeout, uint8 maxCommitteeSize, uint8 maxStandbys) {
		Settings memory _settings = settings;
		readyToSyncTimeout = _settings.readyToSyncTimeout;
		maxCommitteeSize = _settings.maxCommitteeSize;
		maxStandbys = _settings.maxStandbys;
	}

	/*
	 * Private
	 */

	function _loadOrbsAddresses(address[] memory addrs) private view returns (address[] memory) {
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

	function _loadCompliance(address[] memory addrs) private view returns (bool[] memory) {
		bool[] memory compliance = new bool[](addrs.length);
		for (uint i = 0; i < addrs.length; i++) {
			compliance[i] = membersData[addrs[i]].isCompliant;
		}
		return compliance;
	}

	function _rankAndUpdateMember(Member memory member) private returns (bool committeeChanged, bool standbysChanged) {
		(committeeChanged, standbysChanged) = _rankMember(member);
		membersData[member.addr] = member.data;
	}

	function _rankMember(Member memory member) private returns (bool committeeChanged, bool standbysChanged) {
		Settings memory _settings = settings;

		bool isParticipant = member.data.inCommittee || member.data.isStandby;
		if (!isParticipant && !qualifiesAsStandby(member)) {
			return (false, false);
		}

		return updateCommittee(member, _settings);
	}

	function isReadyToSyncStale(uint48 timestamp, bool currentlyInCommittee, Settings memory _settings) private view returns (bool) {
		return timestamp == 0 || !currentlyInCommittee && timestamp <= uint48(now) - _settings.readyToSyncTimeout;
	}

	function qualifiesAsStandby(Member memory member) private pure returns (bool) {
		return member.data.isMember && member.data.readyToSyncTimestamp != 0 && member.data.weight != 0;
	}

	function qualifiesAsStandby(Participant memory p) private pure returns (bool) {
		return qualifiesAsStandby(Member({
			data: p.data,
			addr: p.addr
		}));
	}

	function qualifiesForCommittee(Participant memory participant, Settings memory _settings, uint committeeSize) private view returns (bool) {
		return (
			participant.data.isMember &&
			participant.data.weight > 0 &&
			participant.data.readyForCommittee &&
			!isReadyToSyncStale(participant.data.readyToSyncTimestamp, participant.data.inCommittee, _settings) &&
			committeeSize < _settings.maxCommitteeSize
		);
	}

	function updateCommittee(Member memory changedMember, Settings memory _settings) private returns (bool committeeChanged, bool standbysChanged) {
		committeeChanged = changedMember.data.inCommittee;
		standbysChanged = changedMember.data.isStandby;

		address[] memory _participantsAddresses = participantAddresses;
		(Participant[] memory _participants, Participant memory changedMemberAsParticipant) = loadParticipantsSortedByWeights(_participantsAddresses, changedMember); // override stored member with preloaded one

		CommitteeInfo memory newCommitteeInfo;

		uint maxPos;
		Participant memory p;
		uint256 newWeightSortIndicesOneBasedBytes;
		bool changed;
		for (uint i = 0; i < _participants.length; i++) {
			p = _participants[i];
			if (qualifiesForCommittee(p, _settings, newCommitteeInfo.committeeSize)) {
				p.shouldBeInCommittee = true;
				newCommitteeInfo.committeeSize++;
				newCommitteeInfo.committeeBitmap |= uint64(uint(1) << p.pos);
			} else if (
				newCommitteeInfo.standbysCount < _settings.maxStandbys &&
				qualifiesAsStandby(p) &&
				!isReadyToSyncStale(p.data.readyToSyncTimestamp, p.data.inCommittee, _settings)
			) {
				p.shouldBeStandby = true;
				newCommitteeInfo.standbysCount++;
			}
		}

		for (uint i = 0; i < _participants.length; i++) {
			p = _participants[i];
			changed = false;
			if (p.shouldBeStandby != p.data.isStandby) {
				if (
					!p.shouldBeInCommittee && p.data.isStandby &&
					newCommitteeInfo.standbysCount < _settings.maxStandbys &&
					qualifiesAsStandby(p)
				) {
					p.shouldBeStandby = true;
					newCommitteeInfo.standbysCount++;
				}
				if (p.shouldBeStandby != p.data.isStandby) {
					p.data.isStandby = p.shouldBeStandby;
					if (p.shouldBeStandby && p.data.inCommittee) {
						p.data.readyToSyncTimestamp = uint48(now); // A committee member just became a standby, set its timestamp to now so will not be considered as timed-out
					}
					changed = true;
					standbysChanged = true;
				}
			}
			if (p.shouldBeInCommittee != p.data.inCommittee) {
				p.data.inCommittee = p.shouldBeInCommittee;
				changed = true;
				committeeChanged = true;
			}
			if (changed) {
				membersData[p.addr] = p.data;
			}
			if (!p.data.inCommittee && !p.data.isStandby) {
				// no longer a participant
				if (p.pos < _participantsAddresses.length) {
					participantAddresses[p.pos] = address(0);
				}
			} else {
				newWeightSortIndicesOneBasedBytes = (newWeightSortIndicesOneBasedBytes << 8) | uint8(p.pos + 1);
				if (maxPos < p.pos) maxPos = p.pos;
			}
		}

		// check if changed member is a new participant
		if (
			(changedMemberAsParticipant.data.inCommittee || changedMemberAsParticipant.data.isStandby) &&
			(_participantsAddresses.length == changedMemberAsParticipant.pos || _participantsAddresses[changedMemberAsParticipant.pos] == address(0))
		) {
			if (_participantsAddresses.length == changedMemberAsParticipant.pos) {
				participantAddresses.length++;
				maxPos = changedMemberAsParticipant.pos;
			}
			participantAddresses[changedMemberAsParticipant.pos] = changedMemberAsParticipant.addr;
		}

		if (_participantsAddresses.length > maxPos + 1) {
			participantAddresses.length = maxPos + 1;
		}

		weightSortIndicesOneBasedBytes = newWeightSortIndicesOneBasedBytes;
		committeeInfo = newCommitteeInfo; // todo check if changed before writing

		notifyChanges(_participants, newCommitteeInfo.committeeSize, newCommitteeInfo.standbysCount, committeeChanged, standbysChanged);
	}

	function notifyChanges(Participant[] memory participants, uint committeeSize, uint standbysCount, bool committeeChanged, bool standbysChanged) private {
		Participant memory p;
		uint ind;

		if (committeeChanged) {
			address[] memory committeeAddrs = new address[](committeeSize);
			uint[] memory committeeWeights = new uint[](committeeSize);
			bool[] memory committeeCompliance = new bool[](committeeSize); // todo - bitmap?
			ind = 0;
			for (uint i = 0; i < participants.length; i++) {
				p = participants[i];
				if (p.data.inCommittee) {
					committeeAddrs[ind] = p.addr;
					committeeCompliance[ind] = p.data.isCompliant;
					committeeWeights[ind++] = p.data.weight;
				}
			}
			_notifyCommitteeChanged(committeeAddrs, committeeWeights, committeeCompliance);
		}
		if (standbysChanged) {
			address[] memory standbyAddrs = new address[](standbysCount);
			uint[] memory standbyWeights = new uint[](standbysCount);
			bool[] memory standbysCompliance = new bool[](standbysCount); // todo - bitmap?
			ind = 0;
			for (uint i = 0; i < participants.length; i++) {
				p = participants[i];
				if (p.data.isStandby) {
					standbyAddrs[ind] = p.addr;
					standbysCompliance[ind] = p.data.isCompliant;
					standbyWeights[ind++] = p.data.weight;
				}
			}
			_notifyStandbysChanged(standbyAddrs, standbyWeights, standbysCompliance);
		}
	}

	function loadParticipantsSortedByWeights(address[] memory participantsAddrs, Member memory preloadedMember) private view returns (Participant[] memory _participants, Participant memory memberAsParticipant) {
		uint nParticipants;
		bool newMember = !preloadedMember.data.inCommittee && !preloadedMember.data.isStandby;
		address addr;
		uint firstFreeSlot = participantsAddrs.length;
		for (uint i = 0; i < participantsAddrs.length; i++) {
			addr = participantsAddrs[i];
			if (addr != address(0)) {
				nParticipants++;
			} else if (firstFreeSlot == participantsAddrs.length) {
				firstFreeSlot = i;
			}
		}
		if (newMember) nParticipants++;

		uint sortBytes = weightSortIndicesOneBasedBytes;
		_participants = new Participant[](nParticipants);
		uint pind = nParticipants - 1;
		uint pos;

		Participant memory p;
		MemberData memory md;
		uint preloadedInd = uint(-1);
		uint preloadedPos = uint(-1);
		while (sortBytes != 0) {
			pos = uint(sortBytes & 0xFF) - 1;
			addr = participantsAddrs[pos];
			if (addr != preloadedMember.addr) {
				md = membersData[addr];
				if (
					preloadedInd == uint(-1) &&
					(md.weight > preloadedMember.data.weight || (md.weight == preloadedMember.data.weight && uint(addr) > uint(preloadedMember.addr)))
				) {
					p = _participants[pind];
					p.addr = preloadedMember.addr;
					p.data = preloadedMember.data;
					preloadedInd = pind;
					memberAsParticipant = p;
					pind--;
				}
				p = _participants[pind];
				p.addr = addr;
				p.data = md;
				p.pos = uint8(pos);
				pind--;
			} else {
				preloadedPos = pos;
			}
			sortBytes = sortBytes >> 8;
		}

		if (preloadedInd == uint(-1)) {
			preloadedInd = 0;
			p = _participants[preloadedInd];
			p.addr = preloadedMember.addr;
			p.data = preloadedMember.data;
			memberAsParticipant = p;
		}
		if (newMember) {
			_participants[preloadedInd].pos = uint8(firstFreeSlot);
		} else {
			_participants[preloadedInd].pos = uint8(preloadedPos);
		}
	}

	function _notifyStandbysChanged(address[] memory addrs, uint256[] memory weights, bool[] memory compliance) private {
		emit StandbysChanged(addrs, weights, compliance);
	}

	function _notifyCommitteeChanged(address[] memory addrs, uint256[] memory weights, bool[] memory compliance) private {
		emit CommitteeChanged(addrs, weights, compliance);
		getRewardsContract().assignRewardsToCommittee(addrs, weights, compliance);
	}

	function DummyMember() private pure returns (Member memory member) {
		MemberData memory data;
		member = Member({
			addr: address(0),
			data: data
		});
	}

}
