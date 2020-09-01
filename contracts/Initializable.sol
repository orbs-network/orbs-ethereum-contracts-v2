pragma solidity 0.5.16;

contract Initializable {

    address private _initializationManager;

    event InitializationComplete();

    constructor() public{
        _initializationManager = msg.sender;
    }

    function initializationManager() public view returns (address) {
        return _initializationManager;
    }

    function initializationComplete() external {
        require(msg.sender == initializationManager(), "caller is not the initialization manager");
        _initializationManager = address(0);
        emit InitializationComplete();
    }

    function isInitializationComplete() public view returns (bool) {
        return _initializationManager == address(0);
    }

}