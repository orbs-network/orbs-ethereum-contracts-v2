pragma solidity 0.5.16;

interface IContractRegistry {

	event ContractAddressUpdated(bytes32 contractId, address addr, bool isManaged);
	event ManagerChanged(string role, address newManager);

	/// @dev updates the contracts address and emits a corresponding event
	function setContracts(bytes32[] calldata contractIds, address[] calldata addrs, bool[] calldata isManaged) external /* onlyFunctionalManager */;

	/// @dev returns the current address of the given contracts
	function getContracts(bytes32[] calldata contractIds) external view returns (address[] memory);

	function getContractIds() external view returns (bytes32[] memory);

	function setManager(string calldata role, address manager) external /* onlyFunctionalManager */;

	function getManager(string calldata role) external view returns (address);
}
