pragma solidity 0.5.16;

import "../IStakingContract.sol";
import "./IContractRegistry.sol";

/// @title Fees contract interface
interface IFees {
    event FeesAssigned(address[] assignees, uint256[] orbs_amounts);
    event FeesAddedToBucket(uint256 bucketId, uint256 added, uint256 total, bool isCompliant);

    /*
     *   External methods
     */

    /// @dev Calculates and assigns validator fees and bootstrap fund for the time period since the last reward calculation
    function assignFees(address[] calldata generalCommittee, address[] calldata complianceCommittee) external /* onlyElectionContract */;

    /// @return Returns the currently unclaimed orbs token reward balance of the given address.
    function getOrbsBalance(address addr) external view returns (uint256 balance);

    /// @dev Transfer all of msg.sender's outstanding balance to their account
    function withdrawFunds() external;

    /// @return The timestamp of the last reward assignment.
    function getLastFeesAssignment() external view returns (uint256 time);

    /// @dev Called by: subscriptions contract
    /// Top-ups the compliance fee pool with the given amount at the given rate (typically called by the subscriptions contract)
    function fillComplianceFeeBuckets(uint256 amount, uint256 monthlyRate, uint256 fromTimestamp) external;

    /// @dev Called by: subscriptions contract
    /// Top-ups the general fee pool with the given amount at the given rate (typically called by the subscriptions contract)
    function fillGeneralFeeBuckets(uint256 amount, uint256 monthlyRate, uint256 fromTimestamp) external;

    /*
     * General governance
     */

    /// @dev Updates the address of the contract registry
    function setContractRegistry(IContractRegistry _contractRegistry) external /* onlyOwner */;


}
