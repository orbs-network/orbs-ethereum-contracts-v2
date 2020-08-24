pragma solidity 0.5.16;

import "../ContractRegistryAccessor.sol";

contract ManagedContract is ContractRegistryAccessor {

    constructor(IContractRegistry _contractRegistry, address _registryManager) ContractRegistryAccessor(_contractRegistry, _registryManager) public {}

    uint public refreshContractsCount;

    function refreshContracts() external {
        refreshContractsCount++;
    }
}