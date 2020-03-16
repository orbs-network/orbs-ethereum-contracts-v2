pragma solidity 0.5.16;

import "./IContractRegistry.sol";

/// @title Elections contract interface
interface ICommittee {
    event CommitteeChanged(address[] addrs, address[] orbsAddrs, uint256[] weights);
	event AuditrosChanged(address[] addrs, address[] orbsAddrs, uint256[] weights);

    // No events
    // No external functions

	/*
     * Methods restricted to other Orbs contracts
     */

	/// @dev Called by: Elections contract
	/// Notifies a weight change for sorting to a relevant committee member.
    /// weight = 0 indicates removal of the member from the committee (for exmaple on unregister, voteUnready, voteOut)
	function memberWeightChange(address addr, uint256 weight, bool readyForCommittee) returns (bool commiteeChanged, bool auditsChanged); /* onlyElectionContract */;

	/// @dev Called by: Elections contract
	/// Notifies a weight change for sorting to a relevant committee member.
    /// weight = 0 indicates removal of the member from the committee (for exmaple on unregister, voteUnready, voteOut)
	function removeMember(address addr) returns (bool commiteeChanged, bool auditsChanged); /* onlyElectionContract */;

	/// @dev Called by: Elections contract
	/// Returns the committee members and audits
	function getWeight(uint N) external view returns (uint256 weight); 

	/// @dev Called by: Elections contract
	/// Returns the committee members and audits
	function getCommitee(uint N) external view returns (address[] memory committee, uint256[] memory audits); 

	/// @dev Called by: Elections contract
	/// Sets the mimimal weight, and committee members
    /// Every member with sortingStake >= mimimumStake OR in top minimumN is included in the committee
	function setMinimumWeight(uint256 mimimumWeight, uint minimumN); /* onlyElectionContract */;


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
	function getCommittee() external view returns (address[] memory addr, address[] memory orbsAddr, uint32[] ip);

    /// @dev returns the current auditors (out of commiteee) topology
	function getAuditors() external view returns (address[] memory addr, address[] memory orbsAddr, uint32[] ip);

}
