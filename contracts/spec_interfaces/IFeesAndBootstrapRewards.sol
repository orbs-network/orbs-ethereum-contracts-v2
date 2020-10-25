// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

/// @title Rewards contract interface
interface IFeesAndBootstrapRewards {
    event FeesAllocated(uint256 allocatedGeneralFees, uint256 generalFeesPerMember, uint256 allocatedCertifiedFees, uint256 certifiedFeesPerMember);
    event FeesAssigned(address indexed guardian, uint256 amount);
    event FeesWithdrawn(address indexed guardian, uint256 amount);
    event BootstrapRewardsAllocated(uint256 allocatedGeneralBootstrapRewards, uint256 generalBootstrapRewardsPerMember, uint256 allocatedCertifiedBootstrapRewards, uint256 certifiedBootstrapRewardsPerMember);
    event BootstrapRewardsAssigned(address indexed guardian, uint256 amount);
    event BootstrapRewardsWithdrawn(address indexed guardian, uint256 amount);

    /*
    * External functions
    */

    /// Triggers update of the guardian rewards
	/// @dev Called by: the Committee contract
    /// @dev called upon expected change in the committee membership of the guardian
    /// @param guardian is the guardian address
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

    /// 
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
        uint256 lastBootstrapPerMember
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
    /// @dev guardians updates remain active based on the current perMember value
    function deactivateRewardDistribution() external /* onlyMigrationManager */;

    /// Activates fees and bootstrap allocation
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

    function getGeneralCommitteeAnnualBootstrap() external view returns (uint256);

    /// @dev Assigns rewards and sets a new monthly rate for the geenral commitee bootstrap.
    function setGeneralCommitteeAnnualBootstrap(uint256 annual_amount) external /* onlyFunctionalManager */;

    function getCertifiedCommitteeAnnualBootstrap() external view returns (uint256);

    /// @dev Assigns rewards and sets a new monthly rate for the certification commitee bootstrap.
    function setCertifiedCommitteeAnnualBootstrap(uint256 annual_amount) external /* onlyFunctionalManager */;

    function isRewardAllocationActive() external view returns (bool);

    /// @dev migrates the staking rewards balance of the guardian to the rewards contract as set in the registry.
    function migrateRewardsBalance(address guardian) external;

    /// @dev accepts guardian's balance migration from a previous rewards contarct.
    function acceptRewardsBalanceMigration(address guardian, uint256 fees, uint256 bootstrapRewards) external;

    /// @dev emergency withdrawal of the rewards contract balances, may eb called only by the EmergencyManager. 
    function emergencyWithdraw(address token) external; /* onlyMigrationManager */
}

