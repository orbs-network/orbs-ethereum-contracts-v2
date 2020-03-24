pragma solidity 0.5.16;

import "@openzeppelin/contracts/ownership/Ownable.sol";

import "./spec_interfaces/IContractRegistry.sol";
import "./spec_interfaces/IValidatorsRegistration.sol";

contract ValidatorsRegistration is IValidatorsRegistration, Ownable {

	modifier onlyRegisteredValidator {
		require(isRegistered(msg.sender), "Validator is not registered");

		_;
	}

	struct Validator {
		bytes4 ip; // TODO should we enforce uniqueness of IP address as we did in previous contract?
		address orbsAddr;
		string name;
		string website;
		string contact;
		uint256 registrationTime;
		uint256 lastUpdateTime;

		mapping(string => string) validatorMetadata;
	}
	mapping (address => Validator) validators;
	mapping (address => address) orbsAddressToEthereumAddress;

	IContractRegistry contractRegistry;

	/*
     * External methods
     */

    /// @dev Called by a participant who wishes to register as a validator
	function registerValidator(bytes4 ip, address orbsAddr, string calldata name, string calldata website, string calldata contact) external {
		require(!isRegistered(msg.sender), "Validator is already registered");
		validators[msg.sender].registrationTime = now;
		_updateValidator(ip, orbsAddr, name, website, contact);
		emit ValidatorRegistered(msg.sender, ip, orbsAddr, name, website, contact);
		// todo: notify elections contract?
	}

    /// @dev Called by a participant who wishes to update its propertires
	function updateValidator(bytes4 ip, address orbsAddr, string calldata name, string calldata website, string calldata contact) external onlyRegisteredValidator {
		_updateValidator(ip, orbsAddr, name, website, contact);
		emit ValidatorDataUpdated(msg.sender, ip, orbsAddr, name, website, contact);
		// todo: notify elections contract?
	}

    /// @dev Called by a prticipant to update additional validator metadata properties.
    function setMetadata(string calldata key, string calldata value) external onlyRegisteredValidator {
		string memory oldValue = validators[msg.sender].validatorMetadata[key];
		validators[msg.sender].validatorMetadata[key] = value;
		emit ValidatorMetadataChanged(msg.sender, key, value, oldValue);
	}

	function getMetadata(address addr, string calldata key) external view returns (string memory) {
		require(isRegistered(addr), "Validator is not registered");
		return validators[addr].validatorMetadata[key];
	}

	/// @dev Called by a participant who wishes to unregister
	function unregisterValidator() external onlyRegisteredValidator {
		orbsAddressToEthereumAddress[validators[msg.sender].orbsAddr] = address(0);
		delete validators[msg.sender];
		emit ValidatorUnregistered(msg.sender);
		// todo: notify elections contract?
	}

    /// @dev Returns a validator's data
    /// Used also by the Election contract
	function getValidatorData(address addr) external view returns (bytes4 ip, address orbsAddr, string memory name, string memory website, string memory contact, uint registration_time, uint last_update_time) {
		require(isRegistered(addr), "Validator is not registered");
		Validator memory v = validators[addr];
		return (v.ip, v.orbsAddr, v.name, v.website, v.contact, v.registrationTime, v.lastUpdateTime);
	}

	/*
     * Methods restricted to other Orbs contracts
     */

    /// @dev Translates a list validators Ethereum addresses to Orbs addresses
    /// Used by the Election conract
	function getOrbsAddresses(address[] calldata ethereumAddrs) external view returns (address[] memory orbsAddrs) {
		orbsAddrs = new address[](ethereumAddrs.length);
		for (uint i = 0; i < ethereumAddrs.length; i++) {
			require(isRegistered(ethereumAddrs[i]), "Validator is not registered"); // todo: can be optimized, or maybe omit?
			orbsAddrs[i] = validators[ethereumAddrs[i]].orbsAddr;
		}
	}

	/// @dev Translates a list validators Orbs addresses to Ethereum addresses
	/// Used by the Election contract
	function getEthereumAddresses(address[] calldata orbsAddrs) external view returns (address[] memory ethereumAddrs) {
		ethereumAddrs = new address[](orbsAddrs.length);
		for (uint i = 0; i < orbsAddrs.length; i++) {
			ethereumAddrs[i] = orbsAddressToEthereumAddress[orbsAddrs[i]];
			require(ethereumAddrs[i] != address(0), "Validator is not registered"); // todo: omit?
		}
	}

	/*
    * Governance
    */

	function setContractRegistry(IContractRegistry _contractRegistry) external onlyOwner {
		require(_contractRegistry != IContractRegistry(0), "contractRegistry must not be 0");
		contractRegistry = _contractRegistry;
	}

	/*
	 * Private methods
	 */

	function isRegistered(address addr) private view returns (bool) { // todo: should this be public?
			return validators[addr].registrationTime != 0;
	}

	function _updateValidator(bytes4 ip, address orbsAddr, string memory name, string memory website, string memory contact) private {
		require(orbsAddr != address(0), "orbs address must be non zero");
		require(bytes(name).length != 0, "name must be given");
		require(bytes(contact).length != 0, "contact must be given");
		// TODO which are mandatory?

		orbsAddressToEthereumAddress[validators[msg.sender].orbsAddr] = address(0);
        orbsAddressToEthereumAddress[orbsAddr] = msg.sender;

        validators[msg.sender].orbsAddr = orbsAddr;
		validators[msg.sender].ip = ip;
		validators[msg.sender].name = name;
		validators[msg.sender].website = website;
		validators[msg.sender].contact = contact;
		validators[msg.sender].lastUpdateTime = now;

		// todo: update committees
	}

}
