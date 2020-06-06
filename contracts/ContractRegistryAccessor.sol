pragma solidity 0.5.16;

import "./spec_interfaces/IContractRegistry.sol";
import "./spec_interfaces/IProtocol.sol";
import "./spec_interfaces/ICommittee.sol";
import "./interfaces/IElections.sol";
import "./spec_interfaces/IValidatorsRegistration.sol";
import "./spec_interfaces/ICompliance.sol";
import "./spec_interfaces/ISubscriptions.sol";
import "./spec_interfaces/IDelegation.sol";
import "./interfaces/IRewards.sol";
import "./WithClaimableMigrationOwnership.sol";
import "./Lockable.sol";

contract ContractRegistryAccessor is Lockable {

    IContractRegistry contractRegistry;

    function setContractRegistry(IContractRegistry _contractRegistry) external onlyMigrationOwner onlyWhenUnlocked {
        require(address(_contractRegistry) != address(0), "contractRegistry must not be 0");
        contractRegistry = _contractRegistry;
    }

    function getProtocolContract() public view returns (IProtocol) {
        return IProtocol(contractRegistry.get("protocol"));
    }

    function getRewardsContract() public view returns (IRewards) {
        return IRewards(contractRegistry.get("rewards"));
    }

    function getCommitteeContract() public view returns (ICommittee) {
        return ICommittee(contractRegistry.get("committee"));
    }

    function getElectionsContract() public view returns (IElections) {
        return IElections(contractRegistry.get("elections"));
    }

    function getDelegationsContract() public view returns (IDelegations) {
        return IDelegations(contractRegistry.get("delegations"));
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
