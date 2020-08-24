pragma solidity 0.5.16;

/// @title An interface for staking contracts.
interface IStakingContractHandler {
    event StakeChangeNotificationFailed(address stakeOwner);
    event StakeChangeBatchNotificationFailed(address[] stakeOwners);
    event StakeMigrationNotificationFailed(address stakeOwner);

    /// @dev Returns the stake of the specified stake owner (excluding unstaked tokens).
    /// @param _stakeOwner address The address to check.
    /// @return uint256 The total stake.
    function getStakeBalanceOf(address _stakeOwner) external view returns (uint256);

    /// @dev Returns the total amount staked tokens (excluding unstaked tokens).
    /// @return uint256 The total staked tokens of all stake owners.
    function getTotalStakedTokens() external view returns (uint256);

}
