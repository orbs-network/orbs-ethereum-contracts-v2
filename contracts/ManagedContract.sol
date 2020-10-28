// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./Lockable.sol";

contract ManagedContract is Lockable {

    constructor(IContractRegistry _contractRegistry, address _registryAdmin) Lockable(_contractRegistry, _registryAdmin) public {}

    function refreshContracts() virtual external {}

}