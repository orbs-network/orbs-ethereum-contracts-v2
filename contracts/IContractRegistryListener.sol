pragma solidity 0.5.16;

import "./spec_interfaces/IContractRegistry.sol";

interface IContractRegistryListener {

    function refreshContracts() external;

    function setContractRegistry(IContractRegistry newRegistry) external;

}
