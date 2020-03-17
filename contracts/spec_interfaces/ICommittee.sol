pragma solidity 0.5.16;

import "./IContractRegistry.sol";

/// @title Elections contract interface
interface ICommittee {
    event CommitteeChanged(address[] addrs, address[] orbsAddrs, uint256[] weights);
	event StandbysChanged(address[] addrs, address[] orbsAddrs, uint256[] weights);

    // No events
    // No external functions

	/*
     * Methods restricted to other Orbs contracts
     */

	/// @dev Called by: Elections contract
	/// Notifies a weight change for sorting to a relevant committee member.
    /// weight = 0 indicates removal of the member from the committee (for exmaple on unregister, voteUnready, voteOut)
	function memberWeightChange(address addr, uint256 weight, bool readyForCommittee) external returns (bool commiteeChanged, bool standbysChanged) /* onlyElectionContract */;

	/// @dev Called by: Elections contract
	/// Notifies a a member removal for example due to voteOut / voteUnready
	function removeMember(address addr) external returns (bool commiteeChanged, bool standbysChanged) /* onlyElectionContract */;

	/// @dev Called by: Elections contract
	/// Returns the weight of
	function getWeight(uint N) external view returns (uint256 weight);

	/// @dev Called by: Elections contract
	/// Returns the committee members and their weights
	function getCommitee(uint N) external view returns (address[] memory addrs, uint256[] memory weights);

	/// @dev Returns the standy (out of commiteee) members and their weights
	function getStandbys(uint N) external view returns (address[] memory addrs, uint256[] memory weights);

	/// @dev Called by: Elections contract
	/// Sets the mimimal weight, and committee members
    /// Every member with sortingStake >= mimimumStake OR in top minimumN is included in the committee
	function setMinimumWeight(uint256 mimimumWeight, uint minimumN) external /* onlyElectionContract */;

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
	function getCommitteeInfo() external view returns (address[] memory addrs, uint256[] memory weights, address[] memory orbsAddrs, uint32[] memory ips);

    /// @dev returns the current standbys (out of commiteee) topology
	function getStandbysInfo() external view returns (address[] memory addrs, uint256[] memory weights, address[] memory orbsAddrs, uint32[] memory ips);

}
