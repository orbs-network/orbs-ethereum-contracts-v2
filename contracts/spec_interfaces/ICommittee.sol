pragma solidity 0.5.16;

import "./IContractRegistry.sol";

/// @title Elections contract interface
interface ICommittee {
	// State events
    event CommitteeChanged(address[] addrs, address[] orbsAddrs, uint256[] weights);
	event StandbysChanged(address[] addrs, address[] orbsAddrs, uint256[] weights);

    // Function calls - TBD do we need events on calls, make sure all are data
	// is available from other contarcts events

	/*
     * Methods restricted to other Orbs contracts
     */

	/// @dev Called by: Elections contract
	/// Adding a member to commtiee for example on register, compliance change.
	/// Once a member was added to the committee, the contarct maintains its weight, readiness status until removal. 
	function addMember(address addr, uint256 weight) external returns (bool commiteeChanged, bool standbysChanged) /* onlyElectionContract */;

	/// @dev Called by: Elections contract
	/// Notifies a weight change for sorting to a relevant committee member.
	function updateMemberWeight(address addr, uint256 weight) external returns (bool commiteeChanged, bool standbysChanged) /* onlyElectionContract */;

	/// @dev Called by: Elections contract
	/// Notifies a member removal for example due to voteOut, voteUnready, unregister
	function removeMember(address addr) external returns (bool commiteeChanged, bool standbysChanged) /* onlyElectionContract */;

	/// @dev Called by: Elections contract
	/// memebr notification of readyForSync
	/// The Election contract forwards the ready updates of members to the Committee contarct 
	function readyForSync(address addr) external returns (bool commiteeChanged, bool standbysChanged) /* onlyElectionContract */;

	/// @dev Called by: Elections contract
	/// memebr notification of readyForCommitee
	/// The Election contract forwards the ready updates of members to the Committee contarct 
	function readyForCommitee(address addr) external returns (bool commiteeChanged, bool standbysChanged) /* onlyElectionContract */;

	/// @dev Called by: Elections contract
	/// Returns the weight of the member with the lowest weight in the committee.
	function getCommiteeMinimumWeight() external view returns (uint256 weight);

	/// @dev Called by: Elections contract
	/// Returns the weight of the member with the lowest weight in the committee.
	function getCommiteeSize() external view returns (uint size);

	/// @dev Called by: Elections contract
	/// Returns the committee members and their weights
	function getCommitee() external view returns (address[] memory addrs, uint256[] memory weights);

	/// @dev Returns the standy (out of commiteee) members and their weights
	function getStandbys( external view returns (address[] memory addrs, uint256[] memory weights);

	/// @dev Called by: Elections contract
	/// Sets the mimimal weight, and committee members
    /// Every member with sortingStake >= mimimumStake OR in top minimumN is included in the committee
	function setMinimumWeight(uint256 mimimumWeight) external /* onlyElectionContract */;

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
	function getCommitteeInfo() external view returns (address[] memory addrs, uint256[] memory weights, address[] memory orbsAddrs, uint32[] memory ips);

    /// @dev returns the current standbys (out of commiteee) topology
	function getStandbysInfo() external view returns (address[] memory addrs, uint256[] memory weights, address[] memory orbsAddrs, uint32[] memory ips);

}
