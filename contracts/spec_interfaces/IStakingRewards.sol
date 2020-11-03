// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

/// @title Staking rewards contract interface
interface IStakingRewards {

    event DelegatorStakingRewardsAssigned(address indexed delegator, uint256 amount, uint256 totalAwarded, address guardian, uint256 delegatorRewardsPerToken, uint256 delegatorRewardsPerTokenDelta);
    event GuardianStakingRewardsAssigned(address indexed guardian, uint256 amount, uint256 totalAwarded, uint256 delegatorRewardsPerToken, uint256 delegatorRewardsPerTokenDelta, uint256 stakingRewardsPerWeight, uint256 stakingRewardsPerWeightDelta);
    event StakingRewardsClaimed(address indexed addr, uint256 claimedDelegatorRewards, uint256 claimedGuardianRewards, uint256 totalClaimedDelegatorRewards, uint256 totalClaimedGuardianRewards);
    event StakingRewardsAllocated(uint256 allocatedRewards, uint256 stakingRewardsPerWeight);
    event GuardianDelegatorsStakingRewardsPercentMilleUpdated(address indexed guardian, uint256 delegatorsStakingRewardsPercentMille);

    /*
     * External functions
     */

    /// Returns the currently reward balance of the given address.
    /// @dev calculates the up to date balances (differ from the state)
    /// @param addr is the address to query
    /// @return delegatorStakingRewardsBalance the rewards awarded to the guardian role
    /// @return guardianStakingRewardsBalance the rewards awarded to the guardian role
    function getStakingRewardsBalance(address addr) external view returns (uint256 delegatorStakingRewardsBalance, uint256 guardianStakingRewardsBalance);

    /// Claims the staking rewards balance of an addr, staking the rewards
    /// @dev Claimed rewards are staked in the staking contract using the distributeRewards interface
    /// @dev includes the rewards for both the delegator and guardian roles
    /// @dev calculates the up to date rewards prior to distribute them to the staking contract
    /// @param addr is the address to claim rewards for
    function claimStakingRewards(address addr) external;

    /// Returns the current global staking rewards state
    /// @dev calculated to the latest block, may differ from the state read
    /// @return stakingRewardsPerWeight is the potential reward per 1E18 (TOKEN_BASE) committee weight assigned to a guardian was in the committee from day zero
    /// @return unclaimedStakingRewards is the of tokens that were assigned to participants and not claimed yet
    function getStakingRewardsState() external view returns (
        uint96 stakingRewardsPerWeight,
        uint96 unclaimedStakingRewards
    );

    /// Returns the current guardian staking rewards state
    /// @dev calculated to the latest block, may differ from the state read
    /// @dev notice that the guardian rewards are the rewards for the guardian role as guardian and do not include delegation rewards
    /// @dev use getDelegatorStakingRewardsData to get the guardian's rewards as delegator
    /// @param guardian is the guardian to query
    /// @return balance is the staking rewards balance for the guardian role
    /// @return claimed is the staking rewards for the guardian role that were claimed
    /// @return delegatorRewardsPerToken is the potential reward per token (1E18 units) assigned to a guardian's delegator that delegated from day zero
    /// @return delegatorRewardsPerTokenDelta is the increment in delegatorRewardsPerToken since the last guardian update
    /// @return lastStakingRewardsPerWeight is the up to date stakingRewardsPerWeight used for the guardian state calculation
    /// @return stakingRewardsPerWeightDelta is the increment in stakingRewardsPerWeight since the last guardian update
    function getGuardianStakingRewardsData(address guardian) external view returns (
        uint256 balance,
        uint256 claimed,
        uint256 delegatorRewardsPerToken,
        uint256 delegatorRewardsPerTokenDelta,
        uint256 lastStakingRewardsPerWeight,
        uint256 stakingRewardsPerWeightDelta
    );

    /// Returns the current delegator staking rewards state
    /// @dev calculated to the latest block, may differ from the state read
    /// @param delegator is the delegator to query
    /// @return balance is the staking rewards balance for the delegator role
    /// @return claimed is the staking rewards for the delegator role that were claimed
    /// @return guardian is the guardian the delegator delegated to receiving a portion of the guardian staking rewards
    /// @return lastDelegatorRewardsPerToken is the up to date delegatorRewardsPerToken used for the delegator state calculation
    /// @return delegatorRewardsPerTokenDelta is the increment in delegatorRewardsPerToken since the last delegator update
    function getDelegatorStakingRewardsData(address delegator) external view returns (
        uint256 balance,
        uint256 claimed,
        address guardian,
        uint256 lastDelegatorRewardsPerToken,
        uint256 delegatorRewardsPerTokenDelta
    );

