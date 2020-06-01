pragma solidity 0.5.16;


import "@openzeppelin/contracts/ownership/Ownable.sol";

/**
 * @title Claimable
 * @dev Extension for the Ownable contract, where the ownership needs to be claimed.
 * This allows the new owner to accept the transfer.
 */
contract Claimable is Ownable {
    address pendingOwner;
    /**
     * @dev Modifier throws if called by any account other than the pendingOwner.
     */
    modifier onlyPendingOwner() {
        require(msg.sender == pendingOwner, "Caller is not the pending owner");
        _;
    }
    /**
     * @dev Allows the current owner to set the pendingOwner address.
     * @param newOwner The address to transfer ownership to.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        pendingOwner = newOwner;
    }
    /**
     * @dev Allows the pendingOwner address to finalize the transfer.
     */
    function claimOwnership() external onlyPendingOwner {
        _transferOwnership(pendingOwner);
        pendingOwner = address(0);
    }
}
