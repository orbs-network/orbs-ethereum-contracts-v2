// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./IContractRegistry.sol";

interface IContractRegistryAccessor {

    /// Sets the contract registry address
    /// @dev governance function called only by an admin
	/// @param newRegistry is the new registry contract 
    function setContractRegistry(IContractRegistry newRegistry) external /* onlyAdmin */;

    /// Returns the contract registry address
    /// @return contractRegistry is the contract registry address
    function getContractRegistry() external view returns (IContractRegistry contractRegistry);

    function setRegistryAdmin(address _registryAdmin) external /* onlyInitializationAdmin */;

}
