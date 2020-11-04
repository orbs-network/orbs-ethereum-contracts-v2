// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./spec_interfaces/ICertification.sol";
import "./spec_interfaces/IElections.sol";
import "./ManagedContract.sol";

/// @title Certification contract
contract Certification is ICertification, ManagedContract {
    mapping(address => bool) guardianCertification;

    modifier onlyCertificationManager {
        require(isManager("certificationManager"), "sender is not the certification manager");

        _;
    }

    /// Constructor
    /// @param _contractRegistry is the contract registry address
    /// @param _registryAdmin is the registry admin address
    constructor(IContractRegistry _contractRegistry, address _registryAdmin) ManagedContract(_contractRegistry, _registryAdmin) public {}

    /*
     * External functions
     */

    /// Returns the certification status of a guardian
    /// @param guardian is the guardian to query
    function isGuardianCertified(address guardian) external override view returns (bool isCertified) {
        return guardianCertification[guardian];
    }

    /// Sets the guardian certification status
    /// @dev governance function called only by the certification manager
    /// @param guardian is the guardian to update
    /// @param isCertified bool indication whether the guardian is certified
    function setGuardianCertification(address guardian, bool isCertified) external override onlyCertificationManager onlyWhenActive {
        guardianCertification[guardian] = isCertified;
        emit GuardianCertificationUpdate(guardian, isCertified);
        electionsContract.guardianCertificationChanged(guardian, isCertified);
    }

    /*
     * Contracts topology / registry interface
     */

    IElections electionsContract;
    
    /// Refreshes the address of the other contracts the contract interacts with
    /// @dev called by the registry contract upon an update of a contract in the registry
    function refreshContracts() external override {
        electionsContract = IElections(getElectionsContract());
    }
}
