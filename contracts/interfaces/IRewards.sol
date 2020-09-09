// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;

import "../IStakingContract.sol";
import "../spec_interfaces/IContractRegistry.sol";

/// @title Rewards contract interface
interface IRewards {

    event RewardDistributionActivated(uint256 startTime);
    event RewardDistributionDeactivated();

    function deactivate() external /* onlyMigrationManager */;

    function activate(uint startTime) external /* onlyInitializationAdmin */;

    function committeeMemberStakeWillChange(address addr, uint256 stake, uint256 totalCommitteeStake, address delegator, uint256 delegatorStake) external /* onlyCommitteeContract */;

    function committeeMembershipWillChange(address addr, uint256 stake, uint256 totalCommitteeStake, bool inCommittee, bool isCertified, uint generalCommitteeSize, uint certifiedCommitteeSize) external /* onlyCommitteeContract */;

    /*
     * Staking
     */

    event StakingRewardsAssigned(address indexed guardian, uint256 amount);
    event StakingRewardsDistributed(address indexed distributer, uint256 fromBlock, uint256 toBlock, uint split, uint txIndex, address[] to, uint256[] amounts);

    /// @dev Returns the currently unclaimed orbs token reward balance of the given address.
    function getStakingRewardBalance(address addr) external view returns (uint256 balance);

    /// @dev Distributes msg.sender's orbs token rewards to a list of addresses, by transferring directly into the staking contract.
    /// @dev `to[0]` must be the sender's main address
    /// @dev Total delegators reward (`to[1:n]`) must be less then maxDelegatorsStakingRewardsPercentMille of total amount
    function distributeStakingRewards(uint256 totalAmount, uint256 fromBlock, uint256 toBlock, uint split, uint txIndex, address[] calldata to, uint256[] calldata amounts) external;

    // Staking Parameters Governance 
    event MaxDelegatorsStakingRewardsChanged(uint32 maxDelegatorsStakingRewardsPercentMille);
    event AnnualStakingRewardsRateChanged(uint256 annualRateInPercentMille, uint256 annualCap);

    /// @dev Sets a new annual rate and cap for the staking reward.
    function setAnnualStakingRewardsRate(uint256 annualRateInPercentMille, uint256 annualCap) external /* onlyFunctionalManager */;

    /// @dev Sets the maximum cut of the delegators staking reward.
    function setMaxDelegatorsStakingRewardsPercentMille(uint32 maxDelegatorsStakingRewardsPercentMille) external /* onlyFunctionalManager onlyWhenActive */;

    /// @dev Gets the annual staking reward rate.
    function getAnnualStakingRewardsRatePercentMille() external view returns (uint32);

    /// @dev Gets the annual staking reward cap.
    function getAnnualStakingRewardsCap() external view returns (uint256);

    /// @dev Gets the maximum cut of the delegators staking reward.
    function getMaxDelegatorsStakingRewardsPercentMille() external view returns (uint32);

    /* 
     * Fees
     */

    event FeesAssigned(address indexed guardian, uint256 amount);
    event FeesWithdrawn(address indexed guardian, uint256 amount);

    /// @dev Returns the currently unclaimed orbs token reward balance of the given address.
    function getFeeBalance(address addr) external view returns (uint256 balance);

    /// @dev Transfer all of msg.sender's outstanding balance to their account
    function withdrawFees(address guardian) external;

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
    
    /// @dev returns the general committee annual bootstrap fund
    function getGeneralCommitteeAnnualBootstrap() external view returns (uint256);
    
    /// @dev returns the certified committee annual bootstrap fund
    function getCertifiedCommitteeAnnualBootstrap() external view returns (uint256);

    /*
     * General
     */

    /// @dev Returns the contract's settings
    function getSettings() external view returns (
        uint generalCommitteeAnnualBootstrap,
        uint certifiedCommitteeAnnualBootstrap,
        uint annualStakingRewardsCap,
        uint32 annualStakingRewardsRatePercentMille,
        uint32 maxDelegatorsStakingRewardsPercentMille,
        bool active
    );

    /*
     * Migration
     */

    event StakingRewardsBalanceMigrated(address guardian, uint256 amount, address toRewardsContract);
    event StakingRewardsMigrationAccepted(address from, address guardian, uint256 amount);
    event EmergencyWithdrawal(address addr);

    /// @dev migrates the staking rewards balance of the guardian to the rewards contract as set in the registry.
    function migrateStakingRewardsBalance(address guardian) external;

    /// @dev accepts guardian's balance migration from a previous rewards contarct.
    function acceptStakingRewardsMigration(address guardian, uint256 amount) external;

    /// @dev emergency withdrawal of the rewards contract balances, may eb called only by the EmergencyManager. 
    function emergencyWithdraw() external /* onlyMigrationManager */; // TODO change to EmergencyManager.
}
