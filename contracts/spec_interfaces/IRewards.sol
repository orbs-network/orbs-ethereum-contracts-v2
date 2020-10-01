// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;

/// @title Rewards contract interface
interface IRewards {

    /*
     * Staking
     */

    event StakingRewardsAssigned(address indexed addr, uint256 amount);
    event GuardianStakingRewardsAssigned(address guardian, uint256 amount, uint256 delegatorRewardsPerToken);
    event StakingRewardsClaimed(address addr, uint256 amount);
    event StakingRewardAllocated(uint256 allocatedRewards, uint256 stakingRewardsPerWeight);
    event GuardianDelegatorsStakingRewardsPercentMilleUpdated(address guardian, uint256 delegatorsStakingRewardsPercentMille);

    /// @dev Returns the currently unclaimed orbs token reward balance of the given address.
    function getStakingRewardsBalance(address addr) external view returns (uint256 balance);

    /// @dev Allows Guardian to set a different delegator staking reward cut than the default
    /// delegatorRewardsPercentMille accepts values between 0 - maxDelegatorsStakingRewardsPercentMille
    function setGuardianDelegatorsStakingRewardsPercentMille(uint32 delegatorRewardsPercentMille) external;

    /// @dev Returns the guardian's delegatorRewardsPercentMille
    function getGuardianDelegatorsStakingRewardsPercentMille(address guardian) external view returns (uint256 delegatorRewardsRatioPercentMille);

    /// @dev Claims the staking rewards balance of addr by staking
    function claimStakingRewards(address addr) external;

    /// @dev Returns the amount of ORBS tokens in the staking wallet that were allocated
    /// but not yet claimed. The staking wallet balance must always larger than the allocated value.
    function getStakingRewardsWalletAllocatedTokens() external view returns (uint256 allocated);

    /// @dev Returns the current stakingRewardsPerToken of a guardian
    function getGuardianDelegatorStakingRewardsPerToken(address guardian) external view returns (uint256 stakingRewardsPerToken);


    // Staking Parameters Governance

    event AnnualStakingRewardsRateChanged(uint256 annualRateInPercentMille, uint256 annualCap);
    event DefaultDelegatorsStakingRewardsChanged(uint32 defaultDelegatorsStakingRewardsPercentMille);
    event MaxDelegatorsStakingRewardsChanged(uint32 maxDelegatorsStakingRewardsPercentMille);

    /// @dev Sets a new annual rate and cap for the staking reward.
    function setAnnualStakingRewardsRate(uint256 annualRateInPercentMille, uint256 annualCap) external /* onlyFunctionalManager */;

    /// @dev Sets the default cut of the delegators staking reward.
    function setDefaultDelegatorsStakingRewardsPercentMille(uint32 defaultDelegatorsStakingRewardsPercentMille) external /* onlyFunctionalManager onlyWhenActive */;

    /// @dev Sets the maximum cut of the delegators staking reward.
    function setMaxDelegatorsStakingRewardsPercentMille(uint32 maxDelegatorsStakingRewardsPercentMille) external /* onlyFunctionalManager onlyWhenActive */;

    /*
     * Fees
     */

    event FeesAssigned(address indexed guardian, uint256 amount);
    event FeesWithdrawn(address indexed guardian, uint256 amount);

    /// @dev Returns the currently unclaimed orbs token reward balance of the given address.
    function getFeeBalance(address addr) external view returns (uint256 balance);

    /// @dev Transfer all of msg.sender's outstanding balance to their account
    function withdrawFees(address guardian) external;

    /// @dev Returns the global Fees and Bootstrap rewards state 
    function getFeesAndBootstrapState() external view returns (
        uint256 certifiedFeesPerMember,
        uint256 generalFeesPerMember,
        uint256 certifiedBootstrapPerMember,
        uint256 generalBootstrapPerMember
    );

    /*
     * Bootstrap
     */

    event BootstrapRewardsAssigned(address indexed guardian, uint256 amount);
    event BootstrapRewardsWithdrawn(address indexed guardian, uint256 amount);

    /// @dev Returns the currently unclaimed bootstrap balance of the given address.
    function getBootstrapBalance(address addr) external view returns (uint256 balance);

    /// @dev Transfer all of msg.sender's outstanding balance to their account
    function withdrawBootstrapFunds(address guardian) external;

