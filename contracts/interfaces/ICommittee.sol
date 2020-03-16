pragma solidity 0.5.16;

import "./IContractRegistry.sol";

/// @title Elections contract interface
interface ICommittee {
    event CommitteeChanged(address[] addrs, address[] orbsAddrs, uint256[] stakes);
	event AuditrosChanged(address[] addrs, address[] orbsAddrs, uint256[] stakes);

    // No events
    // No external functions

	/*
     * Methods restricted to other Orbs contracts
     */

	/// @dev Called by: Elections contract
	/// Notifies a stake change for sorting to a relevant committee member.
    /// stake = 0 indicates removal of the member from the committee (for exmaple on unregister, voteUnready, voteOut)
	function stakeChange(address addr, uint256 stake, bool readyForCommittee); /* onlyElectionContract */;

	/// @dev Called by: Elections contract
	/// Returns the N top committee members
	function getCommitee(uint N) external view returns (address[] memory, uint256[] memory); 

	/// @dev Called by: Elections contract
	/// Sets the mimimal stake, and committee members
    /// Every member with sortingStake >= mimimumStake OR in top minimumN is included in the committee
	function setMinimumStake(uint256 mimimumStake, minimumN); /* onlyElectionContract */;


	/*
	 * Governance
	 */
	
    /// @dev Updates the address calldata of the contract registry
	function setContractRegistry(IContractRegistry _contractRegistry) external /* onlyOwner */;

	/*
	 * Getters
	 */

    /// @dev returns the current committee
    /// used also by the rewards and fees contracts
	function getCommittee() external view returns (address[] memory addr, address[] memory orbsAddr, uint32[] ip);

    /// @dev returns the current auditors (out of commiteee) topology
	function getAuditors() external view returns (address[] memory addr, address[] memory orbsAddr, uint32[] ip);

}
