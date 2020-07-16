pragma solidity 0.5.16;

import "../spec_interfaces/IContractRegistry.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


/// @title Rewards contract interface
interface IRewards {

    /// @dev an external function that allows anyone to calculate the current rewards and assign to the committee members
    function assignRewards() external;

    /// @dev assigns rewards to the committee members
    /// Called only by the committee contract 
    function assignRewardsToCommittee(address[] calldata generalCommittee, uint256[] calldata generalCommitteeWeights, bool[] calldata certification) external /* onlyCommitteeContract */;

    // staking

    /// @dev Assigns rewards and sets a new monthly rate for the pro-rata pool.
    function setAnnualStakingRewardsRate(uint256 annual_rate_in_percent_mille, uint256 annual_cap) external /* onlyFunctionalOwner */;

    /*
     *   External methods
     */

    /// @return The timestamp of the last reward assignment.
    function getLastRewardAssignmentTime() external view returns (uint256 time);

    /*
     * Reward-governor methods
     */

    /// @dev Assigns rewards and sets a new monthly rate for the general committee bootstrap.
    function setGeneralCommitteeAnnualBootstrap(uint256 annual_amount) external /* onlyFunctionalOwner */;

    /// @dev Assigns rewards and sets a new monthly rate for the certification committee bootstrap.
    function setCertificationCommitteeAnnualBootstrap(uint256 annual_amount) external /* onlyFunctionalOwner */;

    /*
     * General governance
     */

    /// @dev Updates the address of the contract registry
    function setContractRegistry(IContractRegistry _contractRegistry) external /* onlyMigrationOwner */;

}
