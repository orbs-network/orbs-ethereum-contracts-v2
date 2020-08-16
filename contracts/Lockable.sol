pragma solidity 0.5.16;

import "./ContractRegistryAccessor.sol";

contract Lockable is ContractRegistryAccessor {

    bool public locked;

    event Locked();
    event Unlocked();

    modifier onlyLockOwner() {
        require(msg.sender == migrationOwner() || msg.sender == address(contractRegistry), "caller is not a lock owner");

        _;
    }

    constructor(IContractRegistry _contractRegistry) ContractRegistryAccessor(_contractRegistry) public {}

    function lock() external onlyLockOwner {
        locked = true;
        emit Locked();
    }

    function unlock() external onlyLockOwner {
        locked = false;
        emit Unlocked();
    }

    modifier onlyWhenActive() {
        require(!locked, "contract is locked for this operation");

        _;
    }
}
