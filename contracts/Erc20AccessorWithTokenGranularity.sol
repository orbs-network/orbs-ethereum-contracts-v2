pragma solidity 0.5.16;

import "@openzeppelin/contracts/ownership/Ownable.sol";
import "./spec_interfaces/IContractRegistry.sol";
import "./spec_interfaces/IProtocol.sol";
import "./spec_interfaces/ICommittee.sol";
import "./interfaces/IElections.sol";
import "./spec_interfaces/IValidatorsRegistration.sol";
import "./spec_interfaces/ICompliance.sol";
import "./spec_interfaces/ISubscriptions.sol";
import "./spec_interfaces/IDelegation.sol";
import "./interfaces/IRewards.sol";

contract ERC20AccessorWithTokenGranularity {

    uint constant TOKEN_GRANULARITY = 1000000000000000;

    function toUint48Granularity(uint256 v) internal view returns (uint48) {
        return uint48(v / TOKEN_GRANULARITY);
    }

    function toUint256Granularity(uint48 v) internal view returns (uint256) {
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
