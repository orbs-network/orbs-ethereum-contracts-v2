// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestingERC20 is ERC20 {

    constructor() ERC20("Testing", "TEST") public {}

    function assign(address _account, uint256 _value) public {
        _burn(_account, balanceOf(_account));
        _mint(_account, _value);
    }
}
