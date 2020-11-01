// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

contract GuardiansRegistrationPreviousVersion {

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

	modifier onlyRegisteredGuardian {
		require(isRegistered(msg.sender), "Guardian is not registered");

		_;
	}

	/*
     * External methods
     */

    /// @dev Called by a participant who wishes to register as a guardian
	function registerGuardian(bytes4 ip, address orbsAddr, string calldata name, string calldata website) external {
		require(!isRegistered(msg.sender), "registerGuardian: Guardian is already registered");

		guardians[msg.sender].registrationTime = uint32(block.timestamp);

		_updateGuardian(msg.sender, ip, orbsAddr, name, website);
	}

    /// @dev Called by a participant who wishes to update its properties
	function updateGuardian(bytes4 ip, address orbsAddr, string calldata name, string calldata website) external onlyRegisteredGuardian {
		_updateGuardian(msg.sender, ip, orbsAddr, name, website);
	}

	function updateGuardianIp(bytes4 ip) external {
		address guardianAddr = resolveGuardianAddress(msg.sender);
		Guardian memory data = guardians[guardianAddr];
		_updateGuardian(guardianAddr, ip, data.orbsAddr, data.name, data.website);
	}

    /// @dev Called by a guardian to update additional guardian metadata properties.
    function setMetadata(string calldata key, string calldata value) external onlyRegisteredGuardian {
		_setMetadata(msg.sender, key, value);
	}

	function getMetadata(address guardian, string calldata key) external view returns (string memory) {
		return guardianMetadata[guardian][key];
	}

	/// @dev Called by a participant who wishes to unregister
	function unregisterGuardian() external onlyRegisteredGuardian {
		delete orbsAddressToGuardianAddress[guardians[msg.sender].orbsAddr];
		delete ipToGuardian[guardians[msg.sender].ip];
		delete guardians[msg.sender];

	}

    /// @dev Returns a guardian's data
	function getGuardianData(address guardian) external view returns (bytes4 ip, address orbsAddr, string memory name, string memory website, string memory contact, uint registrationTime, uint lastUpdateTime) {
		Guardian memory v = guardians[guardian];
		return (v.ip, v.orbsAddr, v.name, v.website, "contact", v.registrationTime, v.lastUpdateTime);
	}

	function getGuardiansOrbsAddress(address[] calldata guardianAddrs) external view returns (address[] memory orbsAddrs) {
		orbsAddrs = new address[](guardianAddrs.length);
		for (uint i = 0; i < guardianAddrs.length; i++) {
			orbsAddrs[i] = guardians[guardianAddrs[i]].orbsAddr;
		}
	}

	function getGuardianIp(address guardian) external view returns (bytes4 ip) {
		return guardians[guardian].ip;
	}

	function getGuardianIps(address[] calldata guardianAddrs) external view returns (bytes4[] memory ips) {
		ips = new bytes4[](guardianAddrs.length);
		for (uint i = 0; i < guardianAddrs.length; i++) {
			ips[i] = guardians[guardianAddrs[i]].ip;
		}
	}

	function isRegistered(address guardian) public view returns (bool) {
		return guardians[guardian].registrationTime != 0;
	}

	function resolveGuardianAddress(address guardianOrOrbsAddress) public view returns (address guardianAddress) {
		if (isRegistered(guardianOrOrbsAddress)) {
			guardianAddress = guardianOrOrbsAddress;
		} else {
			guardianAddress = orbsAddressToGuardianAddress[guardianOrOrbsAddress];
		}

		require(guardianAddress != address(0), "Cannot resolve address");
	}

	/// @dev Translates a list guardians Orbs addresses to Ethereum addresses
	function getGuardianAddresses(address[] calldata orbsAddrs) external view returns (address[] memory guardianAddrs) {
		guardianAddrs = new address[](orbsAddrs.length);
		for (uint i = 0; i < orbsAddrs.length; i++) {
			guardianAddrs[i] = orbsAddressToGuardianAddress[orbsAddrs[i]];
		}
	}

	/*
	 * Private methods
	 */

	function _updateGuardian(address guardianAddr, bytes4 ip, address orbsAddr, string memory name, string memory website) private {
		require(orbsAddr != address(0), "orbs address must be non zero");
		require(orbsAddr != guardianAddr, "orbs address must be different than the guardian address");
		require(!isRegistered(orbsAddr), "orbs address must not be a guardian address of a registered guardian");
		require(bytes(name).length != 0, "name must be given");

		delete ipToGuardian[guardians[guardianAddr].ip];
		require(ipToGuardian[ip] == address(0), "ip is already in use");
		ipToGuardian[ip] = guardianAddr;

		delete orbsAddressToGuardianAddress[guardians[guardianAddr].orbsAddr];
		require(orbsAddressToGuardianAddress[orbsAddr] == address(0), "orbs address is already in use");
		orbsAddressToGuardianAddress[orbsAddr] = guardianAddr;

		guardians[guardianAddr].orbsAddr = orbsAddr;
		guardians[guardianAddr].ip = ip;
		guardians[guardianAddr].name = name;
		guardians[guardianAddr].website = website;
		guardians[guardianAddr].lastUpdateTime = uint32(block.timestamp);

    }

	function _setMetadata(address guardian, string memory key, string memory value) private {
		guardianMetadata[guardian][key] = value;
	}

}
