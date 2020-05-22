pragma solidity 0.5.16;

import "./IContractRegistry.sol";

/// @title Elections contract interface
interface ICommittee {
    event CommitteeChanged(address[] addrs, address[] orbsAddrs, uint256[] weights, bool[] compliance);
	event StandbysChanged(address[] addrs, address[] orbsAddrs, uint256[] weights, bool[] compliance);

    // No events
    // No external functions

	/*
     * Methods restricted to other Orbs contracts
     */

	/// @dev Called by: Elections contract
	/// Notifies a weight change for sorting to a relevant committee member.
    /// weight = 0 indicates removal of the member from the committee (for exmaple on unregister, voteUnready, voteOut)
	function memberWeightChange(address addr, uint256 weight) external returns (bool commiteeChanged, bool standbysChanged) /* onlyElectionContract */;

	/// @dev Called by: Elections contract
	/// Notifies a validator sent a readyToSynx signal, with a flag indicating whether the validator is ready to join the committee
	function memberReadyToSync(address addr, bool readyForCommittee) external returns (bool commiteeChanged, bool standbysChanged) /* onlyElectionsContract */;

	/// @dev Called by: Elections contract
	/// Notifies a validator is no longer ready to sync
	function memberNotReadyToSync(address addr) external returns (bool commiteeChanged, bool standbysChanged) /* onlyElectionsContract */;

	/// @dev Called by: Elections contract
	/// Notifies a validator compliance change
	function memberComplianceChange(address addr, bool isCompliant) external returns (bool commiteeChanged, bool standbysChanged) /* onlyElectionsContract */;

	/// @dev Called by: Elections contract
	/// Notifies a a member removal for exampl	e due to voteOut / voteUnready
	function removeMember(address addr) external returns (bool commiteeChanged, bool standbysChanged) /* onlyElectionContract */;

	/// @dev Called by: Elections contract
	/// Notifies a new member applicable for committee (due to registration, unbanning, compliance change)
	function addMember(address addr, uint256 weight, bool isCompliant) external returns (bool committeeChanged, bool standbysChanged) /* onlyElectionsContract */;

	/// @dev Called by: Elections contract
	/// Returns the committee member with the lowest weight
	function getLowestCommitteeMember() external view returns (address addr);

	/// @dev Called by: Elections contract
	/// Returns the committee members and their weights
	function getCommittee() external view returns (address[] memory addrs, uint256[] memory weights);

	/// @dev Returns the standy (out of commiteee) members and their weights
	function getStandbys() external view returns (address[] memory addrs, uint256[] memory weights);

	/*
	 * Governance
	 */

    /// @dev Updates the address calldata of the contract registry
	function setContractRegistry(IContractRegistry _contractRegistry) external /* onlyOwner */;

    /*
     * Getters
     */

    /// @dev returns the current committee
    /// used also by the rewards and fees contracts
	function getCommitteeInfo() external view returns (address[] memory addrs, uint256[] memory weights, address[] memory orbsAddrs, bytes4[] memory ips);

    /// @dev returns the current standbys (out of commiteee) topology
	function getStandbysInfo() external view returns (address[] memory addrs, uint256[] memory weights, address[] memory orbsAddrs, bytes4[] memory ips);

}
