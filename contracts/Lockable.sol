pragma solidity 0.5.16;

import "./WithClaimableMigrationOwnership.sol";


/**
 * @title Claimable
 * @dev Extension for the Ownable contract, where the ownership needs to be claimed.
 * This allows the new owner to accept the transfer.
 */
contract Lockable is WithClaimableMigrationOwnership {

    bool public locked;

    event Locked();
    event Unlocked();

    function lock() external onlyMigrationOwner {
        locked = true;
        emit Locked();
    }

    function unlock() external onlyMigrationOwner {
        locked = false;
        emit Unlocked();
    }

    modifier onlyWhenActive() {
        require(!locked, "contract is locked for this operation");

        _;
    }
}
