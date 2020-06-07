pragma solidity 0.5.16;

import "./WithClaimableMigrationOwnership.sol";


/**
 * @title Claimable
 * @dev Extension for the Ownable contract, where the ownership needs to be claimed.
 * This allows the new owner to accept the transfer.
 */
contract Lockable is WithClaimableMigrationOwnership{

    bool locked;

    function lock() external onlyMigrationOwner {
        locked = true;
    }

    function unlock() external onlyMigrationOwner {
        locked = false;
    }

    modifier onlyWhenActive() {
        require(!locked, "contract is locked for this operation");

        _;
    }
}
