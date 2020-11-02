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

    /// Top-ups the fee pool with the given amount at the given rate
    /// @dev Called by: subscriptions contract. (not enforced)
    /// @dev fills the rewards in 30 days buckets based on the monthlyRate
    /// @param amount is the amount to fill
    /// @param monthlyRate is the monthly rate
    /// @param fromTimestamp is the to start fill the buckets, determines the first bucket to fill and the amount filled in the first bucket.
    function fillFeeBuckets(uint256 amount, uint256 monthlyRate, uint256 fromTimestamp) external;

    /// Collect fees from the buckets since the last call and transfers the amount back.
    /// @dev Called by: only FeesAndBootstrapRewards contract
    /// @dev The amount to collect may be queried before collect by calling getOutstandingFees
    /// @return collectedFees the amount of fees collected and transferred
    function collectFees() external returns (uint256 collectedFees) /* onlyRewardsContract */;

    /// Returns the amount of fees that are currently available for withdrawal
    /// @param currentTime is the time to check the pending fees for
    /// @return outstandingFees is the amount of pending fees to collect at time currentTime
    function getOutstandingFees(uint256 currentTime) external view returns (uint256 outstandingFees);

    /*
     * General governance
     */

    event EmergencyWithdrawal(address addr, address token);

    /// Migrates the fees of bucket starting at startTimestamp.
	/// @dev governance function called only by the migration manager
    /// @dev Calls acceptBucketMigration in the destination contract.
    /// @param destination is the address of the new FeesWallet contract
    /// @param bucketStartTime is the start time of the bucket to migration, must be a bucket's valid start time
    function migrateBucket(IMigratableFeesWallet destination, uint256 bucketStartTime) external /* onlyMigrationManager */;

    /// Accepts a bucket fees from a old fees wallet as part of a migration
    /// @dev Called by the old FeesWallet contract.
    /// @dev Part of the IMigratableFeesWallet interface.
    /// @dev assumes the caller approved the amount prior to calling
    /// @param bucketStartTime is the start time of the bucket to migration, must be a bucket's valid start time
    /// @param amount is the amount to migrate (transfer) to the bucket
    function acceptBucketMigration(uint256 bucketStartTime, uint256 amount) external;

    /// Emergency withdraw the contract funds
	/// @dev governance function called only by the migration manager
    /// @dev used in emergencies only, where migrateBucket is not a suitable solution
    /// @param erc20 is the erc20 address of the token to withdraw
    function emergencyWithdraw(address erc20) external /* onlyMigrationManager */;

}
