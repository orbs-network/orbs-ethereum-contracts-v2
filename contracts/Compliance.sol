pragma solidity 0.5.16;

import "./spec_interfaces/ICompliance.sol";
import "./ContractRegistryAccessor.sol";

contract Compliance is ICompliance, ContractRegistryAccessor {

    mapping (address => bool) validatorCompliance;

    /*
     * External methods
     */

    function isValidatorCompliant(address addr) external view returns (bool isCompliant) {
        return validatorCompliance[addr];
    }

    function isValidatorCompliantBatch(address[] calldata addrs) external view returns (bool[] memory isCompliantArr) { // todo needed?
        isCompliantArr = new bool[](addrs.length);
        for (uint i = 0; i < addrs.length; i++) {
            isCompliantArr[i] = validatorCompliance[addrs[i]];
        }
    }

    function setValidatorCompliance(address addr, bool isCompliant) external onlyOwner {
        validatorCompliance[addr] = isCompliant;
        emit ValidatorComplianceUpdate(addr, isCompliant);
        getElectionsContract().validatorComplianceChanged(addr, isCompliant);
    }

}
