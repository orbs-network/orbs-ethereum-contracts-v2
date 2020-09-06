// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;

import "./spec_interfaces/IContractRegistry.sol";

interface IContractRegistryListener {

    function refreshContracts() external;

    function setContractRegistry(IContractRegistry newRegistry) external;

}
