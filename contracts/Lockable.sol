pragma solidity 0.5.16;

import "./ContractRegistryAccessor.sol";
import "./spec_interfaces/ILockable.sol";

contract Lockable is ILockable, ContractRegistryAccessor {

    bool public locked;

    modifier onlyLockOwner() {
        require(msg.sender == registryAdmin() || msg.sender == address(contractRegistry), "caller is not a lock owner");

        _;
    }

    constructor(IContractRegistry _contractRegistry, address _registryAdmin) ContractRegistryAccessor(_contractRegistry, _registryAdmin) public {}

    function lock() external onlyLockOwner {
        locked = true;
        emit Locked();
    }

    function unlock() external onlyLockOwner {
        locked = false;
        emit Unlocked();
    }

    function isLocked() external view returns (bool) {
        return locked;
    }

    modifier onlyWhenActive() {
        require(!locked, "contract is locked for this operation");

        _;
    }
}
