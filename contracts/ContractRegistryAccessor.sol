pragma solidity 0.5.16;

import "./spec_interfaces/IContractRegistry.sol";
import "./spec_interfaces/IProtocol.sol";
import "./spec_interfaces/ICommittee.sol";
import "./interfaces/IElections.sol";
import "./spec_interfaces/IGuardiansRegistration.sol";
import "./spec_interfaces/ICertification.sol";
import "./spec_interfaces/ISubscriptions.sol";
import "./spec_interfaces/IDelegation.sol";
import "./spec_interfaces/IFeesWallet.sol";
import "./interfaces/IRewards.sol";
import "./WithClaimableMigrationOwnership.sol";
import "./Lockable.sol";
import "./spec_interfaces/IProtocolWallet.sol";
import "./spec_interfaces/IGuardiansWallet.sol";

contract ContractRegistryAccessor is WithClaimableMigrationOwnership {

    IContractRegistry contractRegistry;

    event ContractRegistryAddressUpdated(address addr);

    function setContractRegistry(IContractRegistry _contractRegistry) external onlyMigrationOwner {
        contractRegistry = _contractRegistry;
        emit ContractRegistryAddressUpdated(address(_contractRegistry));
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

    function getGuardiansRegistrationContract() public view returns (IGuardiansRegistration) {
        return IGuardiansRegistration(contractRegistry.get("guardiansRegistration"));
    }

    function getCertificationContract() public view returns (ICertification) {
        return ICertification(contractRegistry.get("certification"));
    }

    function getStakingContract() public view returns (IStakingContract) {
        return IStakingContract(contractRegistry.get("staking"));
    }

    function getSubscriptionsContract() public view returns (ISubscriptions) {
        return ISubscriptions(contractRegistry.get("subscriptions"));
    }

    function getStakingRewardsWallet() public view returns (IProtocolWallet) {
        return IProtocolWallet(contractRegistry.get("stakingRewardsWallet"));
    }

    function getBootstrapRewardsWallet() public view returns (IProtocolWallet) {
        return IProtocolWallet(contractRegistry.get("bootstrapRewardsWallet"));
    }

    function getGuardiansWallet() public view returns (IGuardiansWallet) {
        return IGuardiansWallet(contractRegistry.get("guardiansWallet"));
    }

    function getGeneralFeesWallet() public view returns (IFeesWallet) {
        return IFeesWallet(contractRegistry.get("generalFeesWallet"));
    }

    function getCertifiedFeesWallet() public view returns (IFeesWallet) {
        return IFeesWallet(contractRegistry.get("certifiedFeesWallet"));
    }

}
