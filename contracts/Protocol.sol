// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./spec_interfaces/IProtocol.sol";
import "./ManagedContract.sol";

/// @title Protocol upgrades contract
contract Protocol is IProtocol, ManagedContract {

    struct DeploymentSubset {
        bool exists;
        uint256 nextVersion;
        uint fromTimestamp;
        uint256 currentVersion;
    }

    mapping(string => DeploymentSubset) public deploymentSubsets;

    /// @param _contractRegistry is the contract registry address
    /// @param _registryAdmin is the registry admin address
    constructor(IContractRegistry _contractRegistry, address _registryAdmin) ManagedContract(_contractRegistry, _registryAdmin) public {}

    /*
     * External functions
     */

    /// Checks whether a deployment subset exists 
    /// @param deploymentSubset is the name of the deployment subset to query
    /// @return exists is a bool indicating the deployment subset exists
    function deploymentSubsetExists(string calldata deploymentSubset) external override view returns (bool) {
        return deploymentSubsets[deploymentSubset].exists;
    }

    /// Returns the current protocol version for a given deployment subset to query
	/// @dev an unexisting deployment subset returns protocol version 0
    /// @param deploymentSubset is the name of the deployment subset
    /// @return currentVersion is the current protocol version of the deployment subset
    function getProtocolVersion(string calldata deploymentSubset) external override view returns (uint256 currentVersion) {
        (, currentVersion) = checkPrevUpgrades(deploymentSubset);
    }

    /// Creates a new deployment subset
	/// @dev governance function called only by the functional manager
    /// @param deploymentSubset is the name of the new deployment subset
    /// @param initialProtocolVersion is the initial protocol version of the deployment subset
    function createDeploymentSubset(string calldata deploymentSubset, uint256 initialProtocolVersion) external override onlyFunctionalManager {
        require(!deploymentSubsets[deploymentSubset].exists, "deployment subset already exists");

        deploymentSubsets[deploymentSubset].currentVersion = initialProtocolVersion;
        deploymentSubsets[deploymentSubset].nextVersion = initialProtocolVersion;
        deploymentSubsets[deploymentSubset].fromTimestamp = now;
        deploymentSubsets[deploymentSubset].exists = true;

        emit ProtocolVersionChanged(deploymentSubset, initialProtocolVersion, initialProtocolVersion, now);
    }

    /// Schedules a protocol version upgrade for the given deployment subset
	/// @dev governance function called only by the functional manager
    /// @param deploymentSubset is the name of the deployment subset
    /// @param nextVersion is the new protocol version to upgrade to, must be greater or equal to current version
    /// @param fromTimestamp is the time the new protocol version takes effect, must be in the future
    function setProtocolVersion(string calldata deploymentSubset, uint256 nextVersion, uint256 fromTimestamp) external override onlyFunctionalManager {
        require(deploymentSubsets[deploymentSubset].exists, "deployment subset does not exist");
        require(fromTimestamp > now, "a protocol update can only be scheduled for the future");

        (bool prevUpgradeExecuted, uint256 currentVersion) = checkPrevUpgrades(deploymentSubset);

        require(nextVersion >= currentVersion, "protocol version must be greater or equal to current version");

        deploymentSubsets[deploymentSubset].nextVersion = nextVersion;
        deploymentSubsets[deploymentSubset].fromTimestamp = fromTimestamp;
        if (prevUpgradeExecuted) {
            deploymentSubsets[deploymentSubset].currentVersion = currentVersion;
        }

        emit ProtocolVersionChanged(deploymentSubset, currentVersion, nextVersion, fromTimestamp);
    }

    /*
     * Private functions
     */

    /// Check whether a previously set protocol upgrade was executed and returns accordingly the current protocol version 
    /// @param deploymentSubset is the name of the deployment subset to query
    /// @return prevUpgradeExecuted indicates whether the previous protocol upgrade was executed 
    /// @return currentVersion is the active protocol version for the deployment subset    
    function checkPrevUpgrades(string memory deploymentSubset) private view returns (bool prevUpgradeExecuted, uint256 currentVersion) {
        prevUpgradeExecuted = deploymentSubsets[deploymentSubset].fromTimestamp <= now;
        currentVersion = prevUpgradeExecuted ? deploymentSubsets[deploymentSubset].nextVersion :
                                               deploymentSubsets[deploymentSubset].currentVersion;
    }

    /*
     * Contracts topology / registry interface
     */

	/// Refreshes the address of the other contracts the contract interacts with
    /// @dev called by the registry contract upon an update of a contract in the registry
    /// @dev the protocol upgrades contract does not interact with other contracts and therefore implements an empty refreshContracts function
    function refreshContracts() external override {}
}
