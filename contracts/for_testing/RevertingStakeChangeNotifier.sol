// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../IStakeChangeNotifier.sol";

/// @title An interface for notifying of stake change events (e.g., stake, unstake, partial unstake, restate, etc.).
contract RevertingStakeChangeNotifier is IStakeChangeNotifier{
    function stakeChange(address, uint256, bool, uint256) external override {
        revert("RevertingStakeChangeNotifier: stakeChange reverted");
    }

    function stakeChangeBatch(address[] calldata, uint256[] calldata, bool[] calldata,
        uint256[] calldata) external override {
        revert("RevertingStakeChangeNotifier: stakeChangeBatch reverted");
    }

    function stakeMigration(address, uint256) external override {
        revert("RevertingStakeChangeNotifier: stakeMigration reverted");
    }
}
