// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;

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

    function isGuardianCertified(address addr) external override view returns (bool isCertified) {
        return guardianCertification[addr];
    }

    function getGuardiansCertification(address[] calldata addrs) external override view returns (bool[] memory certification) {
        certification = new bool[](addrs.length);
        for (uint i = 0; i < addrs.length; i++) {
            certification[i] = guardianCertification[addrs[i]];
        }
    }

    function setGuardianCertification(address addr, bool isCertified) external override onlyFunctionalManager onlyWhenActive {
        guardianCertification[addr] = isCertified;
        emit GuardianCertificationUpdate(addr, isCertified);
        electionsContract.guardianCertificationChanged(addr, isCertified);
    }

    IElections electionsContract;
    function refreshContracts() external override {
        electionsContract = IElections(getElectionsContract());
    }

}
