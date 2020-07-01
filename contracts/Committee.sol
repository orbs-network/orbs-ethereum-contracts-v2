pragma solidity 0.5.16;

import "./spec_interfaces/ICommittee.sol";
import "./spec_interfaces/IValidatorsRegistration.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "./ContractRegistryAccessor.sol";
import "./WithClaimableFunctionalOwnership.sol";

/// @title Elections contract interface
contract Committee is ICommittee, ContractRegistryAccessor, WithClaimableFunctionalOwnership, Lockable {
	uint constant TOPOLOGY_SIZE = 32; // Cannot be greater than 32 (number of bytes in bytes32)

	struct CommitteeMember {
		address addr;
		uint96 weight;
	}
	CommitteeMember[] public committee;

	struct MemberData { // TODO can be reduced to 1 state entry
		uint96 weight;
		uint8 pos;
		bool isMember;
		bool isCompliant;

		bool inCommittee;
	}
	mapping (address => MemberData) membersData;

	// Derived properties
	struct CommitteeInfo {
		uint32 committeeBitmap; // TODO redundant, sort bytes can be used instead
		uint8 minCommitteeMemberPos;
		uint8 committeeSize;
	}
	CommitteeInfo committeeInfo;
	bytes32 weightSortIndicesOneBasedBytes;

	struct Settings {
		uint32 maxTimeBetweenRewardAssignments;
		uint8 maxCommitteeSize;
	}
	Settings settings;

	modifier onlyElectionsContract() {
		require(msg.sender == address(getElectionsContract()), "caller is not the elections");

		_;
	}

	function getMinMember(CommitteeInfo memory info) private returns (CommitteeMember memory minMember) {
		if (info.committeeSize == 0) {
			return CommitteeMember({
				addr: address(0),
				weight: uint96(0)
			});
		}

		return committee[info.minCommitteeMemberPos];
	}

	function findFreePos(CommitteeInfo memory info) private returns (uint8 pos) {
		pos = 0;
		uint32 bitmap = info.committeeBitmap;
		while (bitmap & 1 == 1) {
			bitmap >>= 1;
			pos++;
		}
	}

	function qualifiesToEnterCommittee(address addr, MemberData memory data, CommitteeInfo memory info, Settings memory _settings) private returns (bool qualified, uint8 entryPos) {
		if (!data.isMember || data.weight == 0) {
			return (false, 0);
		}

		if (info.committeeSize < _settings.maxCommitteeSize) {
			return (true, findFreePos(info));
		}

		CommitteeMember memory minMember = committee[info.minCommitteeMemberPos];
		if (data.weight < minMember.weight || data.weight == minMember.weight && addr < minMember.addr) {
			return (false, 0);
		}

		return (true, info.minCommitteeMemberPos);
	}

	function updateOnMemberChange(address addr, MemberData memory data) private returns (bool committeeChanged) {
		CommitteeInfo memory info = committeeInfo;
		Settings memory _settings = settings;
		bytes32 sortBytes = weightSortIndicesOneBasedBytes;

		if (!data.inCommittee) {
			(bool qualified, uint8 entryPos) = qualifiesToEnterCommittee(addr, data, info, _settings);
			if (!qualified) {
				if (data.isMember) {
					membersData[addr] = data;
				} else {
					delete membersData[addr];
				}
				return false;
			}

			(info, sortBytes) = removeMemberAtPos(entryPos, sortBytes, info);
			(info, sortBytes) = addToCommittee(addr, data, entryPos, sortBytes, info);
		} else {
			committee[data.pos].weight = data.weight;
		}

		(info, sortBytes) = (data.isMember && data.weight > 0) ?
			rankMember(addr, data, sortBytes, info) :
			_removeMember(addr, data, sortBytes, info);

		emit ValidatorCommitteeChange(addr, data.weight, data.isCompliant, data.inCommittee);

		if (data.isMember) {
			membersData[addr] = data;
		} else {
			delete membersData[addr];
		}

		committeeInfo = info;
		weightSortIndicesOneBasedBytes = sortBytes;

		assignRewardsIfNeeded(_settings);

		return true;
	}

	function addToCommittee(address addr, MemberData memory data, uint8 entryPos, bytes32 sortBytes, CommitteeInfo memory info) private returns (CommitteeInfo memory newInfo, bytes32 newSortByes) {
		committee[entryPos] = CommitteeMember({
			addr: addr,
			weight: data.weight
		});
		data.inCommittee = true;
		data.pos = entryPos;
		info.committeeBitmap |= uint32(uint(1) << entryPos);
		info.committeeSize++;

		sortBytes = bytes32Set(sortBytes, info.committeeSize - 1, byte(entryPos));
		return (info, sortBytes);
	}

	function _removeMember(address addr, MemberData memory data, bytes32 sortBytes, CommitteeInfo memory info) private returns (CommitteeInfo memory newInfo, bytes32 newSortBytes) {
		uint rank = 0;
		while (uint8(sortBytes[rank]) != data.pos) {
			rank++;
		}

		for (; rank < info.committeeSize - 1; rank++) {
			sortBytes = bytes32Set(sortBytes, rank, sortBytes[rank + 1]);
		}
		sortBytes = bytes32Set(sortBytes, rank, 0);

		info.committeeSize--;
		if (info.committeeSize > 0) {
			info.minCommitteeMemberPos = uint8(sortBytes[info.committeeSize - 1]);
		}
		info.committeeBitmap &= ~uint32(uint(1) << data.pos);

		delete committee[data.pos];
		data.inCommittee = false;

		return (info, sortBytes);
	}

	function removeMemberAtPos(uint8 pos, bytes32 sortBytes, CommitteeInfo memory info) private returns (CommitteeInfo memory newInfo, bytes32 newSortBytes) {
		if (info.committeeBitmap & (uint(1) << pos) == 0) {
			return (info, sortBytes);
		}

		address addr = committee[pos].addr;
		MemberData memory data = membersData[addr];

		(newInfo, newSortBytes) = _removeMember(addr, data, sortBytes, info);

		emit ValidatorCommitteeChange(addr, data.weight, data.isCompliant, false);

		membersData[addr] = data;
	}

	function rankMember(address addr, MemberData memory data, bytes32 sortBytes, CommitteeInfo memory info) private returns (CommitteeInfo memory newInfo, bytes32 newSortBytes) {
		uint rank = 0;
		while (uint8(sortBytes[rank]) != data.pos) {
			rank++;
		}

		CommitteeMember memory cur = CommitteeMember({addr: addr, weight: data.weight});
		CommitteeMember memory next;
		byte a;
		byte b;

		while (rank < info.committeeSize - 1) {
			next = committee[uint8(sortBytes[rank + 1])];
			if (cur.weight > next.weight || cur.weight == next.weight && cur.addr > next.addr) break;

			(a, b) = (sortBytes[rank + 1], sortBytes[rank]);
			sortBytes = bytes32Set(sortBytes, rank, a);
			sortBytes = bytes32Set(sortBytes, rank + 1, b);

			rank++;
		}

		while (rank > 0) {
			next = committee[uint8(sortBytes[rank - 1])];
			if (cur.weight < next.weight || cur.weight == next.weight && cur.addr < next.addr) break;

			(a, b) = (sortBytes[rank - 1], sortBytes[rank]);
			sortBytes = bytes32Set(sortBytes, rank, a);
			sortBytes = bytes32Set(sortBytes, rank - 1, b);

			rank--;
		}

		info.minCommitteeMemberPos = uint8(sortBytes[info.committeeSize - 1]);
		return (info, sortBytes);
	}

	function getMinCommitteeMemberWeight() external view returns (uint96) {
		return committee[committeeInfo.minCommitteeMemberPos].weight;
	}

	function assignRewardsIfNeeded(Settings memory _settings) private {
        IRewards rewardsContract = getRewardsContract();
        uint lastAssignment = rewardsContract.getLastRewardAssignmentTime();
        if (now - lastAssignment < _settings.maxTimeBetweenRewardAssignments) {
             return;
        }

		(address[] memory committeeAddrs, uint[] memory committeeWeights, bool[] memory committeeCompliance) = _getCommittee();
        rewardsContract.assignRewardsToCommittee(committeeAddrs, committeeWeights, committeeCompliance);

		emit CommitteeSnapshot(committeeAddrs, committeeWeights, committeeCompliance);
	}

	constructor(uint _maxCommitteeSize, uint32 maxTimeBetweenRewardAssignments) public {
		require(_maxCommitteeSize > 0, "maxCommitteeSize must be larger than 0");
		require(_maxCommitteeSize <= TOPOLOGY_SIZE, "maxCommitteeSize must be 32 at most");
		settings = Settings({
			maxCommitteeSize: uint8(_maxCommitteeSize),
			maxTimeBetweenRewardAssignments: maxTimeBetweenRewardAssignments
		});

		committee.length = TOPOLOGY_SIZE;
	}

	/*
	 * Methods restricted to other Orbs contracts
	 */

	/// @dev Called by: Elections contract
	/// Notifies a weight change for sorting to a relevant committee member.
	/// weight = 0 indicates removal of the member from the committee (for example on unregister, voteUnready, voteOut)
	function memberWeightChange(address addr, uint256 weight) external onlyElectionsContract onlyWhenActive returns (bool committeeChanged) {
		require(uint256(uint96(weight)) == weight, "weight is out of range");

		MemberData memory data = membersData[addr];
		if (!data.isMember) {
			return false;
		}
		data.weight = uint96(weight);
		return updateOnMemberChange(addr, data);
	}

	function memberComplianceChange(address addr, bool isCompliant) external onlyElectionsContract onlyWhenActive returns (bool committeeChanged) {
		MemberData memory data = membersData[addr];
		if (!data.isMember) {
			return false;
		}

		data.isCompliant = isCompliant;
		return updateOnMemberChange(addr, data);
	}

	function addMember(address addr, uint256 weight, bool isCompliant) external onlyElectionsContract onlyWhenActive returns (bool committeeChanged) {
		require(uint256(uint96(weight)) == weight, "weight is out of range");

		if (membersData[addr].isMember) {
			return false;
		}

		return updateOnMemberChange(addr, MemberData({
			isMember: true,
			weight: uint96(weight),
			isCompliant: isCompliant,
			inCommittee: false,
			pos: uint8(-1)
		}));
	}

	/// @dev Called by: Elections contract
	/// Notifies a a member removal for example due to voteOut / voteUnready
	function removeMember(address addr) external onlyElectionsContract onlyWhenActive returns (bool committeeChanged) {
		MemberData memory data = membersData[addr];

		if (!membersData[addr].isMember) {
			return false;
		}

		data.isMember = false;
		return updateOnMemberChange(addr, data);
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
				addrs[aInd] = committee[pInd].addr;
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
		require(maxCommitteeSize <= TOPOLOGY_SIZE, "maxCommitteeSize must be 32 at most");
		Settings memory _settings = settings;
		emit MaxCommitteeSizeChanged(maxCommitteeSize, _settings.maxCommitteeSize);
		_settings.maxCommitteeSize = maxCommitteeSize;
		settings = _settings;

		CommitteeInfo memory info = committeeInfo;
		if (maxCommitteeSize >= info.committeeSize) {
			return;
		}

		bytes32 sortBytes = weightSortIndicesOneBasedBytes;
		for (int rank = int(info.committeeSize); rank >= int(maxCommitteeSize); rank--) {
			(info, sortBytes) = removeMemberAtPos(uint8(sortBytes[uint(rank)]), sortBytes, info);
		}
		committeeInfo = info;
		weightSortIndicesOneBasedBytes = sortBytes;
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

	function bytes32Set(bytes32 _bytes32, uint i, byte v) private pure returns (bytes32) {
		i = 31 - i;
		return _bytes32 & ~bytes32(uint(0xFF) << (i << 3)) | bytes32(uint(uint8(v)) << (i << 3));
	}
}
