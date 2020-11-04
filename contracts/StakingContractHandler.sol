// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./spec_interfaces/IStakingContractHandler.sol";
import "./IStakeChangeNotifier.sol";
import "./IStakingContract.sol";
import "./ManagedContract.sol";

contract StakingContractHandler is IStakingContractHandler, IStakeChangeNotifier, ManagedContract {

    IStakingContract stakingContract;
    struct Settings {
        IStakeChangeNotifier delegationsContract;
        bool notifyDelegations;
    }
    Settings settings;

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

    function stakeChange(address stakeOwner, uint256 amount, bool sign, uint256 updatedStake) external override onlyStakingContract {
        Settings memory _settings = settings;
        if (!_settings.notifyDelegations) {
            emit StakeChangeNotificationSkipped(stakeOwner);
            return;
        }

        _settings.delegationsContract.stakeChange(stakeOwner, amount, sign, updatedStake);
    }

    /// @dev Notifies of multiple stake change events.
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

    /// @dev Returns the stake of the specified stake owner (excluding unstaked tokens).
    /// @param stakeOwner address The address to check.
    /// @return uint256 The total stake.
    function getStakeBalanceOf(address stakeOwner) external override view returns (uint256) {
        return stakingContract.getStakeBalanceOf(stakeOwner);
    }

    /// @dev Returns the total amount staked tokens (excluding unstaked tokens).
    /// @return uint256 The total staked tokens of all stake owners.
    function getTotalStakedTokens() external override view returns (uint256) {
        return stakingContract.getTotalStakedTokens();
    }

    /*
    * Governance functions
    */

    function setNotifyDelegations(bool _notifyDelegations) external override onlyMigrationManager {
        settings.notifyDelegations = _notifyDelegations;
        emit NotifyDelegationsChanged(_notifyDelegations);
    }

    function getNotifyDelegations() external view override returns (bool) {
        return settings.notifyDelegations;
    }

    /*
     * Contracts topology / registry interface
     */

    function refreshContracts() external override {
        settings.delegationsContract = IStakeChangeNotifier(getDelegationsContract());
        stakingContract = IStakingContract(getStakingContract());
    }
}