// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;

/// @title Elections contract interface
interface IElections {
	
	// Election state change events
	event GuardianVotedUnready(address guardian);
	event GuardianVotedOut(address guardian);
	event StakeChanged(address addr, uint256 selfStake, uint256 delegatedStake, uint256 effectiveStake);
	event GuardianStatusUpdated(address addr, bool readyToSync, bool readyForCommittee);

	// Vote out / Vote unready
	event VoteUnreadyCasted(address voter, address subject, uint256 expiration);
	event VoteOutCasted(address voter, address subject);

	// Parameters Governance 
	event VoteUnreadyTimeoutSecondsChanged(uint32 newValue, uint32 oldValue);
	event VoteOutPercentMilleThresholdChanged(uint32 newValue, uint32 oldValue);
	event VoteUnreadyPercentMilleThresholdChanged(uint32 newValue, uint32 oldValue);
	event MinSelfStakePercentMilleChanged(uint32 newValue, uint32 oldValue);

	/*
	 * External methods
	 */

	/// @dev Called by a guardian as part of the automatic vote-unready flow
	function voteUnready(address subject_addr, uint expiration) external;

	/// @dev Casts a voteOut vote by the sender to the given address
	function voteOut(address subjectAddr) external;

	/// @dev Called by a guardian when ready to start syncing with other nodes
	function readyToSync() external;

	/// @dev Called by a guardian when ready to join the committee, typically after syncing is complete or after being voted out
	function readyForCommittee() external;

	function initReadyForCommittee(address[] calldata guardians) external /* onlyInitializationAdmin */;

	/// @dev Called to test if a guardian calling readyForCommittee() will lead to joining the committee
	function canJoinCommittee(address addr) external view returns (bool);

	/// @dev Returns the governance voteOut status of a guardian.
	/// A guardian is voted out if votedStake / totalDelegatedStake (in percent mille) > threshold  
	function getVoteOutStatus(address subjectAddr) external view returns (uint votedStake, uint totalDelegatedStake);

	/// @dev Returns the current vote-unready status of a subject guardian.
	/// votes indicates wether the specific committee member voted the guardian unready
	function getVoteUnreadyStatus(address subjectAddr) external view returns
		(address[] memory committee, uint256[] memory weights, bool[] memory certification, bool[] memory votes, bool subjectInCommittee, bool subjectInCertifiedCommittee);

	/// @dev Returns an address effective stake
	function getEffectiveStake(address addr) external view returns (uint effectiveStake);

	/// @dev Returns the subject address the addr has voted-out against
	function getVoteOutVote(address addr) external view returns (address);

	/// @dev returns the current committee
	/// used also by the rewards and fees contracts
	function getCommittee() external view returns (address[] memory addrs, uint256[] memory weights, address[] memory orbsAddrs, bool[] memory certification, bytes4[] memory ips);

	/*
	 * Methods restricted to other Orbs contracts
	 */

	/// @dev Called by: delegation contract
	/// Notifies a delegated stake change event
	/// total_delegated_stake = 0 if addr delegates to another guardian
	function delegatedStakeChange(address delegate, uint256 selfStake, uint256 delegatedStake, uint256 totalDelegatedStake) external /* onlyDelegationsContract onlyWhenActive */;

	/// @dev Called by: guardian registration contract
	/// Notifies a new guardian was registered
	function guardianRegistered(address addr) external;

	/// @dev Called by: guardian registration contract
	/// Notifies a new guardian was unregistered
	function guardianUnregistered(address addr) external /* onlyGuardiansRegistrationContract */;

	/// @dev Called by: guardian registration contract
	/// Notifies on a guardian certification change
	function guardianCertificationChanged(address addr, bool isCertified) external /* onlyCertificationContract */;


	/*
     * Governance
	 */

	/// @dev Sets the minimum self-stake required for the effective stake
	/// minSelfStakePercentMille - the minimum self stake in percent-mille (0-100,000)
	function setMinSelfStakePercentMille(uint32 minSelfStakePercentMille) external /* onlyFunctionalManager onlyWhenActive */;
	
	/// @dev Sets the vote-out threshold
	/// voteOutPercentMilleThreshold - the minimum threshold in percent-mille (0-100,000)
	function setVoteOutPercentMilleThreshold(uint32 voteUnreadyPercentMilleThreshold) external /* onlyFunctionalManager onlyWhenActive */;
	
	/// @dev Sets the vote-unready threshold
	/// voteUnreadyPercentMilleThreshold - the minimum threshold in percent-mille (0-100,000)
	function setVoteUnreadyPercentMilleThreshold(uint32 voteUnreadyPercentMilleThreshold) external /* onlyFunctionalManager onlyWhenActive */;

	/// @dev Returns the minimum self-stake required for the effective stake
	function getMinSelfStakePercentMille() external view returns (uint32);
	
	/// @dev Returns the vote-out threshold
	function getVoteOutPercentMilleThreshold() external view returns (uint32);
	
	/// @dev Returns the vote-unready threshold	
	function getVoteUnreadyPercentMilleThreshold() external view returns (uint32);

	/// @dev Returns the contract's settings 
	function getSettings() external view returns (
		uint32 minSelfStakePercentMille,
		uint32 voteUnreadyPercentMilleThreshold,
		uint32 voteOutPercentMilleThreshold
	);
}

