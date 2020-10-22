// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;

import "./spec_interfaces/ICertification.sol";
import "./spec_interfaces/IElections.sol";
import "./ManagedContract.sol";

contract Certification is ICertification, ManagedContract {
    mapping(address => bool) guardianCertification;

    modifier onlyCertificationManager {
        require(isManager("certificationManager"), "sender is not the certification manager");

        _;
    }

    constructor(IContractRegistry _contractRegistry, address _registryAdmin) ManagedContract(_contractRegistry, _registryAdmin) public {}

    /*
     * External functions
     */

    function isGuardianCertified(address guardian) external override view returns (bool isCertified) {
        return guardianCertification[guardian];
    }

    function setGuardianCertification(address guardian, bool isCertified) external override onlyCertificationManager onlyWhenActive {
        guardianCertification[guardian] = isCertified;
        emit GuardianCertificationUpdate(guardian, isCertified);
        electionsContract.guardianCertificationChanged(guardian, isCertified);
    }

    /*
     * Contracts topology / registry interface
     */

    IElections electionsContract;
    function refreshContracts() external override {
        electionsContract = IElections(getElectionsContract());
    }
}
