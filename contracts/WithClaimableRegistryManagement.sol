pragma solidity 0.5.16;


import "@openzeppelin/contracts/GSN/Context.sol";

/**
 * @title Claimable
 * @dev Extension for the Ownable contract, where the ownership needs to be claimed.
 * This allows the new owner to accept the transfer.
 */
contract WithClaimableRegistryManagement is Context {
    address private _registryManager;
    address pendingRegistryManager;

    event RegistryManagementTransferred(address indexed previousRegistryManager, address indexed newRegistryManager);

    /**
     * @dev Initializes the contract setting the deployer as the initial registryRegistryManager.
     */
    constructor () internal {
        address msgSender = _msgSender();
        _registryManager = msgSender;
        emit RegistryManagementTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current registryManager.
     */
    function registryManager() public view returns (address) {
        return _registryManager;
    }

    /**
     * @dev Throws if called by any account other than the registryManager.
     */
    modifier onlyRegistryManager() {
        require(isRegistryManager(), "WithClaimableRegistryManagement: caller is not the registryManager");
        _;
    }

    /**
     * @dev Returns true if the caller is the current registryManager.
     */
    function isRegistryManager() public view returns (bool) {
        return _msgSender() == _registryManager;
    }

    /**
     * @dev Leaves the contract without registryManager. It will not be possible to call
     * `onlyManager` functions anymore. Can only be called by the current registryManager.
     *
     * NOTE: Renouncing registryManagement will leave the contract without an registryManager,
     * thereby removing any functionality that is only available to the registryManager.
     */
    function renounceRegistryManagement() public onlyRegistryManager {
        emit RegistryManagementTransferred(_registryManager, address(0));
        _registryManager = address(0);
    }

    /**
     * @dev Transfers registryManagement of the contract to a new account (`newManager`).
     */
    function _transferRegistryManagement(address newRegistryManager) internal {
        require(newRegistryManager != address(0), "RegistryManager: new registryManager is the zero address");
        emit RegistryManagementTransferred(_registryManager, newRegistryManager);
        _registryManager = newRegistryManager;
    }

    /**
     * @dev Modifier throws if called by any account other than the pendingManager.
     */
    modifier onlyPendingRegistryManager() {
        require(msg.sender == pendingRegistryManager, "Caller is not the pending registryManager");
        _;
    }
    /**
     * @dev Allows the current registryManager to set the pendingManager address.
     * @param newRegistryManager The address to transfer registryManagement to.
     */
    function transferRegistryManagement(address newRegistryManager) public onlyRegistryManager {
        pendingRegistryManager = newRegistryManager;
    }

    /**
     * @dev Allows the pendingRegistryManager address to finalize the transfer.
     */
    function claimRegistryManagement() external onlyPendingRegistryManager {
        _transferRegistryManagement(pendingRegistryManager);
        pendingRegistryManager = address(0);
    }
}
