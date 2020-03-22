pragma solidity 0.5.16;

import "../IStakingContract.sol";
import "./IContractRegistry.sol";

/// @title Fees contract interface
interface IBootstrapRewards {
    event BootstrapRewardsAssigned(address[] assignees, uint256[] amounts);
    event BootstrapAddedToPool(uint256 added, uint256 total);

    /*
     *   External methods
     */

    /// @return Returns the currently unclaimed bootstrap balance of the given address.
    function getBootstrapBalance(address addr) external view returns (uint256 balance);

    /// @dev Transfer all of msg.sender's outstanding balance to their account
    function withdrawFunds() external;

    /// @return The timestamp of the last reward assignment.
    function getLastBootstrapAssignment() external view returns (uint256 time);

    /// @dev Transfers the given amount of bootstrap tokens form the sender to this contract and update the pool.
    /// Assumes the tokens were approved for transfer
    function topUpBootstrapPool(uint256 amount) external;

    /*
     * Reward-governor methods
     */

    /// @dev Assigns rewards and sets a new monthly rate for the geenral commitee bootstrap.
    function setGeneralCommitteeAnnualBootstrap(uint256 annual_amount) external;

    /// @dev Assigns rewards and sets a new monthly rate for the compliance commitee bootstrap.
    function setComplianceCommitteeAnnualBootstrap(uint256 annual_amount) external;

    /*
     * General governance
     */

    /// @dev Updates the address of the contract registry
    function setContractRegistry(IContractRegistry _contractRegistry) external /* onlyOwner */;

}