    /// Returns an estimation for the delegator and guardian staking rewards for a given duration
    /// @dev the returned value is an estimation, assuming no change in the PoS state
    /// @dev the period calculated for start from the current block time until the current time + duration.
    /// @param addr is the address to estimate rewards for
    /// @param duration is the duration to calculate for in seconds
    /// @return estimatedDelegatorStakingRewards is the estimated reward for the delegator role
    /// @return estimatedGuardianStakingRewards is the estimated reward for the guardian role
    function estimateFutureRewards(address addr, uint256 duration) external view returns (
        uint256 estimatedDelegatorStakingRewards,
        uint256 estimatedGuardianStakingRewards
    );

    /// Sets ths guardian's delegators staking reward portion
    /// @dev by default uses the defaultDelegatorsStakingRewardsPercentMille
    /// @param delegatorRewardsPercentMille is the delegators portion in percent-mille (0 - maxDelegatorsStakingRewardsPercentMille)
    function setGuardianDelegatorsStakingRewardsPercentMille(uint32 delegatorRewardsPercentMille) external;

    /// Returns a guardian's delegators staking reward portion
    /// @dev If not explicitly set, returns the defaultDelegatorsStakingRewardsPercentMille
    /// @return delegatorRewardsRatioPercentMille is the delegators portion in percent-mille
    function getGuardianDelegatorsStakingRewardsPercentMille(address guardian) external view returns (uint256 delegatorRewardsRatioPercentMille);

    /// Returns the amount of ORBS tokens in the staking rewards wallet allocated to staking rewards
    /// @dev The staking wallet balance must always larger than the allocated value
    /// @return allocated is the amount of tokens allocated in the staking rewards wallet
    function getStakingRewardsWalletAllocatedTokens() external view returns (uint256 allocated);

    /// Returns the current annual staking reward rate
    /// @dev calculated based on the current total committee weight
    /// @return annualRate is the current staking reward rate in percent-mille
    function getCurrentStakingRewardsRatePercentMille() external view returns (uint256 annualRate);

    /// Notifies an expected change in the committee membership of the guardian
    /// @dev Called only by: the Committee contract
    /// @dev called upon expected change in the committee membership of the guardian
    /// @dev triggers update of the global rewards state and the guardian rewards state
    /// @dev updates the rewards state based on the committee state prior to the change
    /// @param guardian is the guardian who's committee membership is updated
    /// @param weight is the weight of the guardian prior to the change
    /// @param totalCommitteeWeight is the total committee weight prior to the change
    /// @param inCommittee indicates whether the guardian was in the committee prior to the change
    /// @param inCommitteeAfter indicates whether the guardian is in the committee after the change
    function committeeMembershipWillChange(address guardian, uint256 weight, uint256 totalCommitteeWeight, bool inCommittee, bool inCommitteeAfter) external /* onlyCommitteeContract */;

    /// Notifies an expected change in a delegator and his guardian delegation state
    /// @dev Called only by: the Delegation contract
    /// @dev called upon expected change in a delegator's delegation state
    /// @dev triggers update of the global rewards state, the guardian rewards state and the delegator rewards state
    /// @dev on delegation change, updates also the new guardian and the delegator's lastDelegatorRewardsPerToken accordingly
    /// @param guardian is the delegator's guardian prior to the change
    /// @param guardianDelegatedStake is the delegated stake of the delegator's guardian prior to the change
    /// @param delegator is the delegator about to change delegation state
    /// @param delegatorStake is the stake of the delegator
    /// @param nextGuardian is the delegator's guardian after to the change
    /// @param nextGuardianDelegatedStake is the delegated stake of the delegator's guardian after to the change
    function delegationWillChange(address guardian, uint256 guardianDelegatedStake, address delegator, uint256 delegatorStake, address nextGuardian, uint256 nextGuardianDelegatedStake) external /* onlyDelegationsContract */;

    /*
     * Governance functions
     */

    event AnnualStakingRewardsRateChanged(uint256 annualRateInPercentMille, uint256 annualCap);
    event DefaultDelegatorsStakingRewardsChanged(uint32 defaultDelegatorsStakingRewardsPercentMille);
    event MaxDelegatorsStakingRewardsChanged(uint32 maxDelegatorsStakingRewardsPercentMille);
    event RewardDistributionActivated(uint256 startTime);
    event RewardDistributionDeactivated();
    event StakingRewardsBalanceMigrated(address indexed addr, uint256 guardianStakingRewards, uint256 delegatorStakingRewards, address toRewardsContract);
    event StakingRewardsBalanceMigrationAccepted(address from, address indexed addr, uint256 guardianStakingRewards, uint256 delegatorStakingRewards);
    event EmergencyWithdrawal(address addr, address token);

    /// Activates staking rewards allocation
    /// @dev governance function called only by the initialization admin
    /// @dev On migrations, startTime should be set to the previous contract deactivation time
    /// @param startTime sets the last assignment time
    function activateRewardDistribution(uint startTime) external /* onlyInitializationAdmin */;

