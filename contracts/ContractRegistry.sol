// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
import "./spec_interfaces/IContractRegistry.sol";
import "./spec_interfaces/ILockable.sol";
import "./spec_interfaces/IContractRegistryAccessor.sol";
import "./WithClaimableRegistryManagement.sol";
import "./Initializable.sol";

/// @title Contract registry
/// @dev The contract registry holds Orbs PoS contracts and managers lists
/// @dev The contract registry updates the managed contracts on changes in the contract list
/// @dev Governance functions restricted to managers access the registry to retrieve the manager address 
/// @dev The contract registry represents the source of truth for Orbs Ethereum contracts 
/// @dev By tracking the registry events or query before interaction, one can access the up to date contracts 
contract ContractRegistry is IContractRegistry, Initializable, WithClaimableRegistryManagement {

	address previousContractRegistry;
	mapping(string => address) contracts;
	address[] managedContractAddresses;
	mapping(string => address) managers;

    /// Constructor
    /// @param _previousContractRegistry is the previous contract registry address
    /// @param registryAdmin is the registry contract admin address
	constructor(address _previousContractRegistry, address registryAdmin) public {
		previousContractRegistry = _previousContractRegistry;
		_transferRegistryManagement(registryAdmin);
	}

	modifier onlyAdmin {
		require(msg.sender == registryAdmin() || msg.sender == initializationAdmin(), "sender is not an admin (registryAdmin or initializationAdmin when initialization in progress)");

		_;
	}

	modifier onlyAdminOrMigrationManager {
		require(msg.sender == registryAdmin() || msg.sender == initializationAdmin() || msg.sender == managers["migrationManager"], "sender is not an admin (registryAdmin or initializationAdmin when initialization in progress) and not the migration manager");

		_;
	}

	/*
	* External functions
	*/

	/// Updates the contracts address and emits a corresponding event
	/// @dev governance function called only by the migrationManager or registryAdmin
	/// @param contractName is the contract name, used to identify it
	/// @param addr is the contract updated address
	/// @param managedContract indicates whether the contract is managed by the registry and notified on changes
	function setContract(string calldata contractName, address addr, bool managedContract) external override onlyAdminOrMigrationManager {
		require(!managedContract || addr != address(0), "managed contract may not have address(0)");
		removeManagedContract(contracts[contractName]);
		contracts[contractName] = addr;
		if (managedContract) {
			addManagedContract(addr);
		}
		emit ContractAddressUpdated(contractName, addr, managedContract);
		notifyOnContractsChange();
	}

	/// Returns the current address of the given contracts
	/// @param contractName is the contract name, used to identify it
	/// @return addr is the contract updated address
	function getContract(string calldata contractName) external override view returns (address) {
		return contracts[contractName];
	}

	/// Returns the list of contract addresses managed by the registry
	/// @dev Managed contracts are updated on changes in the registry contracts addresses 
	/// @return addrs is the list of managed contracts
	function getManagedContracts() external override view returns (address[] memory) {
		return managedContractAddresses;
	}

	/// Locks all the managed contracts 
	/// @dev governance function called only by the migrationManager or registryAdmin
	/// @dev When set all onlyWhenActive functions will revert
	function lockContracts() external override onlyAdminOrMigrationManager {
		for (uint i = 0; i < managedContractAddresses.length; i++) {
			ILockable(managedContractAddresses[i]).lock();
		}
	}

	/// Unlocks all the managed contracts 
	/// @dev governance function called only by the migrationManager or registryAdmin
	function unlockContracts() external override onlyAdminOrMigrationManager {
		for (uint i = 0; i < managedContractAddresses.length; i++) {
			ILockable(managedContractAddresses[i]).unlock();
		}
	}

	/// Updates a manager address and emits a corresponding event
	/// @dev governance function called only by the registryAdmin
	/// @dev the managers list is a flexible list of role to the manager's address
	/// @param role is the managers' role name, for example "functionalManager"
	/// @param manager is the manager updated address
	function setManager(string calldata role, address manager) external override onlyAdmin {
		managers[role] = manager;
		emit ManagerChanged(role, manager);
	}

	/// Returns the current address of the given manager
	/// @param role is the manager name, used to identify it
	/// @return addr is the manager updated address
	function getManager(string calldata role) external override view returns (address) {
		return managers[role];
	}

	/// Sets a new contract registry to migrate to
	/// @dev governance function called only by the registryAdmin
	/// @dev updates the registry address record in all the managed contracts
	/// @dev by tracking the emitted ContractRegistryUpdated, tools can track the up to date contracts
	/// @param newRegistry is the new registry contract 
	function setNewContractRegistry(IContractRegistry newRegistry) external override onlyAdmin {
		for (uint i = 0; i < managedContractAddresses.length; i++) {
			IContractRegistryAccessor(managedContractAddresses[i]).setContractRegistry(newRegistry);
			IContractRegistryAccessor(managedContractAddresses[i]).refreshContracts();
		}
		emit ContractRegistryUpdated(address(newRegistry));
	}

	/// Returns the previous contract registry address 
	/// @dev used when the setting the contract as a new registry to assure a valid registry
	/// @return previousContractRegistry is the previous contract registry
	function getPreviousContractRegistry() external override view returns (address) {
		return previousContractRegistry;
	}

	/*
	* Private methods
	*/

	/// Notifies the managed contracts on a change in a contract address
	/// @dev invokes the refreshContracts() function in each contract that queries the relevant contract addresses
	function notifyOnContractsChange() private {
		for (uint i = 0; i < managedContractAddresses.length; i++) {
			IContractRegistryAccessor(managedContractAddresses[i]).refreshContracts();
		}
	}

	/// Adds a new managed contract address to the managed contracts list
	function addManagedContract(address addr) private {
		managedContractAddresses.push(addr);
	}

	/// Removes a managed contract address from the managed contracts list
	function removeManagedContract(address addr) private {
		uint length = managedContractAddresses.length;
		for (uint i = 0; i < length; i++) {
			if (managedContractAddresses[i] == addr) {
				if (i != length - 1) {
					managedContractAddresses[i] = managedContractAddresses[length-1];
				}
				managedContractAddresses.pop();
				length--;
			}
		}
	}

}
