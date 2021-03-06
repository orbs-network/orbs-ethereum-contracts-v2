// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

/// @title Delegations contract interface
interface IDelegations /* is IStakeChangeNotifier */ {

    // Delegation state change events
	event DelegatedStakeChanged(address indexed addr, uint256 selfDelegatedStake, uint256 delegatedStake, address indexed delegator, uint256 delegatorContributedStake);

    // Function calls
	event Delegated(address indexed from, address indexed to);

	/*
     * External functions
     */

    /// Delegate your stake
    /// @dev updates the election contract on the changes in the delegated stake
    /// @dev updates the rewards contract on the upcoming change in the delegator's delegation state
    /// @param to is the address to delegate to
	function delegate(address to) external /* onlyWhenActive */;

    /// Refresh the address stake for delegation power based on the staking contract
    /// @dev Disabled stake change update notifications from the staking contract may create mismatches
    /// @dev refreshStake re-syncs the stake data with the staking contract
    /// @param addr is the address to refresh its stake
	function refreshStake(address addr) external /* onlyWhenActive */;

    /// Refresh the addresses stake for delegation power based on the staking contract
    /// @dev Batched version of refreshStake
    /// @dev Disabled stake change update notifications from the staking contract may create mismatches
    /// @dev refreshStakeBatch re-syncs the stake data with the staking contract
    /// @param addrs is the list of addresses to refresh their stake
	function refreshStakeBatch(address[] calldata addrs) external /* onlyWhenActive */;

    /// Returns the delegate address of the given address
    /// @param addr is the address to query
    /// @return delegation is the address the addr delegated to
	function getDelegation(address addr) external view returns (address);

    /// Returns a delegator info
    /// @param addr is the address to query
    /// @return delegation is the address the addr delegated to
    /// @return delegatorStake is the stake of the delegator as reflected in the delegation contract
	function getDelegationInfo(address addr) external view returns (address delegation, uint256 delegatorStake);
	
    /// Returns the delegated stake of an addr 
    /// @dev an address that is not self delegating has a 0 delegated stake
    /// @param addr is the address to query
    /// @return delegatedStake is the address delegated stake
	function getDelegatedStake(address addr) external view returns (uint256);

    /// Returns the total delegated stake
    /// @dev delegatedStake - the total stake delegated to an address that is self delegating
    /// @dev the delegated stake of a non self-delegated address is 0
    /// @return totalDelegatedStake is the total delegatedStake of all the addresses
	function getTotalDelegatedStake() external view returns (uint256) ;

	/*
	 * Governance functions
	 */

	event DelegationsImported(address[] from, address indexed to);

	event DelegationInitialized(address indexed from, address indexed to);

    /// Imports delegations during initial migration
    /// @dev initialization function called only by the initializationManager
    /// @dev Does not update the Rewards or Election contracts
    /// @dev assumes deactivated Rewards
    /// @param from is a list of delegator addresses
    /// @param to is the address the delegators delegate to
	function importDelegations(address[] calldata from, address to) external /* onlyMigrationManager onlyDuringDelegationImport */;

    /// Initializes the delegation of an address during initial migration 
    /// @dev initialization function called only by the initializationManager
    /// @dev behaves identically to a delegate transaction sent by the delegator
    /// @param from is the delegator addresses
    /// @param to is the delegator delegates to
	function initDelegation(address from, address to) external /* onlyInitializationAdmin */;
}
