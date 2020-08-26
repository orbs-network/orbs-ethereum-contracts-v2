pragma solidity 0.5.16;

contract Initializable {

    address private _initializationAdmin;

    event InitializationComplete();

    constructor() public{
        _initializationAdmin = msg.sender;
    }

    function initializationAdmin() public view returns (address) {
        return _initializationAdmin;
    }

    function initializationComplete() external {
        require(msg.sender == initializationAdmin(), "caller is not the initialization manager");
        _initializationAdmin = address(0);
        emit InitializationComplete();
    }

    function isInitializationComplete() public view returns (bool) {
        return _initializationAdmin == address(0);
    }

}