// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./IContractRegistry.sol";

interface IContractRegistryListener {

    /// Refreshes the address of the other contracts the contract interacts with
    /// @dev called by the registry contract upon an update of a contract in the registry
    function refreshContracts() external;

    /// Sets the contract registry address
    /// @dev governance function called only by an admin
    function setContractRegistry(IContractRegistry newRegistry) external /* onlyAdmin */;

}
