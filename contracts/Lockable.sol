// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./ContractRegistryAccessor.sol";
import "./spec_interfaces/ILockable.sol";

contract Lockable is ILockable, ContractRegistryAccessor {

    bool public locked;

    constructor(IContractRegistry _contractRegistry, address _registryAdmin) ContractRegistryAccessor(_contractRegistry, _registryAdmin) public {}

    function lock() external override onlyMigrationManager {
        locked = true;
        emit Locked();
    }

    function unlock() external override onlyMigrationManager {
        locked = false;
        emit Unlocked();
    }

    function isLocked() external override view returns (bool) {
        return locked;
    }

    modifier onlyWhenActive() {
        require(!locked, "contract is locked for this operation");

        _;
    }
}
