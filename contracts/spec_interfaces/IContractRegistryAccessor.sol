// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./IContractRegistry.sol";

interface IContractRegistryAccessor {

    /// Refreshes the address of the other contracts the contract interacts with
    /// @dev called by the registry contract upon an update of a contract in the registry
    function refreshContracts() external;

    /// Sets the contract registry address
    /// @dev governance function called only by an admin
	/// @param newRegistry is the new registry contract 
    function setContractRegistry(IContractRegistry newRegistry) external /* onlyAdmin */;

    /// Returns the contract registry that the contract is set to use
	/// @return contractRegistry is the registry contract address
    function getContractRegistry() external view returns (IContractRegistry);

}
