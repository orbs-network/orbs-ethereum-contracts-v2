pragma solidity 0.5.16;

import "@openzeppelin/contracts/ownership/Ownable.sol";
import "./spec_interfaces/IProtocol.sol";

contract Protocol is IProtocol, Ownable {

    struct DeploymentSubset {
        bool exists;
        uint256 nextVersion;
        uint asOfBlock;
        uint256 currentVersion;
    }

    mapping (string => DeploymentSubset) deploymentSubsets;

    function deploymentSubsetExists(string calldata deploymentSubset) external view returns (bool) {
        return deploymentSubsets[deploymentSubset].exists;
    }

    function createDeploymentSubset(string calldata deploymentSubset, uint256 initialProtocolVersion) external onlyOwner {
        require(!deploymentSubsets[deploymentSubset].exists, "deployment subset already exists");

        deploymentSubsets[deploymentSubset].currentVersion = initialProtocolVersion;
        deploymentSubsets[deploymentSubset].nextVersion = initialProtocolVersion;
        deploymentSubsets[deploymentSubset].asOfBlock = block.number;
        deploymentSubsets[deploymentSubset].exists = true;

        emit ProtocolVersionChanged(deploymentSubset, initialProtocolVersion, block.number); // TODO different event?
    }

    function setProtocolVersion(string calldata deploymentSubset, uint256 protocolVersion, uint256 asOfBlock) external onlyOwner {
        require(deploymentSubsets[deploymentSubset].exists, "deployment subset does not exist");
        require(asOfBlock > block.number, "protocol update can only be scheduled for a future block");

        if (deploymentSubsets[deploymentSubset].asOfBlock <= block.number) {
            deploymentSubsets[deploymentSubset].currentVersion = deploymentSubsets[deploymentSubset].nextVersion;
        }
        require(protocolVersion > deploymentSubsets[deploymentSubset].currentVersion, "protocol version must be later than current version");

        deploymentSubsets[deploymentSubset].nextVersion = protocolVersion;
        deploymentSubsets[deploymentSubset].asOfBlock = asOfBlock;

        emit ProtocolVersionChanged(deploymentSubset, protocolVersion, asOfBlock);
    }

    // TODO what about cancelling a future upgrade?
}
