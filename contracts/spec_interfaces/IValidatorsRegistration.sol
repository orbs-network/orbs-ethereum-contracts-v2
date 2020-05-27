pragma solidity 0.5.16;

import "./IContractRegistry.sol";

/// @title Elections contract interface
interface IValidatorsRegistration {
	event ValidatorRegistered(address addr, bytes4 ip, address orbsAddr, string name, string website, string contact);
	event ValidatorDataUpdated(address addr, bytes4 ip, address orbsAddr, string name, string website, string contact);
	event ValidatorUnregistered(address addr);
	event ValidatorMetadataChanged(address addr, string key, string newValue, string oldValue);

	/*
     * External methods
     */

    /// @dev Called by a participant who wishes to register as a validator
	function registerValidator(bytes4 ip, address orbsAddr, string calldata name, string calldata website, string calldata contact) external;

    /// @dev Called by a participant who wishes to update its propertires
	function updateValidator(bytes4 ip, address orbsAddr, string calldata name, string calldata website, string calldata contact) external;

    /// @dev Called by a participant to update additional validator metadata properties.
    function setMetadata(string calldata key, string calldata value) external;

    /// @dev Called by a participant to get additional validator metadata properties.
    function getMetadata(address addr, string calldata key) external view returns (string memory);

    /// @dev Called by a participant who wishes to unregister
	function unregisterValidator() external;

    /// @dev Returns a validator's data
    /// Used also by the Election contract
	function getValidatorData(address addr) external view returns (bytes4 ip, address orbsAddr, string memory name, string memory website, string memory contact, uint registration_time, uint last_update_time);


	// TODO added the following two getters for the elections contract which only needs ip and orbs address. Using getValidatorData caused "Unused Variables" warnings.

	/// @dev Returns a validator's orbs address
	/// Used also by the Election contract
	function getValidatorOrbsAddress(address addr) external view returns (address orbsAddr);

	function getValidatorsOrbsAddress(address[] calldata addrs) external view returns (address[] memory orbsAddrs);

	/// @dev Returns a validator's ip
	/// Used also by the Election contract
	function getValidatorIp(address addr) external view returns (bytes4 ip);


	/// @dev Returns true if the given address is of a registered validator
	/// Used also by the Election contract
	function isRegistered(address addr) external view returns (bool);

	/*
     * Methods restricted to other Orbs contracts
     */

    /// @dev Translates a list validators Ethereum addresses to Orbs addresses
    /// Used by the Election contract
	function getOrbsAddresses(address[] calldata ethereumAddrs) external view returns (address[] memory orbsAddr);


	/// @dev Translates a list validators Orbs addresses to Ethereum addresses
	/// Used by the Election contract
	function getEthereumAddresses(address[] calldata orbsAddrs) external view returns (address[] memory ethereumAddr);

}
