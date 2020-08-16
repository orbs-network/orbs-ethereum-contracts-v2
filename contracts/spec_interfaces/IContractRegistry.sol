pragma solidity 0.5.16;

interface IContractRegistry {

	event ContractAddressUpdated(bytes32 contractId, address addr, bool isManaged);

	/// @dev updates the contracts address and emits a corresponding event
	function setContracts(bytes32[] calldata contractIds, address[] calldata addrs, bool[] calldata isManaged) external /* onlyFunctionalOwner */;

	/// @dev returns the current address of the given contracts
	function getContracts(bytes32[] calldata contractIds) external view returns (address[] memory);

}
