// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;

interface ICommitteeListener {
    function committeeChanged(address[] calldata addrs, uint256[] calldata stakes) external;
}
