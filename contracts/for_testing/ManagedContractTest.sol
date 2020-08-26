pragma solidity 0.5.16;

import "../ContractRegistryAccessor.sol";
import "../ManagedContract.sol";

contract ManagedContractTest is ManagedContract {

    constructor(IContractRegistry _contractRegistry, address _registryAdmin) ManagedContract(_contractRegistry, _registryAdmin) public {}

    uint public refreshContractsCount;

    address public delegations;
    function refreshContracts() external {
        refreshContractsCount++;
        delegations = getDelegationsContract();
    }

    function adminOp() external view onlyAdmin {}
    function migrationManagerOp() external view onlyMigrationManager {}
    function nonExistentManagerOp() external view {
        require(isManager("nonexistentrole"), "sender is not the manager");
    }

}