pragma solidity 0.5.16;

import "./IContractRegistry.sol";

/// @title Elections contract interface
interface IDelegations {
    // Delegation state change events
    event DelegatedStakeChanged(address addr, uint256 selfSstake, uint256 delegatedStake);

    // Function calls
	event Delegated(address from, address to, );

	/*
     * External methods
     */

	/// @dev Stake delegation
	function delegate(address to) external;
    
	/*
     * Methods restricted to other Orbs contracts
     */

	/// @dev Called by: delegation contract
	/// Notifies a stake change event
	function stakeChange(address addr, uint256 selfStake, uint256 delegatedStake); /* onlyDelegationContract */;

	/// @dev Called by: delegation contract
	/// Notifies a batch of stake updates
	function stakeChangeBatch(address[] calldata addr, uint256[] calldata selfStake, uint256[] calldata delegatedStake); /* onlyDelegationContract */;    

	/*
	 * Governance
	 */
	
    /// @dev Updates the address calldata of the contract registry
	function setContractRegistry(IContractRegistry _contractRegistry) external /* onlyOwner */;

	/*
	 * Getters
	 */

}
