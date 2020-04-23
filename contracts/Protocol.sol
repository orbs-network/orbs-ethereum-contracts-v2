pragma solidity 0.5.16;

import "@openzeppelin/contracts/ownership/Ownable.sol";
import "./spec_interfaces/IProtocol.sol";

contract Protocol is IProtocol, Ownable {

    struct DeploymentSubset {
        bool exists;
        uint nextVersion;
        uint asOfBlock;
        uint currentVersion;
    }

    mapping (string => DeploymentSubset) deploymentSubsets;

    function deploymentSubsetExists(string memory deploymentSubset) public view returns (bool) {
        return deploymentSubsets[deploymentSubset].exists;
    }

    function setProtocolVersion(string calldata deploymentSubset, uint256 protocolVersion, uint256 asOfBlock) external onlyOwner {
        if (!deploymentSubsets[deploymentSubset].exists) {
            require(asOfBlock == 0, "initial protocol version must be from block 0");
            deploymentSubsets[deploymentSubset].currentVersion = protocolVersion;
            deploymentSubsets[deploymentSubset].exists = true;
        } else {
            uint currentAsOfBlock = deploymentSubsets[deploymentSubset].asOfBlock;
            if (currentAsOfBlock <= block.number) {
                deploymentSubsets[deploymentSubset].currentVersion = deploymentSubsets[deploymentSubset].nextVersion;
            }

            require(asOfBlock > block.number, "protocol update can only be scheduled for a future block");
            require(protocolVersion > deploymentSubsets[deploymentSubset].currentVersion, "protocol version must be later than current version");
        }

        deploymentSubsets[deploymentSubset].nextVersion = protocolVersion;
        deploymentSubsets[deploymentSubset].asOfBlock = asOfBlock;

        emit ProtocolVersionChanged(deploymentSubset, protocolVersion, asOfBlock);
    }
}