    // Bootstrap Parameters Governance 
    event GeneralCommitteeAnnualBootstrapChanged(uint256 generalCommitteeAnnualBootstrap);
    event CertifiedCommitteeAnnualBootstrapChanged(uint256 certifiedCommitteeAnnualBootstrap);

    /// @dev Assigns rewards and sets a new monthly rate for the geenral commitee bootstrap.
    function setGeneralCommitteeAnnualBootstrap(uint256 annual_amount) external /* onlyFunctionalManager */;

    /// @dev Assigns rewards and sets a new monthly rate for the certification commitee bootstrap.
    function setCertifiedCommitteeAnnualBootstrap(uint256 annual_amount) external /* onlyFunctionalManager */;
    
	/*
	 * Notifications from other Orbs contracts
	 */

    /// @dev called by the Committee contract upon expected change in the committee membership of the guardian
    /// Triggers update of the member rewards 
    function committeeMembershipWillChange(address guardian, uint256 weight, uint256 totalCommitteeWeight, bool inCommittee, bool isCertified, bool nextCertification, uint generalCommitteeSize, uint certifiedCommitteeSize) external /* onlyCommitteeContract */;

    /// @dev called by the Delegation contract upon expected change in a committee member delegator stake 
    /// Triggers update of the delegator and guardian staking rewards 
    function delegationWillChange(address guardian, uint256 delegatedStake, address delegator, uint256 delegatorStake, address nextGuardian, uint256 nextGuardianDelegatedStake) external /* onlyDelegationsContract */;

    /*
     * General & Governance 
     */

    event RewardDistributionActivated(uint256 startTime);
    event RewardDistributionDeactivated();

    /// @dev deactivates reward distribution, all rewards will be distributed up
    /// deactivate moment.
    function deactivateRewardDistribution() external /* onlyMigrationManager */;

    /// @dev activates reward distribution, all rewards will be distributed up
    /// assuming the last assignment was on startTime (the time the old contarct was deactivated)
    function activateRewardDistribution(uint startTime) external /* onlyInitializationAdmin */;

    /// @dev Returns the contract's settings
    function getSettings() external view returns (
        uint generalCommitteeAnnualBootstrap,
        uint certifiedCommitteeAnnualBootstrap,
        uint annualStakingRewardsCap,
        uint32 annualStakingRewardsRatePercentMille,
        uint32 defaultDelegatorsStakingRewardsPercentMille,
        uint32 maxDelegatorsStakingRewardsPercentMille,
        bool rewardAllocationActive
    );

    /*
     * Migration
     */

    event RewardsBalanceMigrated(address from, uint256 guardianStakingRewards, uint256 delegatorStakingRewards, uint256 fees, uint256 bootstrapRewards, address toRewardsContract);
    event RewardsBalanceMigrationAccepted(address from, address to, uint256 guardianStakingRewards, uint256 delegatorStakingRewards, uint256 fees, uint256 bootstrapRewards);
    event EmergencyWithdrawal(address addr);

    /// @dev migrates the staking rewards balance of the guardian to the rewards contract as set in the registry.
    function migrateRewardsBalance(address guardian) external;

    /// @dev accepts guardian's balance migration from a previous rewards contarct.
    function acceptRewardsBalanceMigration(address guardian, uint256 guardianStakingRewards, uint256 delegatorStakingRewards, uint256 fees, uint256 bootstrapRewards) external;

    /// @dev emergency withdrawal of the rewards contract balances, may eb called only by the EmergencyManager. 
    function emergencyWithdraw() external /* onlyMigrationManager */; // TODO change to EmergencyManager.

    //    /// @dev Gets the annual staking reward rate.
    //    function getAnnualStakingRewardsRatePercentMille() external view returns (uint32);
    //
    //    /// @dev Gets the annual staking reward cap.
    //    function getAnnualStakingRewardsCap() external view returns (uint256);
    //
    //    /// @dev Gets the default cut of the delegators staking reward.
    //    function getDefaultDelegatorsStakingRewardsPercentMille() external view returns (uint32);
    //
    //    /// @dev Gets the maximum cut of the delegators staking reward.
    //    function getMaxDelegatorsStakingRewardsPercentMille() external view returns (uint32);
    //
    //    /// @dev returns the general committee annual bootstrap fund
    //    function getGeneralCommitteeAnnualBootstrap() external view returns (uint256);
    //
    //    /// @dev returns the certified committee annual bootstrap fund
    //    function getCertifiedCommitteeAnnualBootstrap() external view returns (uint256);

}

