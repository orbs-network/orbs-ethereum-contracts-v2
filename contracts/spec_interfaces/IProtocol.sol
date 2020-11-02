// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

/// @title Protocol upgrades contract interface
interface IProtocol {
    event ProtocolVersionChanged(string deploymentSubset, uint256 currentVersion, uint256 nextVersion, uint256 fromTimestamp);

    /*
     *   External functions
     */

    /// Checks whether a deployment subset exists 
    /// @param deploymentSubset is the name of the deployment subset to query
    /// @return exists is a bool indicating the deployment subset exists
    function deploymentSubsetExists(string calldata deploymentSubset) external view returns (bool);

    /// Returns the current protocol version for a given deployment subset to query
	/// @dev an unexisting deployment subset returns protocol version 0
    /// @param deploymentSubset is the name of the deployment subset
    /// @return currentVersion is the current protocol version of the deployment subset
    function getProtocolVersion(string calldata deploymentSubset) external view returns (uint256 currentVersion);

    /*
     *   Governance functions
     */

    /// Creates a new deployment subset
	/// @dev governance function called only by the functional manager
    /// @param deploymentSubset is the name of the new deployment subset
    /// @param initialProtocolVersion is the initial protocol version of the deployment subset
    function createDeploymentSubset(string calldata deploymentSubset, uint256 initialProtocolVersion) external /* onlyFunctionalManager */;


    /// Schedules a protocol version upgrade for the given deployment subset
	/// @dev governance function called only by the functional manager
    /// @param deploymentSubset is the name of the deployment subset
    /// @param nextVersion is the new protocol version to upgrade to, must be greater or equal to current version
    /// @param fromTimestamp is the time the new protocol version takes effect, must be in the future
    function setProtocolVersion(string calldata deploymentSubset, uint256 nextVersion, uint256 fromTimestamp) external /* onlyFunctionalManager */;
}
