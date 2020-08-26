pragma solidity 0.5.16;

import "../ContractRegistryAccessor.sol";
import "../ManagedContract.sol";

contract ManagedContractTest is ManagedContract {

    constructor(IContractRegistry _contractRegistry, address _registryManager) ManagedContract(_contractRegistry, _registryManager) public {}

    uint public refreshContractsCount;

    function refreshContracts() external {
        refreshContractsCount++;
    }

    function adminOp() external view onlyAdmin {}
    function migrationManagerOp() external view onlyMigrationManager {}
    function nonExistentManagerOp() external view {
        require(isManager("nonexistentrole"), "sender is not the manager");
    }

}