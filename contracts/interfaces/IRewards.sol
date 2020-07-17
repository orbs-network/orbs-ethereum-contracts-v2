pragma solidity 0.5.16;

import "../IStakingContract.sol";
import "../spec_interfaces/IContractRegistry.sol";

/// @title Rewards contract interface
interface IRewards {

    function assignRewards() external;
    function assignRewardsToCommittee(address[] calldata generalCommittee, uint256[] calldata generalCommitteeWeights, bool[] calldata certification) external /* onlyCommitteeContract */;

    // staking

    event MaxDelegatorsStakingRewardsChanged(uint32 maxDelegatorsStakingRewardsPercentMille);

    /*
    *   Reward-governor methods
    */

    /// @dev Assigns rewards and sets a new monthly rate for the pro-rata pool.
    function setAnnualStakingRewardsRate(uint256 annual_rate_in_percent_mille, uint256 annual_cap) external /* onlyFunctionalOwner */;


    // fees

    event FeesWithdrawnFromBucket(uint256 bucketId, uint256 withdrawn, uint256 total, bool isCertified);
    event FeesAddedToBucket(uint256 bucketId, uint256 added, uint256 total, bool isCertified);

    /*
     *   External methods
     */

    /// @dev Called by: subscriptions contract
    /// Top-ups the certification fee pool with the given amount at the given rate (typically called by the subscriptions contract)
    function fillCertificationFeeBuckets(uint256 amount, uint256 monthlyRate, uint256 fromTimestamp) external;

    /// @dev Called by: subscriptions contract
    /// Top-ups the general fee pool with the given amount at the given rate (typically called by the subscriptions contract)
    function fillGeneralFeeBuckets(uint256 amount, uint256 monthlyRate, uint256 fromTimestamp) external;

    // bootstrap

    /*
     *   External methods
     */

    /// @return The timestamp of the last reward assignment.
    function getLastRewardAssignmentTime() external view returns (uint256 time);

    /*
     * Reward-governor methods
     */

    /// @dev Assigns rewards and sets a new monthly rate for the geenral commitee bootstrap.
    function setGeneralCommitteeAnnualBootstrap(uint256 annual_amount) external /* onlyFunctionalOwner */;

    /// @dev Assigns rewards and sets a new monthly rate for the certification commitee bootstrap.
    function setCertificationCommitteeAnnualBootstrap(uint256 annual_amount) external /* onlyFunctionalOwner */;


    /*
     * General governance
     */

    /// @dev Updates the address of the contract registry
    function setContractRegistry(IContractRegistry _contractRegistry) external /* onlyMigrationOwner */;


}
