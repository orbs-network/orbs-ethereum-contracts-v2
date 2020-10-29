// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

/// @title Guardian registration contract interface
interface IGuardiansRegistration {
	event GuardianRegistered(address indexed guardian);
	event GuardianUnregistered(address indexed guardian);
	event GuardianDataUpdated(address indexed guardian, bool isRegistered, bytes4 ip, address orbsAddr, string name, string website);
	event GuardianMetadataChanged(address indexed guardian, string key, string newValue, string oldValue);

	/*
     * External methods
     */

    /// Registers a new guardian
	/// @dev called using the guardian's address that holds the guardian self-stake and used for delegation
	/// @param ip is the guardian's node ipv4 address as a 32b number 
	/// @param orbsAddr is the guardian's Orbs node address 
	/// @param name is the guardian's name as a string
	/// @param website is the guardian's website as a string, publishing a name and website provide information for delegators
	function registerGuardian(bytes4 ip, address orbsAddr, string calldata name, string calldata website) external;

    /// Updates a registered guardian data
	/// @dev may be called only by a registered guardian
	/// @param ip is the guardian's node ipv4 address as a 32b number 
	/// @param orbsAddr is the guardian's Orbs node address 
	/// @param name is the guardian's name as a string
	/// @param website is the guardian's website as a string, publishing a name and website provide information for delegators
	function updateGuardian(bytes4 ip, address orbsAddr, string calldata name, string calldata website) external;

	/// Updates a registered guardian ip address
	/// @dev may be called only by a registered guardian
	/// @dev may be called with either the guardian address or the guardian's orbs address
	/// @param ip is the guardian's node ipv4 address as a 32b number 
	function updateGuardianIp(bytes4 ip) external /* onlyWhenActive */;

    /// Updates a guardian's metadata property
	/// @dev called using the guardian's address
	/// @dev any key may be updated to be used by Orbs platform and tools
	/// @param key is the name of the property to update
	/// @param value is the value of the property to update in a string format
    function setMetadata(string calldata key, string calldata value) external;

    /// Returns a guardian's metadata property
	/// @dev a property that wasn't set returns an empty string
	/// @param guardian is the guardian to query
	/// @param key is the name of the metadata property to query
	/// @return value is the value of the queried property in a string format
    function getMetadata(address guardian, string calldata key) external view returns (string memory);

    /// Unregisters a guardian
	/// @dev may be called only by a registered guardian
	/// @dev unregistering does not clear the guardian's metadata properties
	function unregisterGuardian() external;

    /// Returns a guardian's data
	/// @param guardian is the guardian to query
	/// @param ip is the guardian's node ipv4 address as a 32b number 
	/// @param orbsAddr is the guardian's Orbs node address 
	/// @param name is the guardian's name as a string
	/// @param website is the guardian's website as a string
	/// @param registrationTime is the timestamp of the guardian's registration
	/// @param lastUpdateTime is the timestamp of the guardian's last update
	function getGuardianData(address guardian) external view returns (bytes4 ip, address orbsAddr, string memory name, string memory website, uint registrationTime, uint lastUpdateTime);

	/// Returns the Orbs addresses of a list of guardians
	/// @dev an unregistered guardian returns address(0) Orbs address
	/// @param guardianAddrs is a list of guardians' addresses to query
	/// @return orbsAddrs is a list of the guardians' Orbs addresses 
	function getGuardiansOrbsAddress(address[] calldata guardianAddrs) external view returns (address[] memory orbsAddrs);

	/// Returns a guardian's ip
	/// @dev an unregistered guardian returns 0 ip address
	/// @param guardian is the guardian to query
	/// @param ip is the guardian's node ipv4 address as a 32b number 
	function getGuardianIp(address guardian) external view returns (bytes4 ip);

	/// Returns the ip of a list of guardians
	/// @dev an unregistered guardian returns 0 ip address
	/// @param guardianAddrs is a list of guardians' addresses to query
	/// @param ips is a list of the guardians' node ipv4 addresses as a 32b numbers
	function getGuardianIps(address[] calldata guardianAddrs) external view returns (bytes4[] memory ips);

	/// Checks if a guardian is registered
	/// @param guardian is the guardian to query
	/// @return registered is a bool indicating a guardian address is registered
	function isRegistered(address guardian) external view returns (bool);

	/// Translates a list guardians Orbs addresses to guardian addresses
	/// @dev an Orbs address that does not correspond to any registered guardian returns address(0)
	/// @param orbsAddrs is a list of the guardians' Orbs addresses to query
	/// @param guardianAddrs is a list of guardians' addresses that matches the Orbs addresses
	function getGuardianAddresses(address[] calldata orbsAddrs) external view returns (address[] memory guardianAddrs);

	/// Resolves the guardian address for a guardian, given a Guardian/Orbs address
	/// @dev revert if the address does not correspond to a registered guardian address or Orbs address
	/// @dev designed to be used for contracts calls, validating a registered guardian
	/// @dev should be used with caution when called by tools as the call may revert
	/// @dev in case of a conflict matching both guardian and Orbs address, the Guardian address takes precedence
	/// @param guardianOrOrbsAddress is the address to query representing a guardian address or Orbs address
	/// @return guardianAddress is the guardian address that matches the queried address
	function resolveGuardianAddress(address guardianOrOrbsAddress) external view returns (address guardianAddress);

	/*
	 * Governance functions
	 */

	/// Migrates a list of guardians from a previous guardians registration contract
	/// @dev governance function called only by the initialization manager
	/// @dev reads the migrated guardians data by calling getGuardianData in the previous contract
	/// @dev imports also the gurdians' registration time and last update
	/// @dev emits a GuardianDataUpdated for each guardian to allow tracking by tools
	/// @param guardiansToMigrate is a list of guardians' addresses to migrate
	/// @param previousContract is the previous registration contract address
	function migrateGuardians(address[] calldata guardiansToMigrate, IGuardiansRegistration previousContract) external /* onlyInitializationAdmin */;

}
