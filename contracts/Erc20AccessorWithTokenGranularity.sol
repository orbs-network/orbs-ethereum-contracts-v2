pragma solidity 0.5.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ERC20AccessorWithTokenGranularity {

    uint constant TOKEN_GRANULARITY = 1000000000000000;

    function toUint48Granularity(uint256 v) internal pure returns (uint48) {
        return uint48(v / TOKEN_GRANULARITY);
    }

    function toUint256Granularity(uint48 v) internal pure returns (uint256) {
        return uint256(v) * TOKEN_GRANULARITY;
    }

    function transferFrom(IERC20 erc20, address sender, address recipient, uint48 amount) internal returns (bool) {
        return erc20.transferFrom(sender, recipient, toUint256Granularity(amount));
    }

    function transfer(IERC20 erc20, address recipient, uint48 amount) internal returns (bool) {
        return erc20.transfer(recipient, toUint256Granularity(amount));
    }

    function approve(IERC20 erc20, address spender, uint48 amount) internal returns (bool) {
        return erc20.approve(spender, toUint256Granularity(amount));
    }

}
