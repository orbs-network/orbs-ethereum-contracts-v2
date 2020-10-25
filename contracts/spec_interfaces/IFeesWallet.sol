// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../spec_interfaces/IMigratableFeesWallet.sol";

/// @title Fees Wallet contract interface, manages the fee buckets
interface IFeesWallet {

    event FeesWithdrawnFromBucket(uint256 bucketId, uint256 withdrawn, uint256 total);
    event FeesAddedToBucket(uint256 bucketId, uint256 added, uint256 total);

    /*
     *   External methods
     */

    /// @dev Called by: subscriptions contract.
    /// Top-ups the fee pool with the given amount at the given rate (typically called by the subscriptions contract).
    function fillFeeBuckets(uint256 amount, uint256 monthlyRate, uint256 fromTimestamp) external;

    /// @dev collect fees from the buckets since the last call and transfers the amount back.
    /// Called by: only Rewards contract.
    function collectFees() external returns (uint256 collectedFees) /* onlyRewardsContract */;

    /// @dev Returns the amount of fees that are currently available for withdrawal
    function getOutstandingFees(uint256 currentTime) external view returns (uint256 outstandingFees);

    /*
     * General governance
     */

    event EmergencyWithdrawal(address addr, address token);

    /// @dev migrates the fees of bucket starting at startTimestamp.
    /// bucketStartTime must be a bucket's start time.
    /// Calls acceptBucketMigration in the destination contract.
    function migrateBucket(IMigratableFeesWallet destination, uint256 bucketStartTime) external /* onlyMigrationManager */;

    /// @dev Called by the old FeesWallet contract.
    /// Part of the IMigratableFeesWallet interface.
    function acceptBucketMigration(uint256 bucketStartTime, uint256 amount) external;

    /// @dev an emergency withdrawal enables withdrawal of all funds to an escrow account. To be use in emergencies only.
    function emergencyWithdraw(address token) external /* onlyMigrationManager */;

}
