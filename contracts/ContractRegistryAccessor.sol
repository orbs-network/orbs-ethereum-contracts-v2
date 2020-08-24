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
import "./WithClaimableRegistryManagement.sol";
import "./spec_interfaces/IProtocolWallet.sol";

contract ContractRegistryAccessor is WithClaimableRegistryManagement {

    function isManager(string memory role) internal view returns (bool) {
        IContractRegistry _contractRegistry = contractRegistry;
        return msg.sender == registryManager() || _contractRegistry != IContractRegistry(0) && contractRegistry.getManager(role) == msg.sender;
    }

    modifier onlyMigrationManager {
        require(isManager("migrationManager"), "sender is not the migration manager");

        _;
    }

    modifier onlyFunctionalManager {
        require(isManager("functionalManager"), "sender is not the functional manager");

        _;
    }

    modifier onlyEmergencyManager {
        require(isManager("emergencyManager"), "sender is not the emergency manager");

        _;
    }

    IContractRegistry contractRegistry;

    constructor(IContractRegistry _contractRegistry, address _registryManager) public {
        require(address(_contractRegistry) != address(0), "_contractRegistry cannot be 0");
        setContractRegistry(_contractRegistry);
        _transferRegistryManagement(_registryManager);
    }

    event ContractRegistryAddressUpdated(address addr);

    function setContractRegistry(IContractRegistry _contractRegistry) public onlyRegistryManager {
        contractRegistry = _contractRegistry;
        emit ContractRegistryAddressUpdated(address(_contractRegistry));
    }

    function getProtocolContract() public view returns (IProtocol) {
        return IProtocol(contractRegistry.getContract("protocol"));
    }

    function getRewardsContract() public view returns (IRewards) {
        return IRewards(contractRegistry.getContract("rewards"));
    }

    function getCommitteeContract() public view returns (ICommittee) {
        return ICommittee(contractRegistry.getContract("committee"));
    }

    function getElectionsContract() public view returns (IElections) {
        return IElections(contractRegistry.getContract("elections"));
    }

    function getDelegationsContract() public view returns (IDelegations) {
        return IDelegations(contractRegistry.getContract("delegations"));
    }

    function getGuardiansRegistrationContract() public view returns (IGuardiansRegistration) {
        return IGuardiansRegistration(contractRegistry.getContract("guardiansRegistration"));
    }

    function getCertificationContract() public view returns (ICertification) {
        return ICertification(contractRegistry.getContract("certification"));
    }

    function getStakingContract() public view returns (IStakingContract) {
        return IStakingContract(contractRegistry.getContract("staking"));
    }

    function getSubscriptionsContract() public view returns (ISubscriptions) {
        return ISubscriptions(contractRegistry.getContract("subscriptions"));
    }

    function getStakingRewardsWallet() public view returns (IProtocolWallet) {
        return IProtocolWallet(contractRegistry.getContract("stakingRewardsWallet"));
    }

    function getBootstrapRewardsWallet() public view returns (IProtocolWallet) {
        return IProtocolWallet(contractRegistry.getContract("bootstrapRewardsWallet"));
    }

    function getGeneralFeesWallet() public view returns (IFeesWallet) {
        return IFeesWallet(contractRegistry.getContract("generalFeesWallet"));
    }

    function getCertifiedFeesWallet() public view returns (IFeesWallet) {
        return IFeesWallet(contractRegistry.getContract("certifiedFeesWallet"));
    }

}
