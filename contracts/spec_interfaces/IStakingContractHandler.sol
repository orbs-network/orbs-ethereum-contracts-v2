// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

/// @title Staking contract handler contract interface in addition to IStakeChangeNotifier
interface IStakingContractHandler {
    event StakeChangeNotificationSkipped(address indexed stakeOwner);
    event StakeChangeBatchNotificationSkipped(address[] stakeOwners);
    event StakeMigrationNotificationSkipped(address indexed stakeOwner);

    /*
    * External functions
    */

    /// Returns the stake of the specified stake owner (excluding unstaked tokens).
    /// @param stakeOwner address The address to check.
    /// @return uint256 The total stake.
    function getStakeBalanceOf(address stakeOwner) external view returns (uint256);

    /// Returns the total amount staked tokens (excluding unstaked tokens).
    /// @return uint256 is the total staked tokens of all stake owners.
    function getTotalStakedTokens() external view returns (uint256);

    /*
    * Governance functions
    */

    event NotifyDelegationsChanged(bool notifyDelegations);

    /// Sets notifications to the delegation contract
    /// @dev staking while notifications are disabled may lead to a discrepancy in the delegation data  
	/// @dev governance function called only by the migration manager
    /// @param notifyDelegations is a bool indicating whether to notify the delegation contract
    function setNotifyDelegations(bool notifyDelegations) external; /* onlyMigrationManager */

    /// Returns the notifications to the delegation contract status
    /// @return notifyDelegations is a bool indicating whether notifications are enabled
    function getNotifyDelegations() external returns (bool);
}
