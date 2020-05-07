pragma solidity 0.5.16;

import "@openzeppelin/contracts/ownership/Ownable.sol";
import "./spec_interfaces/IContractRegistry.sol";
import "./spec_interfaces/IProtocol.sol";
import "./spec_interfaces/IFees.sol";
import "./spec_interfaces/ICommittee.sol";
import "./interfaces/IElections.sol";
import "./spec_interfaces/IValidatorsRegistration.sol";
import "./spec_interfaces/ICompliance.sol";
import "./spec_interfaces/ISubscriptions.sol";

contract ContractRegistryAccessor is Ownable {

    IContractRegistry contractRegistry;

    function setContractRegistry(IContractRegistry _contractRegistry) external onlyOwner {
        require(address(_contractRegistry) != address(0), "contractRegistry must not be 0");
        contractRegistry = _contractRegistry;
    }

    function getProtocolContract() public view returns (IProtocol) {
        return IProtocol(contractRegistry.get("protocol"));
    }

    function getFeesContract() public view returns (IFees) {
        return IFees(contractRegistry.get("fees"));
    }

    function getGeneralCommitteeContract() public view returns (ICommittee) {
        return ICommittee(contractRegistry.get("committee-general"));
    }

    function getComplianceCommitteeContract() public view returns (ICommittee) {
        return ICommittee(contractRegistry.get("committee-compliance"));
    }

    function getElectionsContract() public view returns (IElections) {
        return IElections(contractRegistry.get("elections"));
    }

    function getDelegationsContract() public view returns (IElections) {
        return IElections(contractRegistry.get("delegations"));
    }

    function getValidatorsRegistrationContract() public view returns (IValidatorsRegistration) {
        return IValidatorsRegistration(contractRegistry.get("validatorsRegistration"));
    }

    function getComplianceContract() public view returns (ICompliance) {
        return ICompliance(contractRegistry.get("compliance"));
    }

    function getStakingContract() public view returns (IStakingContract) {
        return IStakingContract(contractRegistry.get("staking"));
    }

    function getSubscriptionsContract() public view returns (ISubscriptions) {
        return ISubscriptions(contractRegistry.get("subscriptions"));
    }


}
