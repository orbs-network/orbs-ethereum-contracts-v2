pragma solidity 0.5.16;
import "./spec_interfaces/IContractRegistry.sol";
import "./WithClaimableMigrationOwnership.sol";
import "./WithClaimableFunctionalOwnership.sol";

contract ContractRegistry is IContractRegistry, WithClaimableMigrationOwnership, WithClaimableFunctionalOwnership {

	mapping (string => address) contracts;

	function set(string calldata contractName, address addr) external onlyFunctionalOwner {
		contracts[contractName] = addr;
		emit ContractAddressUpdated(contractName, addr);
	}

	function get(string calldata contractName) external view returns (address) {
		address addr = contracts[contractName];
		require(addr != address(0), "the contract name is not registered");
		return addr;
	}
}
