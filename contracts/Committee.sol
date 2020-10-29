// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./spec_interfaces/ICommittee.sol";
import "./ManagedContract.sol";
import "./spec_interfaces/IStakingRewards.sol";
import "./spec_interfaces/IFeesAndBootstrapRewards.sol";

/// @title Committee contract
contract Committee is ICommittee, ManagedContract {
	using SafeMath for uint256;
	using SafeMath for uint96;

	uint96 constant CERTIFICATION_MASK = 1 << 95;
	uint96 constant WEIGHT_MASK = ~CERTIFICATION_MASK;

	struct CommitteeMember {
		address addr;
		uint96 weightAndCertifiedBit;
	}
	CommitteeMember[] committee;

	struct MemberStatus {
		uint32 pos;
		bool inCommittee;
	}
	mapping(address => MemberStatus) public membersStatus;

	struct CommitteeStats {
		uint96 totalWeight;
		uint32 generalCommitteeSize;
		uint32 certifiedCommitteeSize;
	}
	CommitteeStats committeeStats;

	uint8 maxCommitteeSize;

    /// Constructor
    /// @param _contractRegistry is the contract registry address
    /// @param _registryAdmin is the registry admin address
	/// @param _maxCommitteeSize is the maximum number of committee members
	constructor(IContractRegistry _contractRegistry, address _registryAdmin, uint8 _maxCommitteeSize) ManagedContract(_contractRegistry, _registryAdmin) public {
		setMaxCommitteeSize(_maxCommitteeSize);
	}

	modifier onlyElectionsContract() {
		require(msg.sender == electionsContract, "caller is not the elections");

		_;
	}

	/*
	 * External functions
	 */

	/// Notifies a weight change of a member
	/// @dev Called only by: Elections contract
	/// @param addr is the committee member address
	/// @param weight is the updated weight of the committee member
	function memberWeightChange(address addr, uint256 weight) external override onlyElectionsContract onlyWhenActive {
		MemberStatus memory status = membersStatus[addr];

		if (!status.inCommittee) {
			return;
		}
		CommitteeMember memory member = committee[status.pos];
		(uint prevWeight, bool isCertified) = getWeightCertification(member);

		committeeStats.totalWeight = uint96(committeeStats.totalWeight.sub(prevWeight).add(weight));

		committee[status.pos].weightAndCertifiedBit = packWeightCertification(weight, isCertified);
		emit CommitteeChange(addr, weight, isCertified, true);
	}

	/// Notifies a change in the certification of a member
	/// @dev Called only by: Elections contract
	/// @param addr is the committee member address
	/// @param isCertified is the updated certification state of the member
	function memberCertificationChange(address addr, bool isCertified) external override onlyElectionsContract onlyWhenActive {
		MemberStatus memory status = membersStatus[addr];

		if (!status.inCommittee) {
			return;
		}
		CommitteeMember memory member = committee[status.pos];
		(uint weight, bool prevCertification) = getWeightCertification(member);

		CommitteeStats memory _committeeStats = committeeStats;

		feesAndBootstrapRewardsContract.committeeMembershipWillChange(addr, true, prevCertification, isCertified, _committeeStats.generalCommitteeSize, _committeeStats.certifiedCommitteeSize);

		committeeStats.certifiedCommitteeSize = _committeeStats.certifiedCommitteeSize - (prevCertification ? 1 : 0) + (isCertified ? 1 : 0);

		committee[status.pos].weightAndCertifiedBit = packWeightCertification(weight, isCertified);
		emit CommitteeChange(addr, weight, isCertified, true);
	}

	/// Notifies a member removal for example due to voteOut / voteUnready
	/// @dev Called only by: Elections contract
	/// @param memberRemoved is the removed committee member address
	/// @return memberRemoved indicates whether the member was removed from the committee
	/// @return removedMemberWeight indicates the removed member weight
	/// @return removedMemberCertified indicates whether the member was in the certified committee
	function removeMember(address addr) external override onlyElectionsContract onlyWhenActive returns (bool memberRemoved, uint removedMemberWeight, bool removedMemberCertified) {
		MemberStatus memory status = membersStatus[addr];
		if (!status.inCommittee) {
			return (false, 0, false);
		}

		memberRemoved = true;
		(removedMemberWeight, removedMemberCertified) = getWeightCertification(committee[status.pos]);

		committeeStats = removeMemberAtPos(status.pos, true, committeeStats);
	}

	/// Notifies a new member applicable for committee (due to registration, unbanning, certification change)
	/// The new member will be added only if it is qualified to join the committee 
	/// @dev Called only by: Elections contract
	/// @param addr is the added committee member address
	/// @param weight is the added member weight
	/// @param isCertified is the added member certification state
	/// @return memberAdded bool indicates whether the member was addded
	function addMember(address addr, uint256 weight, bool isCertified) external override onlyElectionsContract onlyWhenActive returns (bool memberAdded) {
		return _addMember(addr, weight, isCertified, true);
	}

	/// Checks if addMember() would add a the member to the committee (qualified to join)
	/// @param addr is the candidate committee member address
	/// @param weight is the candidate committee member weight
	/// @return wouldAddMember bool indicates whether the member will be addded
	function checkAddMember(address addr, uint256 weight) external view override returns (bool wouldAddMember) {
		if (membersStatus[addr].inCommittee) {
			return false;
		}

		(bool qualified, ) = qualifiesToEnterCommittee(addr, weight, maxCommitteeSize);
		return qualified;
	}

	/// Returns the committee members and their weights
	/// @return addrs is the committee members list
	/// @return weights is an array of uint, indicating committee members list weight
	/// @return certification is an array of bool, indicating the committee members certification status
	function getCommittee() external override view returns (address[] memory addrs, uint256[] memory weights, bool[] memory certification) {
		return _getCommittee();
	}

	/// Returns the currently appointed committee data
	/// @return generalCommitteeSize is the number of members in the committee
	/// @return certifiedCommitteeSize is the number of certified members in the committee
	/// @return totalWeight is the total effective stake / weight of the committee
	function getCommitteeStats() external override view returns (uint generalCommitteeSize, uint certifiedCommitteeSize, uint totalWeight) {
		CommitteeStats memory _committeeStats = committeeStats;
		return (_committeeStats.generalCommitteeSize, _committeeStats.certifiedCommitteeSize, _committeeStats.totalWeight);
	}

	/// Returns a committee member data
	/// @param addr is the committee member address
	/// @return inCommittee indicates whether the queried address is a member in the committee
	/// @return weight is the committee member weight
	/// @return isCertified indicates whether the committee member is certified
	/// @return totalCommitteeWeight is the total weight of the committee.
	function getMemberInfo(address addr) external override view returns (bool inCommittee, uint weight, bool isCertified, uint totalCommitteeWeight) {
		MemberStatus memory status = membersStatus[addr];
		inCommittee = status.inCommittee;
		if (inCommittee) {
			(weight, isCertified) = getWeightCertification(committee[status.pos]);
		}
		totalCommitteeWeight = committeeStats.totalWeight;
	}
	
	/// Emits a CommitteeSnapshot events with current committee info
	/// @dev a CommitteeSnapshot is useful on contracts migration or to remove the need to track past events.
	function emitCommitteeSnapshot() external override {
		(address[] memory addrs, uint256[] memory weights, bool[] memory certification) = _getCommittee();
		for (uint i = 0; i < addrs.length; i++) {
			emit CommitteeChange(addrs[i], weights[i], certification[i], true);
		}
		emit CommitteeSnapshot(addrs, weights, certification);
	}


	/*
	 * Governance functions
	 */

	/// Sets the maximum number of committee members
	/// @dev governance function called only by the functional manager
	/// @dev when reducing the number of members, the bottom ones are removed from the committee
	/// @param _maxCommitteeSize is the maximum number of committee members 
	function setMaxCommitteeSize(uint8 _maxCommitteeSize) public override onlyFunctionalManager {
		uint8 prevMaxCommitteeSize = maxCommitteeSize;
		maxCommitteeSize = _maxCommitteeSize;

		while (committee.length > _maxCommitteeSize) {
			(, ,uint pos) = _getMinCommitteeMember();
			committeeStats = removeMemberAtPos(pos, true, committeeStats);
		}

		emit MaxCommitteeSizeChanged(_maxCommitteeSize, prevMaxCommitteeSize);
	}

	/// Returns the maximum number of committee members
	/// @return maxCommitteeSize is the maximum number of committee members 
	function getMaxCommitteeSize() external override view returns (uint8) {
		return maxCommitteeSize;
	}

	/// Imports the committee members from a previous committee contract during migration
	/// @dev initialization function called only by the initializationManager
	/// @dev does not update the reward contract to avoid incorrect notifications 
	/// @param previousCommitteeContract is the address of the previous committee contract
	function importMembers(ICommittee previousCommitteeContract) external override onlyInitializationAdmin {
		(address[] memory addrs, uint256[] memory weights, bool[] memory certification) = previousCommitteeContract.getCommittee();
		for (uint i = 0; i < addrs.length; i++) {
			_addMember(addrs[i], weights[i], certification[i], false);
		}
	}

	/*
	 * Private
	 */

	/// Checks a member eligibility to join the committee and add if eligible
	/// @dev Private function called by AddMember and importMembers
	/// @dev checks if the maximum committee size has reached, removes the lowest weight member if needed
	/// @param addr is the added committee member address
	/// @param weight is the added member weight
	/// @param isCertified is the added member certification state
	/// @param notifyRewards indicates whether to notify the rewards contract on the update, false on members import during migration
	function _addMember(address addr, uint256 weight, bool isCertified, bool notifyRewards) private returns (bool memberAdded) {
		MemberStatus memory status = membersStatus[addr];

		if (status.inCommittee) {
			return false;
		}

		(bool qualified, uint entryPos) = qualifiesToEnterCommittee(addr, weight, maxCommitteeSize);
		if (!qualified) {
			return false;
		}

		memberAdded = true;

		CommitteeStats memory _committeeStats = committeeStats;

		if (notifyRewards) {
			stakingRewardsContract.committeeMembershipWillChange(addr, weight, _committeeStats.totalWeight, false, true);
			feesAndBootstrapRewardsContract.committeeMembershipWillChange(addr, false, isCertified, isCertified, _committeeStats.generalCommitteeSize, _committeeStats.certifiedCommitteeSize);
		}

		_committeeStats.generalCommitteeSize++;
		if (isCertified) _committeeStats.certifiedCommitteeSize++;
		_committeeStats.totalWeight = uint96(_committeeStats.totalWeight.add(weight));

		CommitteeMember memory newMember = CommitteeMember({
			addr: addr,
			weightAndCertifiedBit: packWeightCertification(weight, isCertified)
			});

		if (entryPos < committee.length) {
			CommitteeMember memory removed = committee[entryPos];
			unpackWeightCertification(removed.weightAndCertifiedBit);

			_committeeStats = removeMemberAtPos(entryPos, false, _committeeStats);
			committee[entryPos] = newMember;
		} else {
			committee.push(newMember);
		}

		status.inCommittee = true;
		status.pos = uint32(entryPos);
		membersStatus[addr] = status;

		committeeStats = _committeeStats;

		emit CommitteeChange(addr, weight, isCertified, true);
	}

	/// Pack a member's weight and certification to a compact uint96 representation
	function packWeightCertification(uint256 weight, bool certification) private pure returns (uint96 weightAndCertified) {
		return uint96(weight) | (certification ? CERTIFICATION_MASK : 0);
	}

	/// Unpacks a compact uint96 representation to a member's weight and certification
	function unpackWeightCertification(uint96 weightAndCertifiedBit) private pure returns (uint256 weight, bool certification) {
		return (uint256(weightAndCertifiedBit & WEIGHT_MASK), weightAndCertifiedBit & CERTIFICATION_MASK != 0);
	}

	/// Returns the weight and certification of a CommitteeMember entry
	function getWeightCertification(CommitteeMember memory member) private pure returns (uint256 weight, bool certification) {
		return unpackWeightCertification(member.weightAndCertifiedBit);
	}

	/// Returns the committee members and their weights
	/// @dev Private function called by getCommittee and emitCommitteeSnapshot
	/// @return addrs is the committee members list
	/// @return weights is an array of uint, indicating committee members list weight
	/// @return certification is an array of bool, indicating the committee members certification status
	function _getCommittee() private view returns (address[] memory addrs, uint256[] memory weights, bool[] memory certification) {
		CommitteeMember[] memory _committee = committee;
		addrs = new address[](_committee.length);
		weights = new uint[](_committee.length);
		certification = new bool[](_committee.length);

		for (uint i = 0; i < _committee.length; i++) {
			addrs[i] = _committee[i].addr;
			(weights[i], certification[i]) = getWeightCertification(_committee[i]);
		}
	}

	/// Returns the committee member with the minimum weight as a candidate to be removed from the committee 
	/// @dev Private function called by qualifiesToEnterCommittee and setMaxCommitteeSize
	/// @return minMemberAddress is the address of the committee member with the minimum weight
	/// @return minMemberWeight is the weight of the committee member with the minimum weight
	/// @return minMemberPos is the committee array pos of the committee member with the minimum weight
	function _getMinCommitteeMember() private view returns (
		address minMemberAddress,
		uint256 minMemberWeight,
		uint minMemberPos
	){
		CommitteeMember[] memory _committee = committee;
		minMemberPos = uint256(-1);
		minMemberWeight = uint256(-1);
		uint256 memberWeight;
		address memberAddress;
		for (uint i = 0; i < _committee.length; i++) {
			memberAddress = _committee[i].addr;
			(memberWeight,) = getWeightCertification(_committee[i]);
			if (memberWeight < minMemberWeight || memberWeight == minMemberWeight && memberAddress < minMemberAddress) {
				minMemberPos = i;
				minMemberWeight = memberWeight;
				minMemberAddress = memberAddress;
			}
		}
	}


	/// Checks if a potential candidate is qualified to join the committee
	/// @dev Private function called by checkAddMember and _addMember
	/// @param addr is the candidate committee member address
	/// @param weight is the candidate committee member weight
	/// @param _maxCommitteeSize is the maximum number of committee members
	/// @return qualified indicates whether the candidate committee member qualifies to join
	/// @return entryPos is the committee array pos allocated to the member (empty or the position of the minimum weight member)
	function qualifiesToEnterCommittee(address addr, uint256 weight, uint8 _maxCommitteeSize) private view returns (bool qualified, uint entryPos) {
		uint committeeLength = committee.length;
		if (committeeLength < _maxCommitteeSize) {
			return (true, committeeLength);
		}

		(address minMemberAddress, uint256 minMemberWeight, uint minMemberPos) = _getMinCommitteeMember();

		if (weight > minMemberWeight || weight == minMemberWeight && addr > minMemberAddress) {
			return (true, minMemberPos);
		}

		return (false, 0);
	}

	/// Removes a member at a certain pos in the committee array 
	/// @dev Private function called by _addMember, removeMember and setMaxCommitteeSize
	/// @param pos is the committee array pos to be removed
	/// @param clearFromList indicates whether to clear the entry in the committee array, false when overriding it with a new member
	/// @param _committeeStats is the current committee statistics
	/// @return newCommitteeStats is the updated committee committee statistics after the removal
	function removeMemberAtPos(uint pos, bool clearFromList, CommitteeStats memory _committeeStats) private returns (CommitteeStats memory newCommitteeStats){
		CommitteeMember memory member = committee[pos];

		(uint weight, bool certification) = getWeightCertification(member);

		stakingRewardsContract.committeeMembershipWillChange(member.addr, weight, _committeeStats.totalWeight, true, false);
		feesAndBootstrapRewardsContract.committeeMembershipWillChange(member.addr, true, certification, certification, _committeeStats.generalCommitteeSize, _committeeStats.certifiedCommitteeSize);

		delete membersStatus[member.addr];

		_committeeStats.generalCommitteeSize--;
		if (certification) _committeeStats.certifiedCommitteeSize--;
		_committeeStats.totalWeight = uint96(_committeeStats.totalWeight.sub(weight));

		emit CommitteeChange(member.addr, weight, certification, false);

		if (clearFromList) {
			uint committeeLength = committee.length;
			if (pos < committeeLength - 1) {
				CommitteeMember memory last = committee[committeeLength - 1];
				committee[pos] = last;
				membersStatus[last.addr].pos = uint32(pos);
			}
			committee.pop();
		}

		return _committeeStats;
	}

	/*
     * Contracts topology / registry interface
     */

	address electionsContract;
	IStakingRewards stakingRewardsContract;
	IFeesAndBootstrapRewards feesAndBootstrapRewardsContract;

	/// Refreshes the address of the other contracts the contract interacts with
    /// @dev called by the registry contract upon an update of a contract in the registry
	function refreshContracts() external override {
		electionsContract = getElectionsContract();
		stakingRewardsContract = IStakingRewards(getStakingRewardsContract());
		feesAndBootstrapRewardsContract = IFeesAndBootstrapRewards(getFeesAndBootstrapRewardsContract());
	}
}
