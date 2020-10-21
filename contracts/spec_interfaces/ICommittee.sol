// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;

/// @title Committee contract interface
interface ICommittee {
	event CommitteeChange(address indexed addr, uint256 weight, bool certification, bool inCommittee);
	event CommitteeSnapshot(address[] addrs, uint256[] weights, bool[] certification);

	// No external functions

	/*
     * External functions
     */

	/// Notifies a weight change of a member
	/// @dev Called by: Elections contract
	/// @param addr - the committee member address
	/// @param weight - the updated weight of the committee member
	function memberWeightChange(address addr, uint256 weight) external /* onlyElectionsContract onlyWhenActive */;

	/// Notifies a change in the certification of a member
	/// @dev Called by: Elections contract
	/// @param addr - the committee member address
	/// @param isCertified - the updated certification state of the member
	function memberCertificationChange(address addr, bool isCertified) external /* onlyElectionsContract onlyWhenActive */;

	/// Notifies a member removal for example due to voteOut / voteUnready
	/// @dev Called by: Elections contract
	/// @param addr - the removed committee member address
	/// @return memberRemoved - indicates whether the member was removed from the committee
	/// @return removedMemberEffectiveStake - indicates the removed member eff
	function removeMember(address addr) external returns (bool memberRemoved, uint removedMemberEffectiveStake, bool removedMemberCertified)/* onlyElectionContract */;

	/// Notifies a new member applicable for committee (due to registration, unbanning, certification change)
	/// The new member will be added only if it is qualified to join the committee 
	/// @dev Called by: Elections contract
	/// @param addr - the added committee member address
	/// @return memberAdded bool - indicates wether the member was addded
	function addMember(address addr, uint256 weight, bool isCertified) external returns (bool memberAdded)  /* onlyElectionsContract */;

	/// Checks if addMember() would add a the member to the committee (qualified to join)
	/// @param addr - the candidate committee member address
	/// @param weight - the candidate committee member weight
	/// @return wouldAddMember bool - indicates wether the member will be addded
	function checkAddMember(address addr, uint256 weight) external view returns (bool wouldAddMember);

	/// Returns the committee members and their weights
	/// @return addrs - the committee members list
	/// @return weights - an array of uint, indicating committee members list weight
	/// @return certification - an array of bool, indicating the committee members certification status
	function getCommittee() external view returns (address[] memory addrs, uint256[] memory weights, bool[] memory certification);

	/// Returns data on the currently appointed committee
	/// @return generalCommitteeSize - the number of members in the committee
	/// @return certifiedCommitteeSize - the number of certified members in the committee
	/// @return totalWeight - the total effective stake / weight of the committee
	function getCommitteeStats() external view returns (uint generalCommitteeSize, uint certifiedCommitteeSize, uint totalWeight);

	/// Returns data on a committee member
	/// @param addr - the committee member address
	/// @return inCommittee - indicates wether the queried address is a member in the committee
	/// @return weight - the the committee member weight
	/// @return isCertified - indicates wether the committee member is certified
	/// @return totalCommitteeWeight - the total weight of the committee.
	function getMemberInfo(address addr) external view returns (bool inCommittee, uint weight, bool isCertified, uint totalCommitteeWeight);

	/// Emits a CommitteeSnapshot events with current committee info
	/// @dev a CommitteeSnapshot is useful on contracts migration or to remove the need to track past events.
	function emitCommitteeSnapshot() external;

	/*
	 * Governance functions
	 */

	event MaxCommitteeSizeChanged(uint8 newValue, uint8 oldValue);

	/// Sets the maximum number of committee members
	/// @dev governance function called only by the functional manager
	/// @dev when reducing the number of members, the bottom ones are removed from the committee
	/// @param maxCommitteeSize - the maximum number of committee members 
	function setMaxCommitteeSize(uint8 maxCommitteeSize) external /* onlyFunctionalManager onlyWhenActive */;

	/// Returns the maximum number of committee members
	/// @return maxCommitteeSize - the maximum number of committee members 
	function getMaxCommitteeSize() external view returns (uint8);
}
