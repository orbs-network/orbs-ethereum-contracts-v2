pragma solidity 0.5.16;

import "./spec_interfaces/ICertification.sol";
import "./ContractRegistryAccessor.sol";
import "./WithClaimableFunctionalOwnership.sol";
import "./Lockable.sol";

contract Certification is ICertification, WithClaimableFunctionalOwnership, Lockable {

    mapping (address => bool) guardianCertification;

    constructor(IContractRegistry _contractRegistry, address _registryManager) Lockable(_contractRegistry, _registryManager) public {}

    /*
     * External methods
     */

    function isGuardianCertified(address addr) external view returns (bool isCertified) {
        return guardianCertification[addr];
    }

    function setGuardianCertification(address addr, bool isCertified) external onlyFunctionalOwner onlyWhenActive {
        guardianCertification[addr] = isCertified;
        emit GuardianCertificationUpdate(addr, isCertified);
        electionsContract.guardianCertificationChanged(addr, isCertified);
    }

    IElections electionsContract;
    function refreshContracts() external {
        electionsContract = getElectionsContract();
    }

}
