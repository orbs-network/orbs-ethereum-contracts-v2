// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;

import "./spec_interfaces/ICommittee.sol";
import "./spec_interfaces/IGuardiansRegistration.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "./ContractRegistryAccessor.sol";
import "solidity-bytes-utils/contracts/BytesLib.sol";
import "./Lockable.sol";
import "./interfaces/IRewards.sol";
import "./interfaces/IElections.sol";
import "./ManagedContract.sol";
import "./spec_interfaces/ICertification.sol";

/// @title Elections contract interface
contract Committee is ICommittee, ManagedContract {
	using BytesLib for bytes;

	uint constant MAX_COMMITTEE_ARRAY_SIZE = 32; // Cannot be greater than 32 (number of bytes in bytes32)

	struct CommitteeMember {
		address addr;
		uint96 weight;
	}
	CommitteeMember[MAX_COMMITTEE_ARRAY_SIZE] public committee;

	struct MemberStatus {
		bool isMember;
		bool inCommittee;
		uint8 pos;
	}
	mapping (address => MemberStatus) membersStatus;

	struct MemberData {
		MemberStatus status;
		uint96 weight;
		bool isCertified;
	}

	// Derived properties
	struct CommitteeInfo {
		uint32 committeeBitmap; // TODO redundant, sort bytes can be used instead
		uint8 minCommitteeMemberPos;
		uint8 committeeSize;
	}
	CommitteeInfo committeeInfo;
	bytes32 committeeSortBytes;

	struct Settings {
		uint32 maxTimeBetweenRewardAssignments;
		uint8 maxCommitteeSize;
	}
	Settings public settings;

	modifier onlyElectionsContract() {
		require(msg.sender == address(electionsContract), "caller is not the elections");

		_;
	}

	function findFreePos(CommitteeInfo memory info) private pure returns (uint8 pos) {
		pos = 0;
		uint32 bitmap = info.committeeBitmap;
		while (bitmap & 1 == 1) {
			bitmap >>= 1;
			pos++;
		}
	}

	function qualifiesToEnterCommittee(address addr, MemberData memory data, CommitteeInfo memory info, Settings memory _settings) private view returns (bool qualified, uint8 entryPos) {
		if (!data.status.isMember || data.weight == 0) {
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

	function saveMemberStatus(address addr, MemberStatus memory status) private {
		if (status.isMember) {
			membersStatus[addr] = status;
		} else {
			delete membersStatus[addr];
		}
	}

	function updateOnMemberChange(address addr, MemberData memory data) private returns (bool committeeChanged) {
		CommitteeInfo memory info = committeeInfo;
		Settings memory _settings = settings;
		bytes memory sortBytes = abi.encodePacked(committeeSortBytes);

		if (!data.status.inCommittee) {
			(bool qualified, uint8 entryPos) = qualifiesToEnterCommittee(addr, data, info, _settings);
			if (!qualified) {
				return false;
			}

			(info, sortBytes) = removeMemberAtPos(entryPos, sortBytes, info);
			(info, sortBytes) = addToCommittee(addr, data, entryPos, sortBytes, info);
		}

		(info, sortBytes) = (data.status.isMember && data.weight > 0) ?
			rankMember(addr, data, sortBytes, info) :
			removeMemberFromCommittee(data, sortBytes, info);

		emit GuardianCommitteeChange(addr, data.weight, data.isCertified, data.status.inCommittee);

		committeeInfo = info;
		committeeSortBytes = sortBytes.toBytes32(0);

		assignRewardsIfNeeded(_settings);

		return true;
	}

	function addToCommittee(address addr, MemberData memory data, uint8 entryPos, bytes memory sortBytes, CommitteeInfo memory info) private returns (CommitteeInfo memory newInfo, bytes memory newSortByes) {
		committee[entryPos] = CommitteeMember({
			addr: addr,
			weight: data.weight
		});
		data.status.inCommittee = true;
		data.status.pos = entryPos;
		info.committeeBitmap |= uint32(uint(1) << entryPos);
		info.committeeSize++;

		sortBytes[info.committeeSize - 1] = byte(entryPos);
		return (info, sortBytes);
	}

	function removeMemberFromCommittee(MemberData memory data, bytes memory sortBytes, CommitteeInfo memory info) private returns (CommitteeInfo memory newInfo, bytes memory newSortBytes) {
		uint rank = 0;
		while (uint8(sortBytes[rank]) != data.status.pos) {
			rank++;
		}

		for (; rank < info.committeeSize - 1; rank++) {
			sortBytes[rank] = sortBytes[rank + 1];
		}
		sortBytes[rank] = 0;

		info.committeeSize--;
		if (info.committeeSize > 0) {
			info.minCommitteeMemberPos = uint8(sortBytes[info.committeeSize - 1]);
		}
		info.committeeBitmap &= ~uint32(uint(1) << data.status.pos);

		delete committee[data.status.pos];
		data.status.inCommittee = false;

		return (info, sortBytes);
	}

	function removeMemberAtPos(uint8 pos, bytes memory sortBytes, CommitteeInfo memory info) private returns (CommitteeInfo memory newInfo, bytes memory newSortBytes) {
		if (info.committeeBitmap & (uint(1) << pos) == 0) {
			return (info, sortBytes);
		}

		CommitteeMember memory cm = committee[pos];

		MemberData memory data = MemberData({
			status: MemberStatus({
				pos: pos,
				inCommittee: true,
				isMember: true
			}),
			weight: cm.weight,
			isCertified: certificationContract.isGuardianCertified(cm.addr)
		});

		(newInfo, newSortBytes) = removeMemberFromCommittee(data, sortBytes, info);

		emit GuardianCommitteeChange(cm.addr, data.weight, data.isCertified, false);

		membersStatus[cm.addr] = data.status;
	}

	function rankMember(address addr, MemberData memory data, bytes memory sortBytes, CommitteeInfo memory info) private view returns (CommitteeInfo memory newInfo, bytes memory newSortBytes) {
		uint rank = 0;
		while (uint8(sortBytes[rank]) != data.status.pos) {
			rank++;
		}

		CommitteeMember memory cur = CommitteeMember({addr: addr, weight: data.weight});
		CommitteeMember memory next;

		while (rank < info.committeeSize - 1) {
			next = committee[uint8(sortBytes[rank + 1])];
			if (cur.weight > next.weight || cur.weight == next.weight && cur.addr > next.addr) break;

			(sortBytes[rank], sortBytes[rank + 1]) = (sortBytes[rank + 1], sortBytes[rank]);
			rank++;
		}

		while (rank > 0) {
			next = committee[uint8(sortBytes[rank - 1])];
			if (cur.weight < next.weight || cur.weight == next.weight && cur.addr < next.addr) break;

			(sortBytes[rank], sortBytes[rank - 1]) = (sortBytes[rank - 1], sortBytes[rank]);
			rank--;
		}

		info.minCommitteeMemberPos = uint8(sortBytes[info.committeeSize - 1]);
		return (info, sortBytes);
	}

	function getMinCommitteeMemberWeight() external view returns (uint96) {
		return committee[committeeInfo.minCommitteeMemberPos].weight;
	}

	function assignRewardsIfNeeded(Settings memory _settings) private {
        IRewards _rewardsContract = rewardsContract;
        uint lastAssignment = _rewardsContract.getLastRewardAssignmentTime();
        if (now - lastAssignment < _settings.maxTimeBetweenRewardAssignments) {
             return;
        }

		(address[] memory committeeAddrs, uint[] memory committeeWeights, bool[] memory committeeCertification) = _getCommittee();
        _rewardsContract.assignRewardsToCommittee(committeeAddrs, committeeWeights, committeeCertification);

		emit CommitteeSnapshot(committeeAddrs, committeeWeights, committeeCertification);
	}

	constructor(IContractRegistry _contractRegistry, address _registryAdmin, uint8 _maxCommitteeSize, uint32 maxTimeBetweenRewardAssignments) ManagedContract(_contractRegistry, _registryAdmin) public {
		setMaxCommitteeSize(_maxCommitteeSize);
		setMaxTimeBetweenRewardAssignments(maxTimeBetweenRewardAssignments);
	}

	/*
	 * Methods restricted to other Orbs contracts
	 */

	function memberChange(address addr, uint256 weight, bool isCertified) external override onlyElectionsContract onlyWhenActive returns (bool committeeChanged) {
		require(uint256(uint96(weight)) == weight, "weight is out of range");

		MemberData memory data = MemberData({
			status: membersStatus[addr],
			weight: uint96(weight),
			isCertified: isCertified
		});

		if (!data.status.isMember) {
			return false;
		}

		if (data.status.inCommittee) {
			committee[data.status.pos].weight = data.weight;
		}

		committeeChanged = updateOnMemberChange(addr, data);
		if (committeeChanged) {
			saveMemberStatus(addr, data.status);
		}
	}

	function addMember(address addr, uint256 weight, bool isCertified) external override onlyElectionsContract onlyWhenActive returns (bool committeeChanged) {
		require(uint256(uint96(weight)) == weight, "weight is out of range");

		if (membersStatus[addr].isMember) {
			return false;
		}

		MemberData memory data = MemberData({
			status: MemberStatus({
				isMember: true,
				inCommittee: false,
				pos: uint8(-1)
			}),
			weight: uint96(weight),
			isCertified: isCertified
		});
		committeeChanged = updateOnMemberChange(addr, data);
		saveMemberStatus(addr, data.status);
	}

	/// @dev Called by: Elections contract
	/// Notifies a a member removal for example due to voteOut / voteUnready
	function removeMember(address addr) external override onlyElectionsContract onlyWhenActive returns (bool committeeChanged) {
		MemberStatus memory status = membersStatus[addr];
		if (!status.isMember) {
			return false;
		}

		status.isMember = false;

		MemberData memory data = MemberData({
			status: status,
			weight: status.inCommittee ? committee[status.pos].weight : uint96(electionsContract.getEffectiveStake(addr)),
			isCertified: certificationContract.isGuardianCertified(addr)
		});
		committeeChanged = updateOnMemberChange(addr, data);

		saveMemberStatus(addr, status);
	}

	/// @dev Called by: Elections contract
	/// Returns the committee members and their weights
	function getCommittee() external override view returns (address[] memory addrs, uint256[] memory weights, bool[] memory certification) {
		return _getCommittee();
	}

	function _getCommittee() private view returns (address[] memory addrs, uint256[] memory weights, bool[] memory certification) {
		CommitteeInfo memory _committeeInfo = committeeInfo;
		uint bitmap = uint(_committeeInfo.committeeBitmap);
		uint committeeSize = _committeeInfo.committeeSize;

		addrs = new address[](committeeSize);
		weights = new uint[](committeeSize);
		uint aInd = 0;
		uint pInd = 0;
		CommitteeMember memory member;
		bitmap = uint(_committeeInfo.committeeBitmap);
		while (bitmap != 0) {
			if (bitmap & 1 == 1) {
				member = committee[pInd];
				addrs[aInd] = member.addr;
				weights[aInd] = member.weight;
				aInd++;
			}
			bitmap >>= 1;
			pInd++;
		}
		certification = certificationContract.getGuardiansCertification(addrs);
	}

	/*
	 * Governance
	 */

	function setMaxTimeBetweenRewardAssignments(uint32 maxTimeBetweenRewardAssignments) public override onlyFunctionalManager /* todo onlyWhenActive */ {
		emit MaxTimeBetweenRewardAssignmentsChanged(maxTimeBetweenRewardAssignments, settings.maxTimeBetweenRewardAssignments);
		settings.maxTimeBetweenRewardAssignments = maxTimeBetweenRewardAssignments;
	}

	function getMaxTimeBetweenRewardAssignments() external override view returns (uint32) {
		return settings.maxTimeBetweenRewardAssignments;
	}

	function setMaxCommitteeSize(uint8 maxCommitteeSize) public override onlyFunctionalManager /* todo onlyWhenActive */ {
		require(maxCommitteeSize > 0, "maxCommitteeSize must be larger than 0");
		require(maxCommitteeSize <= MAX_COMMITTEE_ARRAY_SIZE, "maxCommitteeSize must be 32 at most");
		Settings memory _settings = settings;
		emit MaxCommitteeSizeChanged(maxCommitteeSize, _settings.maxCommitteeSize);
		_settings.maxCommitteeSize = maxCommitteeSize;
		settings = _settings;

		CommitteeInfo memory info = committeeInfo;
		if (maxCommitteeSize >= info.committeeSize) {
			return;
		}

		bytes memory sortBytes = abi.encodePacked(committeeSortBytes);
		for (int rank = int(info.committeeSize); rank >= int(maxCommitteeSize); rank--) {
			(info, sortBytes) = removeMemberAtPos(uint8(sortBytes[uint(rank)]), sortBytes, info);
		}
		committeeInfo = info;
		committeeSortBytes = sortBytes.toBytes32(0);
	}

	function getMaxCommitteeSize() external override view returns (uint8) {
		return settings.maxCommitteeSize;
	}

	/*
     * Getters
     */

	/// @dev returns the current committee
	/// used also by the rewards and fees contracts
	function getCommitteeInfo() external override view returns (address[] memory addrs, uint256[] memory weights, address[] memory orbsAddrs, bool[] memory certification, bytes4[] memory ips) {
		(addrs, weights, certification) = _getCommittee();
		return (addrs, weights, _loadOrbsAddresses(addrs), certification, _loadIps(addrs));
	}

	function getSettings() external override view returns (uint32 maxTimeBetweenRewardAssignments, uint8 maxCommitteeSize) {
		Settings memory _settings = settings;
		maxTimeBetweenRewardAssignments = _settings.maxTimeBetweenRewardAssignments;
		maxCommitteeSize = _settings.maxCommitteeSize;
	}

	/*
	 * Private
	 */

	function _loadOrbsAddresses(address[] memory addrs) private view returns (address[] memory) {
		return guardianRegistrationContract.getGuardiansOrbsAddress(addrs);
	}

	function _loadIps(address[] memory addrs) private view returns (bytes4[] memory) {
		return guardianRegistrationContract.getGuardianIps(addrs);
	}

	IElections electionsContract;
	IRewards rewardsContract;
	IGuardiansRegistration guardianRegistrationContract;
	ICertification certificationContract;
	function refreshContracts() external override {
		electionsContract = IElections(getElectionsContract());
		rewardsContract = IRewards(getRewardsContract());
		guardianRegistrationContract = IGuardiansRegistration(getGuardiansRegistrationContract());
		certificationContract = ICertification(getCertificationContract());
	}

}
