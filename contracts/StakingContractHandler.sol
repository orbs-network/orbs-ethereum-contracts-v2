// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./spec_interfaces/IStakingContractHandler.sol";
import "./IStakeChangeNotifier.sol";
import "./IStakingContract.sol";
import "./ManagedContract.sol";

/// @title Staking contract handler
/// @dev instantiated between the staking contract and delegation contract
/// @dev handles migration and governance for the staking contract notification
contract StakingContractHandler is IStakingContractHandler, IStakeChangeNotifier, ManagedContract {

    IStakingContract stakingContract;
    struct Settings {
        IStakeChangeNotifier delegationsContract;
        bool notifyDelegations;
    }
    Settings settings;

    /// @param _contractRegistry is the contract registry address
    /// @param _registryAdmin is the registry admin address
    constructor(IContractRegistry _contractRegistry, address _registryAdmin) public ManagedContract(_contractRegistry, _registryAdmin) {
        settings.notifyDelegations = true;
    }

    modifier onlyStakingContract() {
        require(msg.sender == address(stakingContract), "caller is not the staking contract");

        _;
    }

    /*
    * External functions
    */

    /// @dev Notifies of stake change event.
    /// @dev IStakeChangeNotifier interface function.
    /// @param _stakeOwner address The address of the subject stake owner.
    /// @param _amount uint256 The difference in the total staked amount.
    /// @param _sign bool The sign of the added (true) or subtracted (false) amount.
    /// @param _updatedStake uint256 The updated total staked amount.
    function stakeChange(address stakeOwner, uint256 amount, bool sign, uint256 updatedStake) external override onlyStakingContract {
        Settings memory _settings = settings;
        if (!_settings.notifyDelegations) {
            emit StakeChangeNotificationSkipped(stakeOwner);
            return;
        }

        _settings.delegationsContract.stakeChange(stakeOwner, amount, sign, updatedStake);
    }

    /// @dev Notifies of multiple stake change events.
    /// @dev IStakeChangeNotifier interface function.
    /// @param stakeOwners address[] The addresses of subject stake owners.
    /// @param amounts uint256[] The differences in total staked amounts.
    /// @param signs bool[] The signs of the added (true) or subtracted (false) amounts.
    /// @param updatedStakes uint256[] The updated total staked amounts.
    function stakeChangeBatch(address[] calldata stakeOwners, uint256[] calldata amounts, bool[] calldata signs, uint256[] calldata updatedStakes) external override onlyStakingContract {
        Settings memory _settings = settings;
        if (!_settings.notifyDelegations) {
            emit StakeChangeBatchNotificationSkipped(stakeOwners);
            return;
        }

        _settings.delegationsContract.stakeChangeBatch(stakeOwners, amounts, signs, updatedStakes);
    }

    /// @dev Notifies of stake migration event.
    /// @dev IStakeChangeNotifier interface function.
    /// @param stakeOwner address The address of the subject stake owner.
    /// @param amount uint256 The migrated amount.
    function stakeMigration(address stakeOwner, uint256 amount) external override onlyStakingContract {
        Settings memory _settings = settings;
        if (!_settings.notifyDelegations) {
            emit StakeMigrationNotificationSkipped(stakeOwner);
            return;
        }

        _settings.delegationsContract.stakeMigration(stakeOwner, amount);
    }

    /// Returns the stake of the specified stake owner (excluding unstaked tokens).
    /// @param _stakeOwner address The address to check.
    /// @return uint256 The total stake.
    function getStakeBalanceOf(address stakeOwner) external override view returns (uint256) {
        return stakingContract.getStakeBalanceOf(stakeOwner);
    }

    /// Returns the total amount staked tokens (excluding unstaked tokens).
    /// @return uint256 is the total staked tokens of all stake owners.
    function getTotalStakedTokens() external override view returns (uint256) {
        return stakingContract.getTotalStakedTokens();
    }

    /*
    * Governance functions
    */

    /// Sets notifications to the delegation contract
    /// @dev staking while notifications are disabled may lead to a discrepancy in the delegation data  
	/// @dev governance function called only by the migration manager
    /// @param notifyDelegations is a bool indicating whether to notify the delegation contract
    function setNotifyDelegations(bool _notifyDelegations) external override onlyMigrationManager {
        settings.notifyDelegations = _notifyDelegations;
        emit NotifyDelegationsChanged(_notifyDelegations);
    }

    /// Returns the notifications to the delegation contract status
    /// @return notifyDelegations is a bool indicating whether notifications are enabled
    function getNotifyDelegations() external override returns (bool) {
        return settings.notifyDelegations;
    }

    /*
     * Contracts topology / registry interface
     */

	/// Refreshes the address of the other contracts the contract interacts with
    /// @dev called by the registry contract upon an update of a contract in the registry
    function refreshContracts() external override {
        settings.delegationsContract = IStakeChangeNotifier(getDelegationsContract());
        stakingContract = IStakingContract(getStakingContract());
    }
}