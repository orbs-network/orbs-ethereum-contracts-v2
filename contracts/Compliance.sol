pragma solidity 0.5.16;

import "./spec_interfaces/ICompliance.sol";
import "./ContractRegistryAccessor.sol";

contract Compliance is ICompliance, ContractRegistryAccessor { // TODO consider renaming to something like 'ValidatorIdentification' or make more generic

    mapping (address => string) validatorCompliance;

    /*
     * External methods
     */

    function getValidatorCompliance(address addr) external view returns (string memory complianceType) {
        string memory compliance = validatorCompliance[addr];
        if (bytes(compliance).length == 0) {
            compliance = "General"; // TODO should this be configurable?
        }
        return compliance;
    }

    function setValidatorCompliance(address addr, string calldata conformanceType) external onlyOwner {
        validatorCompliance[addr] = complianceType; // TODO should we only allow a predefined set? (i.e. "General", "Compliance")
        emit ValidatorComplianceUpdate(addr, complianceType);
        getElectionsContract().validatorComplianceChanged(addr, complianceType);
    }

}
