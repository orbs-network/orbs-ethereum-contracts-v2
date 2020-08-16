pragma solidity 0.5.16;


import "@openzeppelin/contracts/GSN/Context.sol";

/**
 * @title Claimable
 * @dev Extension for the Ownable contract, where the ownership needs to be claimed.
 * This allows the new owner to accept the transfer.
 */
contract WithClaimableFunctionalOwnership is Context{
    address private _functionalOwner;
    address pendingFunctionalOwner;

    event FunctionalOwnershipTransferred(address indexed previousFunctionalOwner, address indexed newFunctionalOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial functionalFunctionalOwner.
     */
    constructor () internal {
        address msgSender = _msgSender();
        _functionalOwner = msgSender;
        emit FunctionalOwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current functionalOwner.
     */
    function functionalOwner() public view returns (address) {
        return _functionalOwner;
    }

    /**
     * @dev Throws if called by any account other than the functionalOwner.
     */
    modifier onlyFunctionalManager() {
        require(isFunctionalOwner(), "WithClaimableFunctionalOwnership: caller is not the functionalOwner");
        _;
    }

    /**
     * @dev Returns true if the caller is the current functionalOwner.
     */
    function isFunctionalOwner() public view returns (bool) {
        return _msgSender() == _functionalOwner;
    }

    /**
     * @dev Leaves the contract without functionalOwner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current functionalOwner.
     *
     * NOTE: Renouncing functionalOwnership will leave the contract without an functionalOwner,
     * thereby removing any functionality that is only available to the functionalOwner.
     */
    function renounceFunctionalOwnership() public onlyFunctionalManager {
        emit FunctionalOwnershipTransferred(_functionalOwner, address(0));
        _functionalOwner = address(0);
    }

    /**
     * @dev Transfers functionalOwnership of the contract to a new account (`newOwner`).
     */
    function _transferFunctionalOwnership(address newFunctionalOwner) internal {
        require(newFunctionalOwner != address(0), "FunctionalOwner: new functionalOwner is the zero address");
        emit FunctionalOwnershipTransferred(_functionalOwner, newFunctionalOwner);
        _functionalOwner = newFunctionalOwner;
    }

    /**
     * @dev Modifier throws if called by any account other than the pendingOwner.
     */
    modifier onlyPendingFunctionalOwner() {
        require(msg.sender == pendingFunctionalOwner, "Caller is not the pending functionalOwner");
        _;
    }
    /**
     * @dev Allows the current functionalOwner to set the pendingOwner address.
     * @param newFunctionalOwner The address to transfer functionalOwnership to.
     */
    function transferFunctionalOwnership(address newFunctionalOwner) public onlyFunctionalManager {
        pendingFunctionalOwner = newFunctionalOwner;
    }
    /**
     * @dev Allows the pendingFunctionalOwner address to finalize the transfer.
     */
    function claimFunctionalOwnership() external onlyPendingFunctionalOwner {
        _transferFunctionalOwnership(pendingFunctionalOwner);
        pendingFunctionalOwner = address(0);
    }
}
