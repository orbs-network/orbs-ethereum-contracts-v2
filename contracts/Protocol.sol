pragma solidity 0.5.16;

import "./spec_interfaces/IProtocol.sol";
import "./WithClaimableFunctionalOwnership.sol";
import "./WithClaimableMigrationOwnership.sol";
import "./ContractRegistryAccessor.sol";

contract Protocol is IProtocol, ContractRegistryAccessor, WithClaimableFunctionalOwnership, Lockable {

    struct DeploymentSubset {
        bool exists;
        uint256 nextVersion;
        uint fromTimestamp;
        uint256 currentVersion;
    }

    mapping (string => DeploymentSubset) deploymentSubsets;

    function deploymentSubsetExists(string calldata deploymentSubset) external view returns (bool) {
        return deploymentSubsets[deploymentSubset].exists;
    }

    function getProtocolVersion(string calldata deploymentSubset) external view returns (uint256 currentVersion) {
        (, currentVersion) = checkPrevUpgrades(deploymentSubset);
    }

    function createDeploymentSubset(string calldata deploymentSubset, uint256 initialProtocolVersion) external onlyFunctionalOwner onlyWhenActive {
        require(!deploymentSubsets[deploymentSubset].exists, "deployment subset already exists");

        deploymentSubsets[deploymentSubset].currentVersion = initialProtocolVersion;
        deploymentSubsets[deploymentSubset].nextVersion = initialProtocolVersion;
        deploymentSubsets[deploymentSubset].fromTimestamp = now;
        deploymentSubsets[deploymentSubset].exists = true;

        emit ProtocolVersionChanged(deploymentSubset, initialProtocolVersion, initialProtocolVersion, now);
    }

    function setProtocolVersion(string calldata deploymentSubset, uint256 nextVersion, uint256 fromTimestamp) external onlyFunctionalOwner onlyWhenActive {
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

    function checkPrevUpgrades(string memory deploymentSubset) private view returns (bool prevUpgradeExecuted, uint256 currentVersion) {
        prevUpgradeExecuted = deploymentSubsets[deploymentSubset].fromTimestamp <= now;
        currentVersion = prevUpgradeExecuted ? deploymentSubsets[deploymentSubset].nextVersion :
                                               deploymentSubsets[deploymentSubset].currentVersion;
    }
}
