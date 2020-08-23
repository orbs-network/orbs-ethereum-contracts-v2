pragma solidity 0.5.16;
import "./spec_interfaces/IContractRegistry.sol";
import "./IContractRegistryListener.sol";
import "./WithClaimableRegistryManagement.sol";

contract ContractRegistry is IContractRegistry, WithClaimableRegistryManagement {

	mapping (string => address) contracts;
	address[] managedContractAddresses;

	mapping (string => address) managers;

	function setContract(string calldata contractName, address addr, bool managedContract) external onlyRegistryManager {
		require(!managedContract || addr != address(0), "managed contract may not have address(0)");
		removeManagedContract(contracts[contractName]);
		contracts[contractName] = addr;
		if (managedContract) {
			addManagedContract(addr);
		}
		emit ContractAddressUpdated(contractName, addr, managedContract);
		notifyOnContractsChange();
	}

	function notifyOnContractsChange() private {
		for (uint i = 0; i < managedContractAddresses.length; i++) {
			IContractRegistryListener(managedContractAddresses[i]).refreshContracts();
		}
	}

	function notifyOnManagersChange(string memory role, address newManager) private {
		for (uint i = 0; i < managedContractAddresses.length; i++) {
			IContractRegistryListener(managedContractAddresses[i]).refreshManagers(role, newManager);
		}
	}

	function addManagedContract(address addr) private {
		managedContractAddresses[managedContractAddresses.length++] = addr;
	}

	function removeManagedContract(address addr) private {
		uint length = managedContractAddresses.length;
		for (uint i = 0; i < length; i++) {
			if (managedContractAddresses[i] == addr) {
				if (i != length - 1) {
					managedContractAddresses[i] = managedContractAddresses[length-1];
				}
				managedContractAddresses[length-1] = address(0);
				length--;
			}
		}
		managedContractAddresses.length = length;
	}

	function getContract(string calldata contractName) external view returns (address) {
		return contracts[contractName]; // TODO revert when contract doesn't exist?
	}

	function getManagedContracts() external view returns (address[] memory) {
		return managedContractAddresses;
	}

	function setManager(string calldata role, address manager) external onlyRegistryManager {
		managers[role] = manager;
		notifyOnManagersChange(role, manager);
		emit ManagerChanged(role, manager);
	}

	function getManager(string calldata role) external view returns (address) {
		return managers[role]; // todo - allow zero address?
	}

}
