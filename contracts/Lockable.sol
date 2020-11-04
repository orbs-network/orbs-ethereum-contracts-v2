// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./ContractRegistryAccessor.sol";
import "./spec_interfaces/ILockable.sol";

/// @title lockable contract
contract Lockable is ILockable, ContractRegistryAccessor {

    bool public locked;

    /// Constructor
    /// @param _contractRegistry is the contract registry address
    /// @param _registryAdmin is the registry admin address
    constructor(IContractRegistry _contractRegistry, address _registryAdmin) ContractRegistryAccessor(_contractRegistry, _registryAdmin) public {}

    /// Locks the contract to external non-governance function calls
    /// @dev governance function called only by the migration manager or an admin
    /// @dev typically called by the registry contract upon locking all managed contracts
    /// @dev getters and migration functions remain active also for locked contracts
    /// @dev checked by the onlyWhenActive modifier
    function lock() external override onlyMigrationManager {
        locked = true;
        emit Locked();
    }

    /// Unlocks the contract 
    /// @dev governance function called only by the migration manager or an admin
    /// @dev typically called by the registry contract upon unlocking all managed contracts
    function unlock() external override onlyMigrationManager {
        locked = false;
        emit Unlocked();
    }

    /// Returns the contract locking status
    /// @return isLocked is a bool indicating the contract is locked 
    function isLocked() external override view returns (bool) {
        return locked;
    }

    modifier onlyWhenActive() {
        require(!locked, "contract is locked for this operation");

        _;
    }
}
