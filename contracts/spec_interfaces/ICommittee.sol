// SPDX-License-Identifier: MIT

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
    /// @dev Called only by: Elections contract
    /// @param addr is the committee member address
    /// @param weight is the updated weight of the committee member
	function memberWeightChange(address addr, uint256 weight) external /* onlyElectionsContract onlyWhenActive */;

    /// Notifies a change in the certification of a member
    /// @dev Called only by: Elections contract
    /// @param addr is the committee member address
    /// @param isCertified is the updated certification state of the member
	function memberCertificationChange(address addr, bool isCertified) external /* onlyElectionsContract onlyWhenActive */;

    /// Notifies a member removal for example due to voteOut or voteUnready
    /// @dev Called only by: Elections contract
    /// @param memberRemoved is the removed committee member address
    /// @return memberRemoved indicates whether the member was removed from the committee
    /// @return removedMemberWeight indicates the removed member weight
    /// @return removedMemberCertified indicates whether the member was in the certified committee
	function removeMember(address addr) external returns (bool memberRemoved, uint removedMemberWeight, bool removedMemberCertified)/* onlyElectionContract */;

    /// Notifies a new member applicable for committee (due to registration, unbanning, certification change)
    /// The new member will be added only if it is qualified to join the committee 
    /// @dev Called only by: Elections contract
    /// @param addr is the added committee member address
    /// @param weight is the added member weight
    /// @param isCertified is the added member certification state
    /// @return memberAdded bool indicates whether the member was addded
	function addMember(address addr, uint256 weight, bool isCertified) external returns (bool memberAdded)  /* onlyElectionsContract */;

    /// Checks if addMember() would add a the member to the committee (qualified to join)
    /// @param addr is the candidate committee member address
    /// @param weight is the candidate committee member weight
    /// @return wouldAddMember bool indicates whether the member will be addded
	function checkAddMember(address addr, uint256 weight) external view returns (bool wouldAddMember);

    /// Returns the committee members and their weights
    /// @return addrs is the committee members list
    /// @return weights is an array of uint, indicating committee members list weight
    /// @return certification is an array of bool, indicating the committee members certification status
	function getCommittee() external view returns (address[] memory addrs, uint256[] memory weights, bool[] memory certification);

    /// Returns the currently appointed committee data
    /// @return generalCommitteeSize is the number of members in the committee
    /// @return certifiedCommitteeSize is the number of certified members in the committee
    /// @return totalWeight is the total effective stake (weight) of the committee
	function getCommitteeStats() external view returns (uint generalCommitteeSize, uint certifiedCommitteeSize, uint totalWeight);

    /// Returns a committee member data
    /// @param addr is the committee member address
    /// @return inCommittee indicates whether the queried address is a member in the committee
    /// @return weight is the committee member weight
    /// @return isCertified indicates whether the committee member is certified
    /// @return totalCommitteeWeight is the total weight of the committee.
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
    /// @param _maxCommitteeSize is the maximum number of committee members 
	function setMaxCommitteeSize(uint8 _maxCommitteeSize) external /* onlyFunctionalManager */;

    /// Returns the maximum number of committee members
    /// @return maxCommitteeSize is the maximum number of committee members 
	function getMaxCommitteeSize() external view returns (uint8);
	
    /// Imports the committee members from a previous committee contract during migration
    /// @dev initialization function called only by the initializationManager
    /// @dev does not update the reward contract to avoid incorrect notifications 
    /// @param previousCommitteeContract is the address of the previous committee contract
	function importMembers(ICommittee previousCommitteeContract) external /* onlyInitializationAdmin */;
}
