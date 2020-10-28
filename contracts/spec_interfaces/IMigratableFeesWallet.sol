// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

/// @title An interface for Fee wallets that support bucket migration.
interface IMigratableFeesWallet {

    /// Accepts a bucket fees from a old fees wallet as part of a migration
    /// @dev Called by the old FeesWallet contract.
    /// @dev Part of the IMigratableFeesWallet interface.
    /// @dev assumes the caller approved the transfer of the amount prior to calling
    /// @param bucketStartTime is the start time of the bucket to migration, must be a bucket's valid start time
    /// @param amount is the amount to migrate (transfer) to the bucket
    function acceptBucketMigration(uint256 bucketStartTime, uint256 amount) external;
}
