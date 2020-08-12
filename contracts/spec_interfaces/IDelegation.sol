pragma solidity 0.5.16;

import "./IContractRegistry.sol";

/// @title Elections contract interface
interface IDelegations /* is IStakeChangeNotifier */ {
	/// @dev Notifies of stake change event.
	/// @param _stakeOwner address The address of the subject stake owner.
	/// @param _amount uint256 The difference in the total staked amount.
	/// @param _sign bool The sign of the added (true) or subtracted (false) amount.
	/// @param _updatedStake uint256 The updated total staked amount.
	function stakeChange(address _stakeOwner, uint256 _amount, bool _sign, uint256 _updatedStake) external;

	/// @dev Notifies of multiple stake change events.
	/// @param _stakeOwners address[] The addresses of subject stake owners.
	/// @param _amounts uint256[] The differences in total staked amounts.
	/// @param _signs bool[] The signs of the added (true) or subtracted (false) amounts.
	/// @param _updatedStakes uint256[] The updated total staked amounts.
	function stakeChangeBatch(address[] calldata _stakeOwners, uint256[] calldata _amounts, bool[] calldata _signs,
		uint256[] calldata _updatedStakes) external;

	/// @dev Notifies of stake migration event.
	/// @param _stakeOwner address The address of the subject stake owner.
	/// @param _amount uint256 The migrated amount.
	function stakeMigration(address _stakeOwner, uint256 _amount) external;

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
	function setContractRegistry(IContractRegistry _contractRegistry) external /* onlyMigrationOwner */;

	function importDelegations(address[] calldata from, address[] calldata to, bool _refreshStakeNotification) external /* onlyMigrationOwner onlyDuringDelegationImport */;
	function finalizeDelegationImport() external /* onlyMigrationOwner onlyDuringDelegationImport */;

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
