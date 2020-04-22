pragma solidity 0.5.16;

import "./spec_interfaces/ICompliance.sol";
import "./ContractAccessor.sol";

contract Compliance is ICompliance, ContractAccessor { // TODO consider renaming to something like 'ValidatorIdentification' or make more generic

    mapping (address => string) validatorCompliance;

    /*
     * External methods
     */

    function getValidatorCompliance(address addr) external view returns (string memory conformanceType) {
        string memory compliance = validatorCompliance[addr];
        if (bytes(compliance).length == 0) {
            compliance = "General"; // TODO should this be configurable?
        }
        return compliance;
    }

    function setValidatorCompliance(address addr, string calldata conformanceType) external onlyOwner {
        validatorCompliance[addr] = conformanceType; // TODO should we only allow a predefined set? (i.e. "General", "Compliance")
        emit ValidatorConformanceUpdate(addr, conformanceType);
        getElectionsContract().validatorConformanceChanged(addr, conformanceType);
    }

}
