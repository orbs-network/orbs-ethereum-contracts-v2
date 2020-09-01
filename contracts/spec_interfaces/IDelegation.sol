pragma solidity 0.5.16;

import "./IContractRegistry.sol";

/// @title Elections contract interface
interface IDelegations /* is IStakeChangeNotifier */ {

	event DelegatedStakeChanged(address indexed addr, uint256 selfDelegatedStake, uint256 delegatedStake, address[] delegators, uint256[] delegatorTotalStakes);
	event Delegated(address indexed from, address indexed to);

	/*
     * External methods
     */

	/// @dev Stake delegation
	function delegate(address to) external /* onlyWhenActive */;

	/// @dev updates the addr delegation and notifies the Election contract
	function refreshStakeNotification(address addr) external /* onlyWhenActive */;

	/// @dev refreshes the stake of addr from the Staking contract
	function refreshStake(address addr) external /* onlyWhenActive */;

	/*
	 * Getters
	 */

	/// @dev returns the delegated stake of an address
	function getDelegatedStakes(address addr) external view returns (uint256);

	/// @dev returns the self-delegated stake of an address
	/// self-delegated stake is the self stake if self-delegated, otherwise 0.
	function getSelfDelegatedStake(address addr) external view returns (uint256);
	
	/// @dev returns the current delegation of an address
	function getDelegation(address addr) external view returns (address);

	/// @dev returns the total delegated stake
	/// The total delegated stake is the total stake delegated to self-delegated addresses
	function getTotalDelegatedStake() external view returns (uint256) ;

	/*
	 * Migration and Initialization
	 */

	event DelegationsImported(address[] from, address[] to, bool notifiedElections);
	event DelegationImportFinalized();

	/// @dev admin function to be used during deployment of a new contract setting an initial delegation state. 
	function importDelegations(address[] calldata from, address[] calldata to, bool _refreshStakeNotification) external /* onlyMigrationManager */;
}
