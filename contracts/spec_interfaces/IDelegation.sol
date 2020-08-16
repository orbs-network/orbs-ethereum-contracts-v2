pragma solidity 0.5.16;

import "./IContractRegistry.sol";

/// @title Elections contract interface
interface IDelegations /* is IStakeChangeNotifier */ {
    // Delegation state change events
	event DelegatedStakeChanged(address indexed addr, uint256 selfDelegatedStake, uint256 delegatedStake, address[] delegators, uint256[] delegatorTotalStakes);

    // Function calls
	event Delegated(address indexed from, address indexed to);

	/*
     * External methods
     */

	/// @dev Stake delegation
	function delegate(address to) external /* onlyWhenActive */;

	function refreshStakeNotification(address addr) external /* onlyWhenActive */;

	function refreshStake(address addr) external /* onlyWhenActive */;

	/*
	 * Governance
	 */

    /// @dev Updates the address calldata of the contract registry
	function setContractRegistry(IContractRegistry _contractRegistry) external /* onlyMigrationManager */;

	function importDelegations(address[] calldata from, address[] calldata to, bool _refreshStakeNotification) external /* onlyMigrationManager onlyDuringDelegationImport */;
	function finalizeDelegationImport() external /* onlyMigrationManager onlyDuringDelegationImport */;

	event DelegationsImported(address[] from, address[] to, bool notifiedElections);
	event DelegationImportFinalized();

	/*
	 * Getters
	 */

	function getDelegatedStakes(address addr) external view returns (uint256);
	function getSelfDelegatedStake(address addr) external view returns (uint256);
	function getDelegation(address addr) external view returns (address);
	function getTotalDelegatedStake() external view returns (uint256) ;


}
