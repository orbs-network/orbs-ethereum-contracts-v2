// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;

contract Initializable {

    address private _initializationAdmin;

    event InitializationComplete();

    modifier onlyInitializationAdmin() {
        require(msg.sender == initializationAdmin(), "sender is not the initialization admin");

        _;
    }

    constructor() public{
        _initializationAdmin = msg.sender;
    }

    function initializationAdmin() public view returns (address) {
        return _initializationAdmin;
    }

    function initializationComplete() external onlyInitializationAdmin {
        _initializationAdmin = address(0);
        emit InitializationComplete();
    }

    function isInitializationComplete() public view returns (bool) {
        return _initializationAdmin == address(0);
    }

}