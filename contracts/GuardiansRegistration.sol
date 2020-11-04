// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./spec_interfaces/IGuardiansRegistration.sol";
import "./spec_interfaces/IElections.sol";
import "./ManagedContract.sol";

contract GuardiansRegistration is IGuardiansRegistration, ManagedContract {

	struct Guardian {
		address orbsAddr;
		bytes4 ip;
		uint32 registrationTime;
		uint32 lastUpdateTime;
		string name;
		string website;
	}
	mapping(address => Guardian) guardians;
	mapping(address => address) orbsAddressToGuardianAddress;
	mapping(bytes4 => address) public ipToGuardian;
	mapping(address => mapping(string => string)) guardianMetadata;

    /// Constructor
    /// @param _contractRegistry is the contract registry address
    /// @param _registryAdmin is the registry admin address
	constructor(IContractRegistry _contractRegistry, address _registryAdmin) ManagedContract(_contractRegistry, _registryAdmin) public {}

	modifier onlyRegisteredGuardian {
		require(isRegistered(msg.sender), "Guardian is not registered");

		_;
	}

	/*
     * External methods
     */

    /// Registers a new guardian
    /// @dev called using the guardian's address that holds the guardian self-stake and used for delegation
    /// @param ip is the guardian's node ipv4 address as a 32b number 
    /// @param orbsAddr is the guardian's Orbs node address 
    /// @param name is the guardian's name as a string
    /// @param website is the guardian's website as a string, publishing a name and website provide information for delegators
	function registerGuardian(bytes4 ip, address orbsAddr, string calldata name, string calldata website) external override onlyWhenActive {
		require(!isRegistered(msg.sender), "registerGuardian: Guardian is already registered");

		guardians[msg.sender].registrationTime = uint32(block.timestamp);
		emit GuardianRegistered(msg.sender);

		_updateGuardian(msg.sender, ip, orbsAddr, name, website);
	}

    /// Updates a registered guardian data
    /// @dev may be called only by a registered guardian
    /// @param ip is the guardian's node ipv4 address as a 32b number 
    /// @param orbsAddr is the guardian's Orbs node address 
    /// @param name is the guardian's name as a string
    /// @param website is the guardian's website as a string, publishing a name and website provide information for delegators
	function updateGuardian(bytes4 ip, address orbsAddr, string calldata name, string calldata website) external override onlyRegisteredGuardian onlyWhenActive {
		_updateGuardian(msg.sender, ip, orbsAddr, name, website);
	}

    /// Updates a registered guardian ip address
    /// @dev may be called only by a registered guardian
    /// @dev may be called with either the guardian address or the guardian's orbs address
    /// @param ip is the guardian's node ipv4 address as a 32b number 
	function updateGuardianIp(bytes4 ip) external override onlyWhenActive {
		address guardianAddr = resolveGuardianAddress(msg.sender);
		Guardian memory data = guardians[guardianAddr];
		_updateGuardian(guardianAddr, ip, data.orbsAddr, data.name, data.website);
	}

    /// Updates a guardian's metadata property
    /// @dev called using the guardian's address
    /// @dev any key may be updated to be used by Orbs platform and tools
    /// @param key is the name of the property to update
    /// @param value is the value of the property to update in a string format
	function setMetadata(string calldata key, string calldata value) external override onlyRegisteredGuardian onlyWhenActive {
		_setMetadata(msg.sender, key, value);
	}

    /// Returns a guardian's metadata property
    /// @dev a property that wasn't set returns an empty string
    /// @param guardian is the guardian to query
    /// @param key is the name of the metadata property to query
    /// @return value is the value of the queried property in a string format
	function getMetadata(address guardian, string calldata key) external override view returns (string memory) {
		return guardianMetadata[guardian][key];
	}

    /// Unregisters a guardian
    /// @dev may be called only by a registered guardian
    /// @dev unregistering does not clear the guardian's metadata properties
	function unregisterGuardian() external override onlyRegisteredGuardian onlyWhenActive {
		delete orbsAddressToGuardianAddress[guardians[msg.sender].orbsAddr];
		delete ipToGuardian[guardians[msg.sender].ip];
		Guardian memory guardian = guardians[msg.sender];
		delete guardians[msg.sender];

		electionsContract.guardianUnregistered(msg.sender);
		emit GuardianDataUpdated(msg.sender, false, guardian.ip, guardian.orbsAddr, guardian.name, guardian.website, guardian.registrationTime);
		emit GuardianUnregistered(msg.sender);
	}

    /// Returns a guardian's data
    /// @param guardian is the guardian to query
    /// @param ip is the guardian's node ipv4 address as a 32b number 
    /// @param orbsAddr is the guardian's Orbs node address 
    /// @param name is the guardian's name as a string
    /// @param website is the guardian's website as a string
    /// @param registrationTime is the timestamp of the guardian's registration
    /// @param lastUpdateTime is the timestamp of the guardian's last update
	function getGuardianData(address guardian) external override view returns (bytes4 ip, address orbsAddr, string memory name, string memory website, uint registrationTime, uint lastUpdateTime) {
		Guardian memory v = guardians[guardian];
		return (v.ip, v.orbsAddr, v.name, v.website, v.registrationTime, v.lastUpdateTime);
	}

    /// Returns the Orbs addresses of a list of guardians
    /// @dev an unregistered guardian returns address(0) Orbs address
    /// @param guardianAddrs is a list of guardians' addresses to query
    /// @return orbsAddrs is a list of the guardians' Orbs addresses 
	function getGuardiansOrbsAddress(address[] calldata guardianAddrs) external override view returns (address[] memory orbsAddrs) {
		orbsAddrs = new address[](guardianAddrs.length);
		for (uint i = 0; i < guardianAddrs.length; i++) {
			orbsAddrs[i] = guardians[guardianAddrs[i]].orbsAddr;
		}
	}

    /// Returns a guardian's ip
    /// @dev an unregistered guardian returns 0 ip address
    /// @param guardian is the guardian to query
    /// @return ip is the guardian's node ipv4 address as a 32b number 
	function getGuardianIp(address guardian) external override view returns (bytes4 ip) {
		return guardians[guardian].ip;
	}

    /// Returns the ip of a list of guardians
    /// @dev an unregistered guardian returns 0 ip address
    /// @param guardianAddrs is a list of guardians' addresses to query
    /// @return ips is a list of the guardians' node ipv4 addresses as a 32b numbers
	function getGuardianIps(address[] calldata guardianAddrs) external override view returns (bytes4[] memory ips) {
		ips = new bytes4[](guardianAddrs.length);
		for (uint i = 0; i < guardianAddrs.length; i++) {
			ips[i] = guardians[guardianAddrs[i]].ip;
		}
	}

    /// Checks if a guardian is registered
    /// @param guardian is the guardian to query
    /// @return registered is a bool indicating a guardian address is registered
	function isRegistered(address guardian) public override view returns (bool) {
		return guardians[guardian].registrationTime != 0;
	}

    /// Translates a list guardians Orbs addresses to guardian addresses
    /// @dev an Orbs address that does not correspond to any registered guardian returns address(0)
    /// @param orbsAddrs is a list of the guardians' Orbs addresses to query
    /// @return guardianAddrs is a list of guardians' addresses that matches the Orbs addresses
	function getGuardianAddresses(address[] calldata orbsAddrs) external override view returns (address[] memory guardianAddrs) {
		guardianAddrs = new address[](orbsAddrs.length);
		for (uint i = 0; i < orbsAddrs.length; i++) {
			guardianAddrs[i] = orbsAddressToGuardianAddress[orbsAddrs[i]];
		}
	}

    /// Resolves the guardian address for a guardian, given a Guardian/Orbs address
    /// @dev revert if the address does not correspond to a registered guardian address or Orbs address
    /// @dev designed to be used for contracts calls, validating a registered guardian
    /// @dev should be used with caution when called by tools as the call may revert
    /// @dev in case of a conflict matching both guardian and Orbs address, the Guardian address takes precedence
    /// @param guardianOrOrbsAddress is the address to query representing a guardian address or Orbs address
    /// @return guardianAddress is the guardian address that matches the queried address
	function resolveGuardianAddress(address guardianOrOrbsAddress) public override view returns (address guardianAddress) {
		if (isRegistered(guardianOrOrbsAddress)) {
			guardianAddress = guardianOrOrbsAddress;
		} else {
			guardianAddress = orbsAddressToGuardianAddress[guardianOrOrbsAddress];
		}

		require(guardianAddress != address(0), "Cannot resolve address");
	}

	/*
	 * Governance
	 */

    /// Migrates a list of guardians from a previous guardians registration contract
    /// @dev governance function called only by the initialization admin
    /// @dev reads the migrated guardians data by calling getGuardianData in the previous contract
    /// @dev imports also the guardians' registration time and last update
    /// @dev emits a GuardianDataUpdated for each guardian to allow tracking by tools
    /// @param guardiansToMigrate is a list of guardians' addresses to migrate
    /// @param previousContract is the previous registration contract address
	function migrateGuardians(address[] calldata guardiansToMigrate, IGuardiansRegistration previousContract) external override onlyInitializationAdmin {
		require(previousContract != IGuardiansRegistration(0), "previousContract must not be the zero address");

		for (uint i = 0; i < guardiansToMigrate.length; i++) {
			require(guardiansToMigrate[i] != address(0), "guardian must not be the zero address");
			migrateGuardianData(previousContract, guardiansToMigrate[i]);
			migrateGuardianMetadata(previousContract, guardiansToMigrate[i]);
		}
	}

	/*
	 * Private methods
	 */

    /// Updates a registered guardian data
    /// @dev used by external functions that register a guardian or update its data
    /// @dev emits a GuardianDataUpdated event on any update to the registration  
    /// @param guardianAddr is the address of the guardian to update
    /// @param ip is the guardian's node ipv4 address as a 32b number 
    /// @param orbsAddr is the guardian's Orbs node address 
    /// @param name is the guardian's name as a string
    /// @param website is the guardian's website as a string, publishing a name and website provide information for delegators
	function _updateGuardian(address guardianAddr, bytes4 ip, address orbsAddr, string memory name, string memory website) private {
		require(orbsAddr != address(0), "orbs address must be non zero");
		require(orbsAddr != guardianAddr, "orbs address must be different than the guardian address");
		require(!isRegistered(orbsAddr), "orbs address must not be a guardian address of a registered guardian");
		require(bytes(name).length != 0, "name must be given");

		Guardian memory guardian = guardians[guardianAddr];

		delete ipToGuardian[guardian.ip];
		require(ipToGuardian[ip] == address(0), "ip is already in use");
		ipToGuardian[ip] = guardianAddr;

		delete orbsAddressToGuardianAddress[guardian.orbsAddr];
		require(orbsAddressToGuardianAddress[orbsAddr] == address(0), "orbs address is already in use");
		orbsAddressToGuardianAddress[orbsAddr] = guardianAddr;

		guardian.orbsAddr = orbsAddr;
		guardian.ip = ip;
		guardian.name = name;
		guardian.website = website;
		guardian.lastUpdateTime = uint32(block.timestamp);

		guardians[guardianAddr] = guardian;

        emit GuardianDataUpdated(guardianAddr, true, ip, orbsAddr, name, website, guardian.registrationTime);
    }

    /// Updates a guardian's metadata property
    /// @dev used by setMetadata and migration functions
    /// @dev any key may be updated to be used by Orbs platform and tools
    /// @param key is the name of the property to update
    /// @param value is the value of the property to update in a string format
	function _setMetadata(address guardian, string memory key, string memory value) private {
		string memory oldValue = guardianMetadata[guardian][key];
		guardianMetadata[guardian][key] = value;
		emit GuardianMetadataChanged(guardian, key, value, oldValue);
	}

    /// Migrates a guardian data from a previous guardians registration contract
    /// @dev used by migrateGuardians
    /// @dev reads the migrated guardians data by calling getGuardianData in the previous contract
    /// @dev imports also the guardians' registration time and last update
    /// @dev emits a GuardianDataUpdated
    /// @param previousContract is the previous registration contract address
    /// @param guardianAddress is the address of the guardians to migrate
	function migrateGuardianData(IGuardiansRegistration previousContract, address guardianAddress) private {
		(bytes4 ip, address orbsAddr, string memory name, string memory website, uint registrationTime, uint lastUpdateTime) = previousContract.getGuardianData(guardianAddress);
		guardians[guardianAddress] = Guardian({
			orbsAddr: orbsAddr,
			ip: ip,
			name: name,
			website: website,
			registrationTime: uint32(registrationTime),
			lastUpdateTime: uint32(lastUpdateTime)
		});
		orbsAddressToGuardianAddress[orbsAddr] = guardianAddress;
		ipToGuardian[ip] = guardianAddress;

		emit GuardianDataUpdated(guardianAddress, true, ip, orbsAddr, name, website, registrationTime);
	}

	string public constant ID_FORM_URL_METADATA_KEY = "ID_FORM_URL";

    /// Migrates a guardian metadata keys in use from a previous guardians registration contract
    /// @dev the metadata used by the contract are hard-coded in the function
    /// @dev used by migrateGuardians
    /// @dev reads the migrated guardians metadata by calling getMetadata in the previous contract
    /// @dev emits a GuardianMetadataChanged
    /// @param previousContract is the previous registration contract address
    /// @param guardianAddress is the address of the guardians to migrate	
	function migrateGuardianMetadata(IGuardiansRegistration previousContract, address guardianAddress) private {
		string memory rewardsFreqMetadata = previousContract.getMetadata(guardianAddress, ID_FORM_URL_METADATA_KEY);
		if (bytes(rewardsFreqMetadata).length > 0) {
			_setMetadata(guardianAddress, ID_FORM_URL_METADATA_KEY, rewardsFreqMetadata);
		}
	}

	/*
     * Contracts topology / registry interface
     */

	IElections electionsContract;

    /// Refreshes the address of the other contracts the contract interacts with
    /// @dev called by the registry contract upon an update of a contract in the registry
	function refreshContracts() external override {
		electionsContract = IElections(getElectionsContract());
	}

}
