pragma solidity 0.5.16;

import "../IStakingContract.sol";
import "../spec_interfaces/IContractRegistry.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


/// @title Guardians wallet contract interface
interface IGuardiansWallet {

    event RewardsAssigned(address[] assignees, uint256[] calldata stakingRewards, uint256[] calldata fees, uint256[] calldata bootstrapRewards); // todo balance?

    /// @dev Assigns rewards to the Guardians balances.
    /// Assumes approve of the funds transfer prior to the call 
    function assignRewardsToGuardians(address[] calldata guardians, uint256[] calldata stakingRewards, uint256[] calldata fees, uint256[] calldata bootstrapRewards) external;

    // Staking
    event StakingRewardsDistributed(address indexed distributer, uint256 fromBlock, uint256 toBlock, uint split, uint txIndex, address[] to, uint256[] amounts);
    event MaxDelegatorsStakingRewardsChanged(uint32 maxDelegatorsStakingRewardsPercentMille);

    /// @dev Distributes msg.sender's orbs token rewards to a list of addresses, by transferring directly into the staking contract.
    /// Total delegators reward (addresses other than the Guardians) must be less than maxDelegatorsStakingRewardsPercentMille of total amount.
    function distributeStakingRewards(uint256 totalAmount, uint256 fromBlock, uint256 toBlock, uint split, uint txIndex, address[] calldata to, uint256[] calldata amounts) external;

    /// @return Returns the currently unclaimed orbs token reward balance of the given address.
    function getStakingRewardBalance(address addr) external view returns (uint256 balance);

    // Fees

    event FeesWithdrawn(address guardian, uint256 amount);

    /// @dev Transfer all of msg.sender's outstanding balance to the Guardian account.
    /// may be called with either the Guardian address or node address.
    function withdrawFees() external;

    /// @return Returns the currently unclaimed orbs token reward balance of the given address.
    function getFeeBalance(address addr) external view returns (uint256 balance);

    // Bootstrap

    event BootstrapRewardsWithdrawn(address guardian, uint256 amount);

    /// @dev Transfer all of msg.sender's outstanding balance to the Guardian account.
    /// may be called with either the Guardian address or node address.
    function withdrawBootstrapFunds() external; 

    /// @return Returns the currently unclaimed bootstrap balance of the given address.
    function getBootstrapBalance(address addr) external view returns (uint256 balance);

    // Governance
    
    /// @dev the maximum percent that may be distributed to delegators, provided in milli-percent.
    /// For example: 66667 indicates that up to 2/3 of the rewards may be distributed to the dlegators and a 1/3 is distributed to the Guardian. 
    function setMaxDelegatorsStakingRewards(uint32 maxDelegatorsStakingRewardsPercentMille) external; /* OnlyFunctionalOwner */

    /// @dev an emergency withdrawal, enables withdrawal of all funds to an escrow account. To be use in emergencies only.
    function emergencyWithdraw() external; /* OnlyMigrationOwner */

//   constructor(IERC20 stakingToken, IERC20 feesToken, IERC20 bootStrapToken, IStakingContract stakingContract);      

}