    /// Deactivates fees and bootstrap allocation
    /// @dev governance function called only by the migration manager
    /// @dev guardians updates remain active based on the current perMember value
    function deactivateRewardDistribution() external /* onlyMigrationManager */;
    
    /// Sets the default delegators staking reward portion
    /// @dev governance function called only by the functional manager
    /// @param defaultDelegatorsStakingRewardsPercentMille is the default delegators portion in percent-mille(0 - maxDelegatorsStakingRewardsPercentMille)
    function setDefaultDelegatorsStakingRewardsPercentMille(uint32 defaultDelegatorsStakingRewardsPercentMille) external /* onlyFunctionalManager */;

    /// Returns the default delegators staking reward portion
    /// @return defaultDelegatorsStakingRewardsPercentMille is the default delegators portion in percent-mille
    function getDefaultDelegatorsStakingRewardsPercentMille() external view returns (uint32);

    /// Sets the maximum delegators staking reward portion
    /// @dev governance function called only by the functional manager
    /// @param maxDelegatorsStakingRewardsPercentMille is the maximum delegators portion in percent-mille(0 - 100,000)
    function setMaxDelegatorsStakingRewardsPercentMille(uint32 maxDelegatorsStakingRewardsPercentMille) external /* onlyFunctionalManager */;

    /// Returns the default delegators staking reward portion
    /// @return maxDelegatorsStakingRewardsPercentMille is the maximum delegators portion in percent-mille
    function getMaxDelegatorsStakingRewardsPercentMille() external view returns (uint32);

    /// Sets the annual rate and cap for the staking reward
    /// @dev governance function called only by the functional manager
    /// @param annualRateInPercentMille is the annual rate in percent-mille
    /// @param annualCap is the annual staking rewards cap
    function setAnnualStakingRewardsRate(uint32 annualRateInPercentMille, uint96 annualCap) external /* onlyFunctionalManager */;

    /// Returns the annual staking reward rate
    /// @return annualStakingRewardsRatePercentMille is the annual rate in percent-mille
    function getAnnualStakingRewardsRatePercentMille() external view returns (uint32);

    /// Returns the annual staking rewards cap
    /// @return annualStakingRewardsCap is the annual rate in percent-mille
    function getAnnualStakingRewardsCap() external view returns (uint256);

    /// Checks if rewards allocation is active
    /// @return rewardAllocationActive is a bool that indicates that rewards allocation is active
    function isRewardAllocationActive() external view returns (bool);

    /// Returns the contract's settings
    /// @return annualStakingRewardsCap is the annual rate in percent-mille
    /// @return annualStakingRewardsRatePercentMille is the annual rate in percent-mille
    /// @return defaultDelegatorsStakingRewardsPercentMille is the default delegators portion in percent-mille
    /// @return maxDelegatorsStakingRewardsPercentMille is the maximum delegators portion in percent-mille
    /// @return rewardAllocationActive is a bool that indicates that rewards allocation is active
    function getSettings() external view returns (
        uint annualStakingRewardsCap,
        uint32 annualStakingRewardsRatePercentMille,
        uint32 defaultDelegatorsStakingRewardsPercentMille,
        uint32 maxDelegatorsStakingRewardsPercentMille,
        bool rewardAllocationActive
    );

    /// Migrates the staking rewards balance of the given addresses to a new staking rewards contract
    /// @dev The new rewards contract is determined according to the contracts registry
    /// @dev No impact of the calling contract if the currently configured contract in the registry
    /// @dev may be called also while the contract is locked
    /// @param addrs is the list of addresses to migrate
    function migrateRewardsBalance(address[] calldata addrs) external;

    /// Accepts addresses balance migration from a previous rewards contract
    /// @dev the function may be called by any caller that approves the amounts provided for transfer
    /// @param addrs is the list migrated addresses
    /// @param migratedGuardianStakingRewards is the list of received guardian rewards balance for each address
    /// @param migratedDelegatorStakingRewards is the list of received delegator rewards balance for each address
    /// @param totalAmount is the total amount of staking rewards migrated for all addresses in the list. Must match the sum of migratedGuardianStakingRewards and migratedDelegatorStakingRewards lists.
    function acceptRewardsBalanceMigration(address[] calldata addrs, uint256[] calldata migratedGuardianStakingRewards, uint256[] calldata migratedDelegatorStakingRewards, uint256 totalAmount) external;

    /// Performs emergency withdrawal of the contract balance
    /// @dev called with a token to withdraw, should be called twice with the fees and bootstrap tokens
    /// @dev governance function called only by the migration manager
    /// @param erc20 is the ERC20 token to withdraw
    function emergencyWithdraw(address erc20) external /* onlyMigrationManager */;
}

