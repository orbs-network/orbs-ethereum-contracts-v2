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

	uint8 constant ROLE_EXCLUDED = 0;
	uint8 constant ROLE_COMMITTEE = 1;
	uint8 constant ROLE_STANDBY = 2;

	struct MemberData { // TODO can be reduced to 1 state entry
		uint128 weight;
		uint48 readyToSyncTimestamp;
		bool isMember; // exists
		bool readyForCommittee;
		bool isCompliant;

		uint8 role;
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

		MemberData oldData;
		uint8 oldRole;
		uint8 newRole;
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

		participantAddresses.length = MAX_TOPOLOGY + 1;
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
				role: ROLE_EXCLUDED
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

		if (!isCommitteeMemberOrStandby(member.data) && !qualifiesAsStandby(member.data)) {
			return (false, false);
		}

		return updateCommittee(member, _settings);
	}

	function isTimedOut(Participant memory p, Settings memory _settings) private view returns (bool) {
		return p.data.readyToSyncTimestamp == 0 || (p.oldRole != ROLE_COMMITTEE && p.data.readyToSyncTimestamp <= uint48(now) - _settings.readyToSyncTimeout);
	}

	function qualifiesAsStandby(MemberData memory data) private pure returns (bool) {
		return data.isMember && data.readyToSyncTimestamp != 0 && data.weight != 0;
	}

	function qualifiesForCommittee(MemberData memory data) private pure returns (bool) {
		return (
			data.isMember &&
			data.weight > 0 &&
			data.readyForCommittee
		);
	}

	function updateCommittee(Member memory changedMember, Settings memory _settings) private returns (bool committeeChanged, bool standbysChanged) {
		committeeChanged = changedMember.data.role == ROLE_COMMITTEE;
		standbysChanged = changedMember.data.role == ROLE_STANDBY;

		CommitteeInfo memory curInfo = committeeInfo;
		CommitteeInfo memory newInfo;

		Participant[] memory sortedParticipants = loadParticipantsSortedByWeights(changedMember, curInfo); // override stored member with preloaded one


		// First iteration - find all committee members and non-timed-out standbys

		Participant memory p;
		for (uint i = 0; i < sortedParticipants.length; i++) {
			p = sortedParticipants[i];

			if (isTimedOut(p, _settings)) continue;

			// Can current participant join the committee?
			if (newInfo.committeeSize < _settings.maxCommitteeSize && qualifiesForCommittee(p.data)) {
				p.newRole = ROLE_COMMITTEE;
				newInfo.committeeSize++;
				newInfo.committeeBitmap |= uint64(uint(1) << p.pos);
				continue;
			}

			// Otherwise, can it be a standby?
			if (newInfo.standbysCount < _settings.maxStandbys && qualifiesAsStandby(p.data)) {
				p.newRole = ROLE_STANDBY;
				newInfo.standbysCount++;
			}
		}

		// Second iteration: - Add timed out standbys until reaching the maxStandbys limitation.
		//					 - Update metadata of changed participants

		Participant memory changedParticipant;
		uint256 newSortBytes;
		for (uint i = 0; i < sortedParticipants.length; i++) {
			p = sortedParticipants[i];

			// Check if an excluded participant can become a standby
			if (
				p.newRole == ROLE_EXCLUDED && // we decided to exclude it in the first iteration
				newInfo.standbysCount < _settings.maxStandbys && qualifiesAsStandby(p.data) // But it qualifies as a standby the there's room
			) {
				p.newRole = ROLE_STANDBY;
				newInfo.standbysCount++;
			}

			// Update changed participants
			if (p.newRole != p.oldRole) {
				if (p.oldRole == ROLE_COMMITTEE && p.newRole == ROLE_STANDBY) {
					p.data.readyToSyncTimestamp = uint48(now); // A committee member just became a standby, set its timestamp to now so will not be considered as timed-out
				}
				committeeChanged = committeeChanged || p.oldRole == ROLE_COMMITTEE || p.newRole == ROLE_COMMITTEE;
				standbysChanged = standbysChanged || p.oldRole == ROLE_STANDBY || p.newRole == ROLE_STANDBY;

				p.data.role = p.newRole;
				membersData[p.addr] = p.data;
			}

			if (isCommitteeMemberOrStandby(p.data)) {
				newSortBytes = (newSortBytes << 8) | uint8(p.pos + 1);
			} else {
				participantAddresses[p.pos] = address(0); // no longer a participant
			}

			if (p.addr == changedMember.addr) changedParticipant = p;
		}

		// check if changed member is a new participant
		if (changedParticipant.oldRole == ROLE_EXCLUDED && changedParticipant.newRole != ROLE_EXCLUDED) {
			participantAddresses[changedParticipant.pos] = changedParticipant.addr;
		}

		weightSortIndicesOneBasedBytes = newSortBytes;
		committeeInfo = newInfo; // todo check if changed before writing

		notifyChanges(sortedParticipants, newInfo.committeeSize, newInfo.standbysCount, curInfo.committeeSize, committeeChanged, standbysChanged);
	}

	function isCommitteeMemberOrStandby(MemberData memory md) private pure returns (bool) {
		return md.role != ROLE_EXCLUDED;
	}

	function notifyChanges(Participant[] memory participants, uint committeeSize, uint standbysCount, uint prevCommitteeSize, bool committeeChanged, bool standbysChanged) private {
		Participant memory p;
		uint ind;

		if (committeeChanged) {
			assignRewardsToPreviousCommittee(participants, prevCommitteeSize);

			address[] memory committeeAddrs = new address[](committeeSize);
			uint[] memory committeeWeights = new uint[](committeeSize);
			bool[] memory committeeCompliance = new bool[](committeeSize); // todo - bitmap?
			ind = 0;
			for (uint i = 0; i < participants.length; i++) {
				p = participants[i];
				if (p.data.role == ROLE_COMMITTEE) {
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
				if (p.data.role == ROLE_STANDBY) {
					standbyAddrs[ind] = p.addr;
					standbysCompliance[ind] = p.data.isCompliant;
					standbyWeights[ind++] = p.data.weight;
				}
			}
			_notifyStandbysChanged(standbyAddrs, standbyWeights, standbysCompliance);
		}
	}

	function assignRewardsToPreviousCommittee(Participant[] memory participants, uint prevCommitteeSize) private {
		address[] memory addrs = new address[](prevCommitteeSize);
		uint[] memory weights = new uint[](prevCommitteeSize);
		bool[] memory compliance = new bool[](prevCommitteeSize);
		uint ind = 0;
		Participant memory p;
		for (uint i = 0; i < participants.length; i++) {
			p = participants[i];
			if (p.oldRole == ROLE_COMMITTEE) {
				addrs[ind] = p.addr;
				compliance[ind] = p.oldData.isCompliant;
				weights[ind++] = p.oldData.weight;
			}
		}

		getRewardsContract().assignRewardsToCommittee(addrs, weights, compliance);
	}

	function loadParticipantsSortedByWeights(Member memory preloadedMember, CommitteeInfo memory info) private view returns (Participant[] memory participants) {
		address[] memory _participantAddresses = participantAddresses;
		bool newMember = !isCommitteeMemberOrStandby(preloadedMember.data);

		uint nParticipants = info.committeeSize + info.standbysCount;
		if (newMember) nParticipants++;
		participants = new Participant[](nParticipants);

		MemberData memory md;
		address addr;
		uint pos;
		uint preloadedInd = uint(-1);
		uint preloadedPos = uint(-1);

		uint pind = nParticipants - 1;
		for (uint sortBytes = weightSortIndicesOneBasedBytes; sortBytes != 0; sortBytes >>= 8) {
			pos = uint(sortBytes & 0xFF) - 1;

			addr = _participantAddresses[pos];

			if (addr == preloadedMember.addr) { // Skip the preloaded member, it will be added later
				preloadedPos = pos;
				continue;
			}

			md = membersData[addr];

			// Check if the preloaded member should have less weight than the current member, if so add the preloaded member first
			if (
				preloadedInd == uint(-1) && // was not previously added
				(md.weight > preloadedMember.data.weight || (md.weight == preloadedMember.data.weight && uint(addr) > uint(preloadedMember.addr))) // has less weight than current
			) {
				preloadedInd = pind;
				pind--;
			}

			participants[pind] = Participant({
				addr: addr,
				data: md,
				pos : uint8(pos),
				newRole: ROLE_EXCLUDED,
				oldRole: md.role,
				oldData: md
			});
			pind--;
		}

		if (preloadedInd == uint(-1)) preloadedInd = 0; // Preloaded member was not added yet - meaning that it has the highest weight

		// Add the preloaded member to the list in the determined position
		participants[preloadedInd] = Participant({
			addr: preloadedMember.addr,
			data: preloadedMember.data,
			pos : uint8(newMember ? findFirstFreeSlotIndex(_participantAddresses) : preloadedPos),
			newRole: ROLE_EXCLUDED,
			oldRole: preloadedMember.data.role,
			oldData: membersData[preloadedMember.addr]
		});
	}

	function findFirstFreeSlotIndex(address[] memory addrs) private pure returns (uint) {
		for (uint i = 0; i < addrs.length; i++) {
			if (addrs[i] == address(0)) {
				return i;
			}
		}
		revert("unreachable - free slot must always be present");
	}

	function _notifyStandbysChanged(address[] memory addrs, uint256[] memory weights, bool[] memory compliance) private {
		emit StandbysChanged(addrs, weights, compliance);
	}

	function _notifyCommitteeChanged(address[] memory addrs, uint256[] memory weights, bool[] memory compliance) private {
		emit CommitteeChanged(addrs, weights, compliance);
	}

	function DummyMember() private pure returns (Member memory member) {
		MemberData memory data;
		member = Member({
			addr: address(0),
			data: data
		});
	}

}
