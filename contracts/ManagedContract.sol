pragma solidity 0.5.16;

import "./Lockable.sol";

contract ManagedContract is Lockable {

    constructor(IContractRegistry _contractRegistry, address _registryManager) Lockable(_contractRegistry, _registryManager) public {}

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

}