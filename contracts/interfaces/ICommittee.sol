pragma solidity 0.5.16;

import "./IContractRegistry.sol";

/// @title Elections contract interface
interface ICommittee {
    // No events
    // No external functions

	/*
     * Methods restricted to other Orbs contracts
     */

	/// @dev Called by: Elections contract
	/// Notifies a stake change for sorting to a relevant committee member.
    /// sotingStake = 0 indicates removal of the member from the committee
	function stakeChange(address addr, uint256 sotingStake); /* onlyDelegationContract */;

	/// @dev Called by: Elections contract
	/// Returns the N top committee members
	function getCommitee(uint N) external view returns (address[] memory); /* onlyDelegationContract */;

	/// @dev Called by: Elections contract
	/// Sets the mimimal stake, and committee members
    /// Every member with sortingStake >= mimimumStake OR in top minimumN is included in the committee
	function setMinimumStake(uint256 mimimumStake, minimumN); /* onlyDelegationContract */;


	/*
	 * Governance
	 */
	
    /// @dev Updates the address calldata of the contract registry
	function setContractRegistry(IContractRegistry _contractRegistry) external /* onlyOwner */;
    
}
