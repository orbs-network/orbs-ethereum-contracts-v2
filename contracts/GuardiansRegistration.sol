pragma solidity 0.5.16;

import "./spec_interfaces/IGuardiansRegistration.sol";
import "./interfaces/IElections.sol";
import "./ContractRegistryAccessor.sol";
import "./WithClaimableFunctionalOwnership.sol";
import "./Lockable.sol";

contract GuardiansRegistration is IGuardiansRegistration, WithClaimableFunctionalOwnership, Lockable {

	modifier onlyRegisteredGuardian {
		require(isRegistered(msg.sender), "Guardian is not registered");

		_;
	}

	struct Guardian {
		address orbsAddr;
		bytes4 ip;
		string name;
		string website;
		string contact;
		uint256 registrationTime;
		uint256 lastUpdateTime;
	}
	mapping (address => Guardian) public guardians;
	mapping (address => address) public orbsAddressToEthereumAddress;
	mapping (bytes4 => address) public ipToGuardian;
	mapping (address => mapping(string => string)) public guardianMetadata;

	constructor(IContractRegistry _contractRegistry, address _registryManager) Lockable(_contractRegistry, _registryManager) public {}

	/*
     * External methods
     */

    /// @dev Called by a participant who wishes to register as a guardian
	function registerGuardian(bytes4 ip, address orbsAddr, string calldata name, string calldata website, string calldata contact) external onlyWhenActive {
		require(!isRegistered(msg.sender), "registerGuardian: Guardian is already registered");

		guardians[msg.sender].registrationTime = now;
		emit GuardianRegistered(msg.sender);

		_updateGuardian(msg.sender, ip, orbsAddr, name, website, contact);

		electionsContract.guardianRegistered(msg.sender);
	}

    /// @dev Called by a participant who wishes to update its properties
	function updateGuardian(bytes4 ip, address orbsAddr, string calldata name, string calldata website, string calldata contact) external onlyRegisteredGuardian onlyWhenActive {
		_updateGuardian(msg.sender, ip, orbsAddr, name, website, contact);
	}

	function updateGuardianIp(bytes4 ip) external onlyWhenActive {
		address guardianAddr = resolveGuardianAddress(msg.sender);
		Guardian memory data = guardians[guardianAddr];
		_updateGuardian(guardianAddr, ip, data.orbsAddr, data.name, data.website, data.contact);
	}

    /// @dev Called by a prticipant to update additional guardian metadata properties.
    function setMetadata(string calldata key, string calldata value) external onlyRegisteredGuardian onlyWhenActive {
		string memory oldValue = guardianMetadata[msg.sender][key];
		guardianMetadata[msg.sender][key] = value;
		emit GuardianMetadataChanged(msg.sender, key, value, oldValue);
	}

	function getMetadata(address addr, string calldata key) external view returns (string memory) {
		require(isRegistered(addr), "getMetadata: Guardian is not registered");
		return guardianMetadata[addr][key];
	}

	/// @dev Called by a participant who wishes to unregister
	function unregisterGuardian() external onlyRegisteredGuardian onlyWhenActive {
		delete orbsAddressToEthereumAddress[guardians[msg.sender].orbsAddr];
		delete ipToGuardian[guardians[msg.sender].ip];
		Guardian memory guardian = guardians[msg.sender];
		delete guardians[msg.sender];

		electionsContract.guardianUnregistered(msg.sender);
		emit GuardianDataUpdated(msg.sender, false, guardian.ip, guardian.orbsAddr, guardian.name, guardian.website, guardian.contact);
		emit GuardianUnregistered(msg.sender);
	}

    /// @dev Returns a guardian's data
    /// Used also by the Election contract
	function getGuardianData(address addr) external view returns (bytes4 ip, address orbsAddr, string memory name, string memory website, string memory contact, uint registration_time, uint last_update_time) {
		require(isRegistered(addr), "getGuardianData: Guardian is not registered");
		Guardian memory v = guardians[addr];
		return (v.ip, v.orbsAddr, v.name, v.website, v.contact, v.registrationTime, v.lastUpdateTime);
	}

	function getGuardiansOrbsAddress(address[] calldata addrs) external view returns (address[] memory orbsAddrs) {
		orbsAddrs = new address[](addrs.length);
		for (uint i = 0; i < addrs.length; i++) {
			orbsAddrs[i] = guardians[addrs[i]].orbsAddr;
		}
	}

	function getGuardianIp(address addr) external view returns (bytes4 ip) {
		require(isRegistered(addr), "getGuardianIp: Guardian is not registered");
		return guardians[addr].ip;
	}

	function getGuardianIps(address[] calldata addrs) external view returns (bytes4[] memory ips) {
		ips = new bytes4[](addrs.length);
		for (uint i = 0; i < addrs.length; i++) {
			ips[i] = guardians[addrs[i]].ip;
		}
	}

	function isRegistered(address addr) public view returns (bool) {
		return guardians[addr].registrationTime != 0;
	}

	function resolveGuardianAddress(address ethereumOrOrbsAddress) public view returns (address ethereumAddress) {
		if (isRegistered(ethereumOrOrbsAddress)) {
			ethereumAddress = ethereumOrOrbsAddress;
		} else {
			ethereumAddress = orbsAddressToEthereumAddress[ethereumOrOrbsAddress];
		}

		require(ethereumAddress != address(0), "Cannot resolve address");
	}

	/*
     * Methods restricted to other Orbs contracts
     */

    /// @dev Translates a list guardians Ethereum addresses to Orbs addresses
    /// Used by the Election conract
	function getOrbsAddresses(address[] calldata ethereumAddrs) external view returns (address[] memory orbsAddrs) {
		orbsAddrs = new address[](ethereumAddrs.length);
		for (uint i = 0; i < ethereumAddrs.length; i++) {
			orbsAddrs[i] = guardians[ethereumAddrs[i]].orbsAddr;
		}
	}

	/// @dev Translates a list guardians Orbs addresses to Ethereum addresses
	/// Used by the Election contract
	function getEthereumAddresses(address[] calldata orbsAddrs) external view returns (address[] memory ethereumAddrs) {
		ethereumAddrs = new address[](orbsAddrs.length);
		for (uint i = 0; i < orbsAddrs.length; i++) {
			ethereumAddrs[i] = orbsAddressToEthereumAddress[orbsAddrs[i]];
		}
	}

	/*
	 * Private methods
	 */

	function _updateGuardian(address guardianAddr, bytes4 ip, address orbsAddr, string memory name, string memory website, string memory contact) private {
		require(orbsAddr != address(0), "orbs address must be non zero");
		require(orbsAddr != guardianAddr, "orbs address must be different than the guardian address");
		require(bytes(name).length != 0, "name must be given");

		delete ipToGuardian[guardians[guardianAddr].ip];
		require(ipToGuardian[ip] == address(0), "ip is already in use");
		ipToGuardian[ip] = guardianAddr;

		delete orbsAddressToEthereumAddress[guardians[guardianAddr].orbsAddr];
		require(orbsAddressToEthereumAddress[orbsAddr] == address(0), "orbs address is already in use");
		orbsAddressToEthereumAddress[orbsAddr] = guardianAddr;

		guardians[guardianAddr].orbsAddr = orbsAddr;
		guardians[guardianAddr].ip = ip;
		guardians[guardianAddr].name = name;
		guardians[guardianAddr].website = website;
		guardians[guardianAddr].contact = contact;
		guardians[guardianAddr].lastUpdateTime = now;

        emit GuardianDataUpdated(guardianAddr, true, ip, orbsAddr, name, website, contact);
    }

	IElections electionsContract;
	function refreshContracts() external {
		electionsContract = getElectionsContract();
	}

}
