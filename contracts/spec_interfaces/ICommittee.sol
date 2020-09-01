pragma solidity 0.5.16;

import "./IContractRegistry.sol";

/// @title Elections contract interface
interface ICommittee {
	event GuardianCommitteeChange(address addr, uint256 weight, bool certification, bool inCommittee);
	event CommitteeSnapshot(address[] addrs, uint256[] weights, bool[] certification);

	// No external functions

	/*
     * Methods restricted to other Orbs contracts
     */

	/// @dev Called by: Elections contract
	/// Notifies a weight change for sorting to a relevant committee member.
    /// weight = 0 indicates removal of the member from the committee (for exmaple on unregister, voteUnready, voteOut)
	function memberWeightChange(address addr, uint256 weight) external returns (bool committeeChanged) /* onlyElectionContract */;

	/// @dev Called by: Elections contract
	/// Notifies a guardian certification change
	function memberCertificationChange(address addr, bool isCertified) external returns (bool committeeChanged) /* onlyElectionsContract */;

	/// @dev Called by: Elections contract
	/// Notifies a a member removal for exampl	e due to voteOut / voteUnready
	function removeMember(address addr) external returns (bool committeeChanged) /* onlyElectionContract */;

	/// @dev Called by: Elections contract
	/// Notifies a new member applicable for committee (due to registration, unbanning, certification change)
	function addMember(address addr, uint256 weight, bool isCertified) external returns (bool committeeChanged) /* onlyElectionsContract */;

	/// @dev Called by: Elections contract
	/// Returns the committee members and their weights
	function getCommittee() external view returns (address[] memory addrs, uint256[] memory weights, bool[] memory certification);

	/*
	 * Governance
	 */

	function setMaxTimeBetweenRewardAssignments(uint32 maxTimeBetweenRewardAssignments) external /* onlyFunctionalManager onlyWhenActive */;
	function setMaxCommitteeSize(uint8 maxCommitteeSize) external /* onlyFunctionalManager onlyWhenActive */;

	function getMaxTimeBetweenRewardAssignments() external view returns (uint32);
	function getMaxCommitteeSize() external view returns (uint8);

	event MaxTimeBetweenRewardAssignmentsChanged(uint32 newValue, uint32 oldValue);
	event MaxCommitteeSizeChanged(uint8 newValue, uint8 oldValue);

    /// @dev Updates the address calldata of the contract registry
	function setContractRegistry(IContractRegistry _contractRegistry) external /* onlyMigrationManager */;

    /*
     * Getters
     */

    /// @dev returns the current committee
    /// used also by the rewards and fees contracts
	function getCommitteeInfo() external view returns (address[] memory addrs, uint256[] memory weights, address[] memory orbsAddrs, bool[] memory certification, bytes4[] memory ips);

	/// @dev returns the current settings of the committee contract
	function getSettings() external view returns (uint32 maxTimeBetweenRewardAssignments, uint8 maxCommitteeSize);
}
