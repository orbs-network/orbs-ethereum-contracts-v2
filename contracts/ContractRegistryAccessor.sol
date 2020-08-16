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
import "./spec_interfaces/IProtocolWallet.sol";
import "./IContractRegistryListener.sol";

contract ContractRegistryAccessor is WithClaimableMigrationOwnership {

    IContractRegistry contractRegistry;

    constructor(IContractRegistry _contractRegistry) public {
        require(address(_contractRegistry) != address(0), "_contractRegistry cannot be 0");
        setContractRegistry(_contractRegistry);
    }

    event ContractRegistryAddressUpdated(address addr);

    function setContractRegistry(IContractRegistry _contractRegistry) public onlyMigrationOwner {
        contractRegistry = _contractRegistry;
        emit ContractRegistryAddressUpdated(address(_contractRegistry));
    }

    function getProtocolContract() public view returns (IProtocol) {
        return IProtocol(getContract("protocol"));
    }

    function getRewardsContract() public view returns (IRewards) {
        return IRewards(getContract("rewards"));
    }

    function getCommitteeContract() public view returns (ICommittee) {
        return ICommittee(getContract("committee"));
    }

    function getElectionsContract() public view returns (IElections) {
        return IElections(getContract("elections"));
    }

    function getDelegationsContract() public view returns (IDelegations) {
        return IDelegations(getContract("delegations"));
    }

    function getGuardiansRegistrationContract() public view returns (IGuardiansRegistration) {
        return IGuardiansRegistration(getContract("guardiansRegistration"));
    }

    function getCertificationContract() public view returns (ICertification) {
        return ICertification(getContract("certification"));
    }

    function getStakingContract() public view returns (IStakingContract) {
        return IStakingContract(getContract("staking"));
    }

    function getSubscriptionsContract() public view returns (ISubscriptions) {
        return ISubscriptions(getContract("subscriptions"));
    }

    function getStakingRewardsWallet() public view returns (IProtocolWallet) {
        return IProtocolWallet(getContract("stakingRewardsWallet"));
    }

    function getBootstrapRewardsWallet() public view returns (IProtocolWallet) {
        return IProtocolWallet(getContract("bootstrapRewardsWallet"));
    }

    function getGeneralFeesWallet() public view returns (IFeesWallet) {
        return IFeesWallet(getContract("generalFeesWallet"));
    }

    function getCertifiedFeesWallet() public view returns (IFeesWallet) {
        return IFeesWallet(getContract("certifiedFeesWallet"));
    }

    function stringToBytes32(string memory source) public pure returns (bytes32 result) {
        bytes memory stringAsBytes = bytes(source);
        if (stringAsBytes.length == 0) {
            return 0x0;
        }

        if (stringAsBytes.length > 32) {
            return keccak256(stringAsBytes);
        }

        assembly {
            result := mload(add(source, 32))
        }
    }

    function getContract(string memory name) private view returns (address) {
        bytes32[] memory arr = new bytes32[](1);
        arr[0] = stringToBytes32(name);
        address[] memory addrs = contractRegistry.getContracts(arr);
        return addrs[0];
    }
}
