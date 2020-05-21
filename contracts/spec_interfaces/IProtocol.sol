pragma solidity 0.5.16;

interface IProtocol {
    event ProtocolVersionChanged(string deploymentSubset, uint256 protocolVersion, uint256 fromTimestamp);

    /*
     *   External methods
     */

    /// @dev returns true if the given deployment subset exists (i.e - is registered with a protocol version)
    function deploymentSubsetExists(string calldata deploymentSubset) external view returns (bool);

    /// @dev returns the current protocol version for the given deployment subset.
    function getProtocolVersion(string calldata deploymentSubset) external view returns (uint256);

    /*
     *   Governor methods
     */

    /// @dev create a new deployment subset.
    function createDeploymentSubset(string calldata deploymentSubset, uint256 initialProtocolVersion) external /* onlyOwner */;

    /// @dev schedules a protocol version upgrade for the given deployment subset.
    function setProtocolVersion(string calldata deploymentSubset, uint256 protocolVersion, uint256 fromTimestamp) external /* onlyOwner */;
}
