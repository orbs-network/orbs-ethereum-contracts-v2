pragma solidity 0.5.16;

import "./spec_interfaces/IContractRegistry.sol";
import "./WithClaimableRegistryManagement.sol";
import "./Initializable.sol";

contract ContractRegistryAccessor is WithClaimableRegistryManagement, Initializable {

    IContractRegistry contractRegistry;

    modifier onlyAdmin {
        require(isAdmin(), "sender is not an admin (registryManger or initializationAdmin)");

        _;
    }

    function isManager(string memory role) internal view returns (bool) {
        IContractRegistry _contractRegistry = contractRegistry;
        return isAdmin() || _contractRegistry != IContractRegistry(0) && contractRegistry.getManager(role) == msg.sender;
    }

    function isAdmin() internal view returns (bool) {
        return msg.sender == registryAdmin() || msg.sender == initializationAdmin() || msg.sender == address(contractRegistry);
    }

    constructor(IContractRegistry _contractRegistry, address _registryAdmin) public {
        require(address(_contractRegistry) != address(0), "_contractRegistry cannot be 0");
        setContractRegistry(_contractRegistry);
        _transferRegistryManagement(_registryAdmin);
    }

    event ContractRegistryAddressUpdated(address addr);

    function setContractRegistry(IContractRegistry newContractRegistry) public onlyAdmin {
        require(newContractRegistry.getPreviousContractRegistry() == contractRegistry, "new contract registry must provide the previous contract registry");
        contractRegistry = newContractRegistry;
        emit ContractRegistryAddressUpdated(address(newContractRegistry));
    }

    function getProtocolContract() internal view returns (address) {
        return contractRegistry.getContract("protocol");
    }

    function getRewardsContract() internal view returns (address) {
        return contractRegistry.getContract("rewards");
    }

    function getCommitteeContract() internal view returns (address) {
        return contractRegistry.getContract("committee");
    }

    function getElectionsContract() internal view returns (address) {
        return contractRegistry.getContract("elections");
    }

    function getDelegationsContract() internal view returns (address) {
        return contractRegistry.getContract("delegations");
    }

    function getGuardiansRegistrationContract() internal view returns (address) {
        return contractRegistry.getContract("guardiansRegistration");
    }

    function getCertificationContract() internal view returns (address) {
        return contractRegistry.getContract("certification");
    }

    function getStakingContract() internal view returns (address) {
        return contractRegistry.getContract("staking");
    }

    function getSubscriptionsContract() internal view returns (address) {
        return contractRegistry.getContract("subscriptions");
    }

    function getStakingRewardsWallet() internal view returns (address) {
        return contractRegistry.getContract("stakingRewardsWallet");
    }

    function getBootstrapRewardsWallet() internal view returns (address) {
        return contractRegistry.getContract("bootstrapRewardsWallet");
    }

    function getGeneralFeesWallet() internal view returns (address) {
        return contractRegistry.getContract("generalFeesWallet");
    }

    function getCertifiedFeesWallet() internal view returns (address) {
        return contractRegistry.getContract("certifiedFeesWallet");
    }

    function getStakingContractHandler() internal view returns (address) {
        return contractRegistry.getContract("stakingContractHandler");
    }

}
