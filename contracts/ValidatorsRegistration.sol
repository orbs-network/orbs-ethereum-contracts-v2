pragma solidity 0.5.16;

import "./spec_interfaces/IValidatorsRegistration.sol";
import "./interfaces/IElections.sol";
import "./ContractRegistryAccessor.sol";
import "./WithClaimableFunctionalOwnership.sol";

contract ValidatorsRegistration is IValidatorsRegistration, ContractRegistryAccessor, WithClaimableFunctionalOwnership, Lockable {

	modifier onlyRegisteredValidator {
		require(isRegistered(msg.sender), "Validator is not registered");

		_;
	}

	struct Validator {
		address orbsAddr;
		bytes4 ip;
		string name;
		string website;
		string contact;
		uint256 registrationTime;
		uint256 lastUpdateTime;

		mapping(string => string) validatorMetadata; // TODO do we want this mapping here or in an external state entry?  How do we delete on unregister?
	}
	mapping (address => Validator) validators;
	mapping (address => address) orbsAddressToEthereumAddress;
	mapping (bytes4 => address) ipToValidator;

	/*
     * External methods
     */

    /// @dev Called by a participant who wishes to register as a validator
	function registerValidator(bytes4 ip, address orbsAddr, string calldata name, string calldata website, string calldata contact) external onlyWhenActive {
		require(!isRegistered(msg.sender), "registerValidator: Validator is already registered");
		validators[msg.sender].registrationTime = now;
		_updateValidator(ip, orbsAddr, name, website, contact);

		emit ValidatorRegistered(msg.sender, ip, orbsAddr, name, website, contact);
		getElectionsContract().validatorRegistered(msg.sender);
	}

    /// @dev Called by a participant who wishes to update its propertires
	function updateValidator(bytes4 ip, address orbsAddr, string calldata name, string calldata website, string calldata contact) external onlyRegisteredValidator onlyWhenActive {
		_updateValidator(ip, orbsAddr, name, website, contact);
		emit ValidatorDataUpdated(msg.sender, ip, orbsAddr, name, website, contact);
	}

    /// @dev Called by a prticipant to update additional validator metadata properties.
    function setMetadata(string calldata key, string calldata value) external onlyRegisteredValidator onlyWhenActive {
		string memory oldValue = validators[msg.sender].validatorMetadata[key];
		validators[msg.sender].validatorMetadata[key] = value;
		emit ValidatorMetadataChanged(msg.sender, key, value, oldValue);
	}

	function getMetadata(address addr, string calldata key) external view returns (string memory) {
		require(isRegistered(addr), "getMetadata: Validator is not registered");
		return validators[addr].validatorMetadata[key];
	}

	/// @dev Called by a participant who wishes to unregister
	function unregisterValidator() external onlyRegisteredValidator onlyWhenActive {
		delete orbsAddressToEthereumAddress[validators[msg.sender].orbsAddr];
		delete ipToValidator[validators[msg.sender].ip];
		delete validators[msg.sender];

		getElectionsContract().validatorUnregistered(msg.sender);

		emit ValidatorUnregistered(msg.sender);
	}

    /// @dev Returns a validator's data
    /// Used also by the Election contract
	function getValidatorData(address addr) external view returns (bytes4 ip, address orbsAddr, string memory name, string memory website, string memory contact, uint registration_time, uint last_update_time) {
		require(isRegistered(addr), "getValidatorData: Validator is not registered");
		Validator memory v = validators[addr];
		return (v.ip, v.orbsAddr, v.name, v.website, v.contact, v.registrationTime, v.lastUpdateTime);
	}

	function getValidatorsOrbsAddress(address[] calldata addrs) external view returns (address[] memory orbsAddrs) {
		orbsAddrs = new address[](addrs.length);
		for (uint i = 0; i < addrs.length; i++) {
			orbsAddrs[i] = validators[addrs[i]].orbsAddr;
		}
	}

	function getValidatorOrbsAddress(address addr) external view returns (address orbsAddr) {
		require(isRegistered(addr), "getValidatorOrbsAddress: Validator is not registered");
		return validators[addr].orbsAddr;
	}

	function getValidatorIp(address addr) external view returns (bytes4 ip) {
		require(isRegistered(addr), "getValidatorIp: Validator is not registered");
		return validators[addr].ip;
	}

	function isRegistered(address addr) public view returns (bool) { // todo: should this be public?
		return validators[addr].registrationTime != 0;
	}

	/*
     * Methods restricted to other Orbs contracts
     */

    /// @dev Translates a list validators Ethereum addresses to Orbs addresses
    /// Used by the Election conract
	function getOrbsAddresses(address[] calldata ethereumAddrs) external view returns (address[] memory orbsAddrs) {
		orbsAddrs = new address[](ethereumAddrs.length);
		for (uint i = 0; i < ethereumAddrs.length; i++) {
			require(isRegistered(ethereumAddrs[i]), "getOrbsAddresses: Validator is not registered"); // todo: can be optimized, or maybe omit?
			orbsAddrs[i] = validators[ethereumAddrs[i]].orbsAddr;
		}
	}

	/// @dev Translates a list validators Orbs addresses to Ethereum addresses
	/// Used by the Election contract
	function getEthereumAddresses(address[] calldata orbsAddrs) external view returns (address[] memory ethereumAddrs) {
		ethereumAddrs = new address[](orbsAddrs.length);
		for (uint i = 0; i < orbsAddrs.length; i++) {
			ethereumAddrs[i] = orbsAddressToEthereumAddress[orbsAddrs[i]];
			require(ethereumAddrs[i] != address(0), "getEthereumAddresses: Validator is not registered"); // todo: omit?
		}
	}

	/*
	 * Private methods
	 */

	function _updateValidator(bytes4 ip, address orbsAddr, string memory name, string memory website, string memory contact) private {
		require(orbsAddr != address(0), "orbs address must be non zero");
		require(bytes(name).length != 0, "name must be given");
		require(bytes(contact).length != 0, "contact must be given");
		// TODO which are mandatory?

		delete ipToValidator[validators[msg.sender].ip];
		require(ipToValidator[ip] == address(0), "ip is already in use");
		ipToValidator[ip] = msg.sender;

		delete orbsAddressToEthereumAddress[validators[msg.sender].orbsAddr];
		require(orbsAddressToEthereumAddress[orbsAddr] == address(0), "orbs address is already in use");
		orbsAddressToEthereumAddress[orbsAddr] = msg.sender;

		validators[msg.sender].orbsAddr = orbsAddr;
		validators[msg.sender].ip = ip;
		validators[msg.sender].name = name;
		validators[msg.sender].website = website;
		validators[msg.sender].contact = contact;
		validators[msg.sender].lastUpdateTime = now;
	}

}
