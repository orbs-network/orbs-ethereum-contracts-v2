pragma solidity 0.5.16;

import "@openzeppelin/contracts/ownership/Ownable.sol";
import "./spec_interfaces/ICompliance.sol";

contract Compliance is ICompliance, Ownable {

    IContractRegistry contractRegistry; // TODO move this (and logic) to a super class

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
        // TODO notify elections contract?
    }

    /*
     * Governance
     */

    function setContractRegistry(IContractRegistry _contractRegistry) external onlyOwner {
        require(address(_contractRegistry) != address(0), "contractRegistry must not be 0");
        contractRegistry = _contractRegistry;
    }


}
