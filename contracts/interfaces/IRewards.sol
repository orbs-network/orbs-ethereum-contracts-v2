pragma solidity 0.5.16;

import "../IStakingContract.sol";
import "./IContractRegistry.sol";

/// @title Rewards contract interface
interface IRewards {
    event RewardAssigned(address assignee, uint256 amount, uint256 balance);

    /*
     *   External methods
     */

    /// @dev Calculates and assigns validator rewards for the time period since the last reward calculation
    function assignRewards() external returns (uint256);

    /// @return Returns the currently unclaimed orbs token reward balance of the given address.
    function getRewardBalance(address addr) external view returns (uint256);

    /// @dev Distributes msg.sender's orbs token rewards to a list of addresses, by transferring directly into the staking contract.
    function distributeOrbsTokenRewards(address[] calldata to, uint256[] calldata amounts) external;

    /// @return The timestamp of the last reward assignment.
    function getLastRewardsAssignment() external view returns (uint256);

    /// @dev Transfers the given amount of orbs tokens form the sender to this contract an update the pool.
    function topUpPool(uint256 amount) external;

    /*
     *   Methods restricted to other Orbs contracts
     */

    /// @dev Called by: Elections contract (committee provider)
    /// Notifies a change in the committee
    function committeeChanged(address[] calldata addrs, uint256[] calldata stakes) external /* onlyCommitteeProvider */;

    /*
    *   Reward-governor methods
    */

    /// @dev Assigns rewards and sets a new monthly rate for the pro-rata pool.
    function setAnnualRate(uint256 annual_rate, uint256 annual_cap) external /* onlyRewardsGovernor */;

    /*
     * General governance
     */

    /// @dev Updates the address of the contract registry
    function setContractRegistry(IContractRegistry _contractRegistry) external /* onlyOwner */;


}
