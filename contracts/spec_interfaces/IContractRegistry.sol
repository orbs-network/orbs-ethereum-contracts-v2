pragma solidity 0.5.16;

interface IContractRegistry {

	event ContractAddressUpdated(string contractName, address addr, bool managedContract);

	/// @dev updates the contracts address and emits a corresponding event
	/// managedContract indicates whether the contract is managed by the registry and notified on changes
	function setContract(string calldata contractName, address addr, bool managedContract) external /* onlyFunctionalOwner */;
	
	/// @dev returns the current address of the given contracts
	function getContract(string calldata contractName) external view returns (address);

	/// @dev returns the list of contract addresses managed by the registry
	function getManagedContracts() external view returns (address[] memory);

}
