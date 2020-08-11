pragma solidity 0.5.16;

import "./IContractRegistry.sol";

/// @title Elections contract interface
interface IGuardiansRegistration {
	event GuardianRegistered(address addr);
	event GuardianUnregistered(address addr);
	event GuardianDataUpdated(address addr, bool isRegistered, bytes4 ip, address orbsAddr, string name, string website, string contact);
	event GuardianMetadataChanged(address addr, string key, string newValue, string oldValue);

	/*
     * External methods
     */

    /// @dev Called by a participant who wishes to register as a guardian
	function registerGuardian(bytes4 ip, address orbsAddr, string calldata name, string calldata website, string calldata contact) external;

    /// @dev Called by a participant who wishes to update its propertires
	function updateGuardian(bytes4 ip, address orbsAddr, string calldata name, string calldata website, string calldata contact) external;

	/// @dev Called by a participant who wishes to update its IP address (can be call by both main and Orbs addresses)
	function updateGuardianIp(bytes4 ip) external /* onlyWhenActive */;

    /// @dev Called by a participant to update additional guardian metadata properties.
    function setMetadata(string calldata key, string calldata value) external;

    /// @dev Called by a participant to get additional guardian metadata properties.
    function getMetadata(address addr, string calldata key) external view returns (string memory);

    /// @dev Called by a participant who wishes to unregister
	function unregisterGuardian() external;

    /// @dev Returns a guardian's data
    /// Used also by the Election contract
	function getGuardianData(address addr) external view returns (bytes4 ip, address orbsAddr, string memory name, string memory website, string memory contact, uint registration_time, uint last_update_time);

	/// @dev Returns the Orbs addresses of a list of guardians
	/// Used also by the committee contract
	function getGuardiansOrbsAddress(address[] calldata addrs) external view returns (address[] memory orbsAddrs);

	/// @dev Returns a guardian's ip
	/// Used also by the Election contract
	function getGuardianIp(address addr) external view returns (bytes4 ip);

	/// @dev Returns guardian ips
	function getGuardianIps(address[] calldata addr) external view returns (bytes4[] memory ips);


	/// @dev Returns true if the given address is of a registered guardian
	/// Used also by the Election contract
	function isRegistered(address addr) external view returns (bool);

	/*
     * Methods restricted to other Orbs contracts
     */

    /// @dev Translates a list guardians Ethereum addresses to Orbs addresses
    /// Used by the Election contract
	function getOrbsAddresses(address[] calldata ethereumAddrs) external view returns (address[] memory orbsAddr);

	/// @dev Translates a list guardians Orbs addresses to Ethereum addresses
	/// Used by the Election contract
	function getEthereumAddresses(address[] calldata orbsAddrs) external view returns (address[] memory ethereumAddr);

	/// @dev Resolves the ethereum address for a guardian, given an Ethereum/Orbs address
	function resolveGuardianAddress(address ethereumOrOrbsAddress) external view returns (address mainAddress);

}
