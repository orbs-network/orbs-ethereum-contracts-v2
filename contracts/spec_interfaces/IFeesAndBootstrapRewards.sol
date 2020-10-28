// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

/// @title Rewards contract interface
interface IFeesAndBootstrapRewards {
    event FeesAllocated(uint256 allocatedGeneralFees, uint256 generalFeesPerMember, uint256 allocatedCertifiedFees, uint256 certifiedFeesPerMember);
    event FeesAssigned(address indexed guardian, uint256 amount, uint256 totalAwarded, bool certification, uint256 feesPerMember);
    event FeesWithdrawn(address indexed guardian, uint256 amount, uint256 totalWithdrawn);
    event BootstrapRewardsAllocated(uint256 allocatedGeneralBootstrapRewards, uint256 generalBootstrapRewardsPerMember, uint256 allocatedCertifiedBootstrapRewards, uint256 certifiedBootstrapRewardsPerMember);
    event BootstrapRewardsAssigned(address indexed guardian, uint256 amount, uint256 totalAwarded, bool certification, uint256 bootstrapPerMember);
    event BootstrapRewardsWithdrawn(address indexed guardian, uint256 amount, uint256 totalWithdrawn);

    /*
    * External functions
    */

    /// Triggers update of the guardian rewards
	/// @dev Called by: the Committee contract
    /// @dev called upon expected change in the committee membership of the guardian
    /// @param guardian is the guardian who's committee membership is updated
    /// @param inCommittee indicates whether the guardian is in the committee prior to the change
    /// @param isCertified indicates whether the guardian is certified prior to the change
    /// @param nextCertification indicates whether after the change, the guardian is certified
    /// @param generalCommitteeSize indicates the general committee size prior to the change
    /// @param certifiedCommitteeSize indicates the certified committee size prior to the change
    function committeeMembershipWillChange(address guardian, bool inCommittee, bool isCertified, bool nextCertification, uint generalCommitteeSize, uint certifiedCommitteeSize) external /* onlyCommitteeContract */;

    /// Returns the fees and bootstrap balances of a guardian
    /// @dev calculates the up to date balances (differ from the state)
    /// @return feeBalance the guardian's fees balance
    /// @return bootstrapBalance the guardian's bootstrap balance
    function getFeesAndBootstrapBalance(address guardian) external view returns (
        uint256 feeBalance,
        uint256 bootstrapBalance
    );

    /// Returns an estimation of the fees and bootstrap a guardian will be entitled to for a duration of time
    /// The estimation is based on the current system state and there for only provides an estimation
    /// @param guardian is the guardian address
    /// @param duration is the amount of time in seconds for which the estimation is calculated
    /// @return estimatedFees is the estimated received fees for the duration
    /// @return estimatedBootstrapRewards is the estimated received bootstrap for the duration
    function estimateFutureFeesAndBootstrapRewards(address guardian, uint256 duration) external view returns (
        uint256 estimatedFees,
        uint256 estimatedBootstrapRewards
    );

    /// Transfers the guardian Fees balance to their account
    /// @dev One may withdraw for another guardian
    /// @param guardian is the guardian address
    function withdrawFees(address guardian) external;

    /// Transfers the guardian bootstrap balance to their account
    /// @dev One may withdraw for another guardian
    /// @param guardian is the guardian address
    function withdrawBootstrapFunds(address guardian) external;

    /// Returns the current global Fees and Bootstrap rewards state 
    /// @dev calculated to the latest block, may differ from the state read
    /// @return certifiedFeesPerMember represents the fees a certified committee member from day 0 would have receive
    /// @return generalFeesPerMember represents the fees a non-certified committee member from day 0 would have receive
    /// @return certifiedBootstrapPerMember represents the bootstrap fund a certified committee member from day 0 would have receive
    /// @return generalBootstrapPerMember represents the bootstrap fund a non-certified committee member from day 0 would have receive
    /// @return lastAssigned is the time the calculation was done to (typically the latest block time)
    function getFeesAndBootstrapState() external view returns (
        uint256 certifiedFeesPerMember,
        uint256 generalFeesPerMember,
        uint256 certifiedBootstrapPerMember,
        uint256 generalBootstrapPerMember,
        uint256 lastAssigned
    );

