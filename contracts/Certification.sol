pragma solidity 0.5.16;

import "./spec_interfaces/ICertification.sol";
import "./ContractRegistryAccessor.sol";
import "./Lockable.sol";
import "./interfaces/IElections.sol";
import "./ManagedContract.sol";

contract Certification is ICertification, ManagedContract {

    mapping (address => bool) guardianCertification;

    constructor(IContractRegistry _contractRegistry, address _registryAdmin) ManagedContract(_contractRegistry, _registryAdmin) public {}

    /*
     * External methods
     */

    function isGuardianCertified(address addr) external view returns (bool isCertified) {
        return guardianCertification[addr];
    }

    function setGuardianCertification(address addr, bool isCertified) external onlyFunctionalManager onlyWhenActive {
        guardianCertification[addr] = isCertified;
        emit GuardianCertificationUpdate(addr, isCertified);
        electionsContract.guardianCertificationChanged(addr, isCertified);
    }

    IElections electionsContract;
    function refreshContracts() external {
        electionsContract = IElections(getElectionsContract());
    }

}
