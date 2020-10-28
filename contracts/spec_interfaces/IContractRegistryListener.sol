// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./IContractRegistry.sol";

interface IContractRegistryListener {

    function refreshContracts() external;

    function setContractRegistry(IContractRegistry newRegistry) external;

}
