pragma solidity 0.5.16;

/// @title An interface for Fee wallets that support bucket migration.
interface IMigratableFeesWallet {
    /// @dev receives a bucket start time and an amount
    function acceptBucketMigration(uint256 bucketStartTime, uint256 amount) external;
}
