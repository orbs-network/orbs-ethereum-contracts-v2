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
		bool isMember; // exists
		bool readyToSync;
		bool readyForCommittee;
		bool isCompliant;

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

		bool inPrevCommittee;
		bool inNextCommittee;
	} // Never in state, only in memory

	struct Settings { // TODO can be reduced to 2-3 state entries
		uint32 maxTimeBetweenRewardAssignments;
		uint8 maxCommitteeSize;
	}
	Settings settings;

	uint256 weightSortIndicesOneBasedBytes;

	// Derived properties
	struct CommitteeInfo {
		uint64 committeeBitmap;
		uint8 committeeSize;
	}
	CommitteeInfo committeeInfo;

	modifier onlyElectionsContract() {
		require(msg.sender == address(getElectionsContract()), "caller is not the elections");

		_;
	}

	constructor(uint _maxCommitteeSize, uint32 maxTimeBetweenRewardAssignments) public {
		require(_maxCommitteeSize > 0, "maxCommitteeSize must be larger than 0");
		require(_maxCommitteeSize <= MAX_TOPOLOGY, "maxCommitteeSize must be 32 at most");
		settings = Settings({
			maxCommitteeSize: uint8(_maxCommitteeSize),
			maxTimeBetweenRewardAssignments: maxTimeBetweenRewardAssignments
		});

		participantAddresses.length = MAX_TOPOLOGY + 1;
	}

	/*
	 * Methods restricted to other Orbs contracts
	 */

	/// @dev Called by: Elections contract
	/// Notifies a weight change for sorting to a relevant committee member.
	/// weight = 0 indicates removal of the member from the committee (for example on unregister, voteUnready, voteOut)
	function memberWeightChange(address addr, uint256 weight) external onlyElectionsContract onlyWhenActive returns (bool committeeChanged) {
		require(uint256(uint128(weight)) == weight, "weight is out of range");

		MemberData memory memberData = membersData[addr];
		if (!memberData.isMember) {
			return false;
		}
		memberData.weight = uint128(weight);
		return _rankAndUpdateMember(Member({
			addr: addr,
			data: memberData
		}));
	}

	function memberReadyToSync(address addr, bool readyForCommittee) external onlyElectionsContract onlyWhenActive returns (bool committeeChanged) {
		MemberData memory memberData = membersData[addr];
		if (!memberData.isMember) {
			return false;
		}

		memberData.readyToSync = true;
		memberData.readyForCommittee = readyForCommittee;
		return _rankAndUpdateMember(Member({
			addr: addr,
			data: memberData
		}));
	}

	function memberNotReadyToSync(address addr) external onlyElectionsContract onlyWhenActive returns (bool committeeChanged) {
		MemberData memory memberData = membersData[addr];
		if (!memberData.isMember) {
			return false;
		}

		memberData.readyToSync = false;
		memberData.readyForCommittee = false;
		return _rankAndUpdateMember(Member({
			addr: addr,
			data: memberData
		}));
	}

	function memberComplianceChange(address addr, bool isCompliant) external onlyElectionsContract onlyWhenActive returns (bool commiteeChanged) {
		MemberData memory memberData = membersData[addr];
		if (!memberData.isMember) {
			return false;
		}

		memberData.isCompliant = isCompliant;
		return _rankAndUpdateMember(Member({
			addr: addr,
			data: memberData
		}));
	}

	function addMember(address addr, uint256 weight, bool isCompliant) external onlyElectionsContract onlyWhenActive returns (bool committeeChanged) {
		require(uint256(uint128(weight)) == weight, "weight is out of range");

		if (membersData[addr].isMember) {
			return false;
		}

		return _rankAndUpdateMember(Member({
			addr: addr,
			data: MemberData({
				isMember: true,
				readyToSync: false,
				readyForCommittee: false,
				weight: uint128(weight),
				isCompliant: isCompliant,
				inCommittee: false
			})
		}));
	}

	/// @dev Called by: Elections contract
	/// Notifies a a member removal for example due to voteOut / voteUnready
	function removeMember(address addr) external onlyElectionsContract onlyWhenActive returns (bool committeeChanged) {
		MemberData memory memberData = membersData[addr];
		memberData.isMember = false;
		committeeChanged = _rankAndUpdateMember(Member({
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

	/*
	 * Governance
	 */

	function setMaxTimeBetweenRewardAssignments(uint32 maxTimeBetweenRewardAssignments) external onlyFunctionalOwner /* todo onlyWhenActive */ {
		emit MaxTimeBetweenRewardAssignmentsChanged(maxTimeBetweenRewardAssignments, settings.maxTimeBetweenRewardAssignments);
		settings.maxTimeBetweenRewardAssignments = maxTimeBetweenRewardAssignments;
	}

	function setMaxCommittee(uint8 maxCommitteeSize) external onlyFunctionalOwner /* todo onlyWhenActive */ {
		require(maxCommitteeSize > 0, "maxCommitteeSize must be larger than 0");
		require(maxCommitteeSize <= MAX_TOPOLOGY, "maxCommitteeSize must be 32 at most");
		Settings memory _settings = settings;
		emit MaxCommitteeSizeChanged(maxCommitteeSize, _settings.maxCommitteeSize);
		_settings.maxCommitteeSize = maxCommitteeSize;
		settings = _settings;

		updateCommittee(DummyMember(), _settings);
	}

	/*
     * Getters
     */

	/// @dev returns the current committee
	/// used also by the rewards and fees contracts
	function getCommitteeInfo() external view returns (address[] memory addrs, uint256[] memory weights, address[] memory orbsAddrs, bool[] memory compliance, bytes4[] memory ips) {
		(address[] memory committee, uint256[] memory weights, bool[] memory compliance) = _getCommittee();
		return (committee, weights, _loadOrbsAddresses(committee), compliance, _loadIps(committee));
	}

	function getSettings() external view returns (uint32 maxTimeBetweenRewardAssignments, uint8 maxCommitteeSize) {
		Settings memory _settings = settings;
		maxTimeBetweenRewardAssignments = _settings.maxTimeBetweenRewardAssignments;
		maxCommitteeSize = _settings.maxCommitteeSize;
	}

	/*
	 * Private
	 */

	function _loadOrbsAddresses(address[] memory addrs) private view returns (address[] memory) {
		return getValidatorsRegistrationContract().getValidatorsOrbsAddress(addrs);
	}

	function _loadIps(address[] memory addrs) private view returns (bytes4[] memory) {
		return getValidatorsRegistrationContract().getValidatorIps(addrs);
	}

	function _loadCompliance(address[] memory addrs) private view returns (bool[] memory) {
		bool[] memory compliance = new bool[](addrs.length);
		for (uint i = 0; i < addrs.length; i++) {
			compliance[i] = membersData[addrs[i]].isCompliant;
		}
		return compliance;
	}

	function _rankAndUpdateMember(Member memory member) private returns (bool committeeChanged) {
		if (!member.data.inCommittee && !qualifiesForCommittee(member.data)) {
			membersData[member.addr] = member.data;
			return false;
		}
		committeeChanged = updateCommittee(member, settings);
		membersData[member.addr] = member.data;
	}

	function qualifiesForCommittee(MemberData memory data) private pure returns (bool) {
		return (
			data.isMember &&
			data.weight > 0 &&
			data.readyForCommittee
		);
	}

	function markCommitteeMembers(Participant[] memory sortedParticipants, Settings memory _settings) private view returns (CommitteeInfo memory newInfo) {
		Participant memory p;
		for (uint i = 0; i < sortedParticipants.length; i++) {
			p = sortedParticipants[i];

			// Can current participant join the committee?
			if (newInfo.committeeSize < _settings.maxCommitteeSize && qualifiesForCommittee(p.data)) {
				p.inNextCommittee = true;
				newInfo.committeeSize++;
				newInfo.committeeBitmap |= uint64(uint(1) << p.pos);
			}
		}
	}

	function updateCommittee(Member memory changedMember, Settings memory _settings) private returns (bool committeeChanged) {
		committeeChanged = changedMember.data.inCommittee;

		(Participant[] memory sortedParticipants, Participant memory changedParticipant) = loadParticipantsSortedByWeights(changedMember); // override stored member with preloaded one

		// First iteration - find all committee members

		CommitteeInfo memory newInfo = markCommitteeMembers(sortedParticipants, _settings);

		// Update metadata of changed participants
		uint256 newSortBytes;
		Participant memory p;

		for (uint i = 0; i < sortedParticipants.length; i++) {
			p = sortedParticipants[i];

			// Update a participant that joined/left the committee
			if (p.inNextCommittee != p.inPrevCommittee) {
				p.data.inCommittee = p.inNextCommittee;
				membersData[p.addr] = p.data;
				committeeChanged = true;
			}

            // Emit a status changed event if the joined/left committee, or of the changed member is not evicted (e.g. weight change of a committee member)
            if (p.inNextCommittee != p.inPrevCommittee || p.addr == changedParticipant.addr && p.inPrevCommittee) {
                emit ValidatorCommitteeChange(p.addr, p.data.weight, p.data.isCompliant, p.inNextCommittee == true);
            }

			if (p.data.inCommittee) {
				newSortBytes = (newSortBytes << 8) | uint8(p.pos + 1);
			} else {
				participantAddresses[p.pos] = address(0); // no longer a participant
			}
		}

		// check if changed member is a new participant
		if (!changedParticipant.inPrevCommittee && changedParticipant.inNextCommittee) {
			participantAddresses[changedParticipant.pos] = changedParticipant.addr;
		}

		weightSortIndicesOneBasedBytes = newSortBytes;
		committeeInfo = newInfo; // todo check if changed before writing

        if (committeeChanged) {
            notifyChanges(sortedParticipants, newInfo.committeeSize, _settings);
        }
	}

	function notifyChanges(Participant[] memory participants, uint committeeSize, Settings memory _settings) private {
        IRewards rewardsContract = getRewardsContract();
        uint lastAssignment = rewardsContract.getLastRewardAssignmentTime();
        if (now - lastAssignment < _settings.maxTimeBetweenRewardAssignments) {
             return;
        }

		(address[] memory committeeAddrs, uint[] memory committeeWeights, bool[] memory committeeCompliance) = buildCommitteeArrays(participants, committeeSize);
        rewardsContract.assignRewardsToCommittee(committeeAddrs, committeeWeights, committeeCompliance);

		emit CommitteeSnapshot(committeeAddrs, committeeWeights, committeeCompliance);
	}

	function buildCommitteeArrays(Participant[] memory participants, uint expectedCount) private pure returns (address[] memory addrs, uint256[] memory weights, bool[] memory compliance) {
		addrs = new address[](expectedCount);
		weights = new uint[](expectedCount);
		compliance = new bool[](expectedCount);
		Participant memory p;
		uint ind;
		for (uint i = 0; i < participants.length; i++) {
			p = participants[i];
			if (p.data.inCommittee) {
				addrs[ind] = p.addr;
				compliance[ind] = p.data.isCompliant;
				weights[ind++] = p.data.weight;
			}
		}
	}

	function loadParticipantsSortedByWeights(Member memory changedMember) private view returns (Participant[] memory sortedParticipants, Participant memory changedParticipant) {
		address[] memory _participantAddresses = participantAddresses;
		bool newParticipant = !changedMember.data.inCommittee;

		CommitteeInfo memory _committeeInfo = committeeInfo;
		uint nParticipants = _committeeInfo.committeeSize;
		if (newParticipant) nParticipants++;
		sortedParticipants = new Participant[](nParticipants);

		MemberData memory data;
		address addr;
		uint pos;
		uint changedMemberSortedInd = uint(-1);
		uint changedMemberPos = uint(-1);

		uint pind = nParticipants - 1;
		for (uint sortBytes = weightSortIndicesOneBasedBytes; sortBytes != 0; sortBytes >>= 8) {
			pos = uint(sortBytes & 0xFF) - 1;

			addr = _participantAddresses[pos];

			if (addr == changedMember.addr) { // Skip the preloaded member, it will be added later
				changedMemberPos = pos;
				continue;
			}

			data = membersData[addr];

			// Check if the preloaded member has less weight than the current member, if so add the preloaded member first
			if (
				changedMemberSortedInd == uint(-1) && // we did not add it already
				(data.weight > changedMember.data.weight || (data.weight == changedMember.data.weight && uint(addr) > uint(changedMember.addr))) // has less weight than current
			) {
				changedMemberSortedInd = pind;
				pind--;
			}

			sortedParticipants[pind] = Participant({
				addr: addr,
				data: data,
				pos : uint8(pos),
				inPrevCommittee: data.inCommittee,
				inNextCommittee: false
			});
			pind--;
		}

		if (changedMemberSortedInd == uint(-1)) changedMemberSortedInd = 0; // Preloaded member was not added yet - meaning that it has the highest weight and should be placed first

		// Fill data of preloaded member to the list in the determined position
		changedParticipant = Participant({
			addr: changedMember.addr,
			data: changedMember.data,
			pos : uint8(newParticipant ? findFirstFreeSlotIndex(_participantAddresses) : changedMemberPos),
			inPrevCommittee: changedMember.data.inCommittee,
			inNextCommittee: false
		});
		sortedParticipants[changedMemberSortedInd] = changedParticipant;
	}

	function findFirstFreeSlotIndex(address[] memory addrs) private pure returns (uint) {
		for (uint i = 0; i < addrs.length; i++) {
			if (addrs[i] == address(0)) {
				return i;
			}
		}
		revert("unreachable - free slot must always be present");
	}

	function DummyMember() private pure returns (Member memory member) {
		MemberData memory data;
		member = Member({
			addr: address(0),
			data: data
		});
	}

}
