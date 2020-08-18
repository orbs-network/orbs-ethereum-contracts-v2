pragma solidity 0.5.16;

import "../ContractRegistryAccessor.sol";

contract ManagedContract is ContractRegistryAccessor {

    constructor(IContractRegistry _contractRegistry, address _registryManager) ContractRegistryAccessor(_contractRegistry, _registryManager) public {}

    uint public refreshContractsCount;
    uint public refreshManagersCount;

    mapping (uint => string) public notifiedRole;
    mapping (uint => address) public notifiedManager;

    function refreshContracts() external {
        refreshContractsCount++;
    }

    function refreshManagers(string calldata role, address newManager) external {
        refreshManagersCount++;
        notifiedRole[refreshManagersCount] = role;
        notifiedManager[refreshManagersCount] = newManager;
    }
}