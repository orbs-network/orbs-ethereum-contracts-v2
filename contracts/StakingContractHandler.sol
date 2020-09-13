// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;

import "./ContractRegistryAccessor.sol";
import "./spec_interfaces/IStakingContractHandler.sol";
import "./IStakeChangeNotifier.sol";
import "./IStakingContract.sol";
import "./Lockable.sol";
import "./ManagedContract.sol";

contract StakingContractHandler is IStakingContractHandler, IStakeChangeNotifier, ManagedContract {

    uint constant NOTIFICATION_GAS_LIMIT = 5000000;

    bool public notifyDelegations = true;

    constructor(IContractRegistry _contractRegistry, address _registryAdmin) public ManagedContract(_contractRegistry, _registryAdmin) {}

    modifier onlyStakingContract() {
        require(msg.sender == address(getStakingContract()), "caller is not the staking contract");

        _;
    }

    function stakeChange(address _stakeOwner, uint256 _amount, bool _sign, uint256 _updatedStake) external override onlyStakingContract {
        if (!notifyDelegations) {
            emit StakeChangeNotificationSkipped(_stakeOwner);
            return;
        }

        delegationsContract.stakeChange(_stakeOwner, _amount, _sign, _updatedStake);
    }

    /// @dev Notifies of multiple stake change events.
    /// @param _stakeOwners address[] The addresses of subject stake owners.
    /// @param _amounts uint256[] The differences in total staked amounts.
    /// @param _signs bool[] The signs of the added (true) or subtracted (false) amounts.
    /// @param _updatedStakes uint256[] The updated total staked amounts.
    function stakeChangeBatch(address[] calldata _stakeOwners, uint256[] calldata _amounts, bool[] calldata _signs, uint256[] calldata _updatedStakes) external override onlyStakingContract {
        if (!notifyDelegations) {
            emit StakeChangeBatchNotificationSkipped(_stakeOwners);
            return;
        }

        delegationsContract.stakeChangeBatch(_stakeOwners, _amounts, _signs, _updatedStakes);
    }

    /// @dev Notifies of stake migration event.
    /// @param _stakeOwner address The address of the subject stake owner.
    /// @param _amount uint256 The migrated amount.
    function stakeMigration(address _stakeOwner, uint256 _amount) external override onlyStakingContract {
        if (!notifyDelegations) {
            emit StakeMigrationNotificationSkipped(_stakeOwner);
            return;
        }

        delegationsContract.stakeMigration(_stakeOwner, _amount);
    }

    /// @dev Returns the stake of the specified stake owner (excluding unstaked tokens).
    /// @param _stakeOwner address The address to check.
    /// @return uint256 The total stake.
    function getStakeBalanceOf(address _stakeOwner) external override view returns (uint256) {
        return stakingContract.getStakeBalanceOf(_stakeOwner);
    }

    /// @dev Returns the total amount staked tokens (excluding unstaked tokens).
    /// @return uint256 The total staked tokens of all stake owners.
    function getTotalStakedTokens() external override view returns (uint256) {
        return stakingContract.getTotalStakedTokens();
    }

    IStakeChangeNotifier delegationsContract;
    IStakingContract stakingContract;
    function refreshContracts() external override {
        delegationsContract = IStakeChangeNotifier(getDelegationsContract());
        stakingContract = IStakingContract(getStakingContract());
    }

    function setNotifyDelegations(bool _notifyDelegations) external override onlyMigrationManager {
        notifyDelegations = _notifyDelegations;
        emit NotifyDelegationsChanged(_notifyDelegations);
    }

}