    /// Returns the current guardian Fees and Bootstrap rewards state 
    /// @dev calculated to the latest block, may differ from the state read
    /// @return feeBalance is the guardian fees balance 
    /// @return lastFeesPerMember is the FeesPerMember on the last update based on the guardian certification state
    /// @return bootstrapBalance is the guardian bootstrap balance 
    /// @return lastBootstrapPerMember is the FeesPerMember on the last BootstrapPerMember based on the guardian certification state
    function getFeesAndBootstrapData(address guardian) external view returns (
        uint256 feeBalance,
        uint256 lastFeesPerMember,
        uint256 bootstrapBalance,
        uint256 lastBootstrapPerMember,
        uint256 withdrawnFees,
        uint256 withdrawnBootstrap,
        bool certified
    );

    /*
     * Governance
     */

    event GeneralCommitteeAnnualBootstrapChanged(uint256 generalCommitteeAnnualBootstrap);
    event CertifiedCommitteeAnnualBootstrapChanged(uint256 certifiedCommitteeAnnualBootstrap);
    event RewardDistributionActivated(uint256 startTime);
    event RewardDistributionDeactivated();
    event FeesAndBootstrapRewardsBalanceMigrated(address indexed guardian, uint256 fees, uint256 bootstrapRewards, address toRewardsContract);
    event FeesAndBootstrapRewardsBalanceMigrationAccepted(address from, address indexed guardian, uint256 fees, uint256 bootstrapRewards);
    event EmergencyWithdrawal(address addr, address token);

    /// Deactivates fees and bootstrap allocation
	/// @dev governance function called only by the migration manager
    /// @dev guardians updates remain active based on the current perMember value
    function deactivateRewardDistribution() external /* onlyMigrationManager */;

    /// Activates fees and bootstrap allocation
	/// @dev governance function called only by the initialization manager
    /// @dev On migrations, startTime should be set as the previous contract deactivation time.
    /// @param startTime sets the last assignment time
    function activateRewardDistribution(uint startTime) external /* onlyInitializationAdmin */;

    /// Returns the contract's settings
    /// @return generalCommitteeAnnualBootstrap is the general committee annual bootstrap
    /// @return certifiedCommitteeAnnualBootstrap is the certified committee additional annual bootstrap
    /// @return rewardAllocationActive indicates the rewards allocation activation state 
    function getSettings() external view returns (
        uint generalCommitteeAnnualBootstrap,
        uint certifiedCommitteeAnnualBootstrap,
        bool rewardAllocationActive
    );

    /// Returns the general committee annual bootstrap award
    /// @return generalCommitteeAnnualBootstrap is the general committee annual bootstrap
    function getGeneralCommitteeAnnualBootstrap() external view returns (uint256);

	/// Sets the annual rate for the general committee bootstrap
	/// @dev governance function called only by the functional manager
    /// @dev updates the global bootstrap and fees state before updating  
	/// @param annualAmount is the annual general committee bootstrap award
    function setGeneralCommitteeAnnualBootstrap(uint256 annualAmount) external /* onlyFunctionalManager */;

    /// Returns the certified committee annual bootstrap reward
    /// @return certifiedCommitteeAnnualBootstrap is the certified committee additional annual bootstrap
    function getCertifiedCommitteeAnnualBootstrap() external view returns (uint256);

	/// Sets the annual rate for the certified committee bootstrap
	/// @dev governance function called only by the functional manager
    /// @dev updates the global bootstrap and fees state before updating  
	/// @param annualAmount is the annual certified committee bootstrap award
    function setCertifiedCommitteeAnnualBootstrap(uint256 annualAmount) external /* onlyFunctionalManager */;

    /// Returns the rewards allocation activation status
    /// @return rewardAllocationActive is the activation status
    function isRewardAllocationActive() external view returns (bool);

    /// Migrates the rewards balance to a new FeesAndBootstrap contract
    /// @dev The new rewards contract is determined according to the contracts registry
    /// @dev No impact of the calling contract if the currently configured contract in the registry
    /// @dev may be called also while the contract is locked
    /// @param guardian is the guardian to migrate
    function migrateRewardsBalance(address guardian) external;

    /// Accepts guardian's balance migration from a previous rewards contract
    /// @dev the function may be called by any caller that approves the amounts provided for transfer
    /// @param guardian is the migrated guardian
    /// @param fees is the received guardian fees balance 
    /// @param bootstrapRewards is the received guardian bootstrap balance
    function acceptRewardsBalanceMigration(address guardian, uint256 fees, uint256 bootstrapRewards) external;

    /// Performs emergency withdrawal of the contract balance
    /// @dev called with a token to withdraw, should be called twice with the fees and bootstrap tokens
	/// @dev governance function called only by the migration manager
    /// @param token is the ERC20 token to withdraw
    function emergencyWithdraw(address token) external; /* onlyMigrationManager */
}

