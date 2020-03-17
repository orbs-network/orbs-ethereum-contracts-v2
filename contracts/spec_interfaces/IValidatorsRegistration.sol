pragma solidity 0.5.16;

import "./IContractRegistry.sol";

/// @title Elections contract interface
interface IValidatorsRegistration {
	event ValidatorRegistered(address addr, bytes4 ip, address orbsAddr, string name, string website, string contact);
	event ValidatorDataUpdated(address addr, bytes4 ip, address orbsAddr, string name, string website, string contact);
	event ValidatorUnregistered(address addr);

	/*
     * External methods
     */

    /// @dev Called by a participant who wishes to register as a validator
	function registerValidator(bytes4 ip, address orbsAddr, string calldata name, string calldata website, string calldata contact) external;

    /// @dev Called by a participant who wishes to update its propertires
	function updateValidator(bytes4 ip, address orbsAddr, string calldata name, string calldata website, string calldata contact) external;

    /// @dev Called by a prticipant to update additional validator metadata properties.
    function setMetadata(string calldata key, string calldata value) external;

    /// @dev Called by a participant who wishes to unregister
	function unregisterValidator() external;

    /// @dev Returns a validator's data
    /// Used also by the Election conract
	function getValidatorData(address addr) external returns (bytes4 ip, address orbsAddr, string memory name, string memory website, string memory contact, uint registration_time, uint last_update_time);


	/*
     * Methods restricted to other Orbs contracts
     */

    /// @dev Translates a list validators Ethereum addresses to Orbs addresses
    /// Used by the Election conract
	function getOrbsAddresses(address[] calldata addr) external returns (address[] memory orbsAddr);

}
