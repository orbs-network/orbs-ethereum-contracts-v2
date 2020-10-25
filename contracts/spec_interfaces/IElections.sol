// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

/// @title Elections contract interface
interface IElections {
	
	// Election state change events
	event StakeChanged(address indexed addr, uint256 selfStake, uint256 delegatedStake, uint256 effectiveStake);
	event GuardianStatusUpdated(address indexed guardian, bool readyToSync, bool readyForCommittee);

	// Vote out / Vote unready
	event GuardianVotedUnready(address indexed guardian);
	event VoteUnreadyCasted(address indexed voter, address indexed subject, uint256 expiration);
	event GuardianVotedOut(address indexed guardian);
	event VoteOutCasted(address indexed voter, address indexed subject);

	/*
	 * External functions
	 */

	/// Called by a guardian when ready to start syncing with other nodes
	/// @dev ready to sync state is not managed in the contract that only emits an event
	/// @dev readyToSync clears the readyForCommittee state
	function readyToSync() external;

	/// Called by a guardian when ready to join the committee, typically after syncing is complete or after being voted out
	/// @dev a guardian calling readyForCommittee that is qualified to join the committee is added.
	function readyForCommittee() external;

	/// Called to test if a guardian calling readyForCommittee() will lead to joining the committee
	/// @dev called periodically by guardians to check if they are qualified to join the committee.
	/// @param guardian is the guardian to check
	/// @return canJoin indicating that the guardian can join the current committee
	function canJoinCommittee(address guardian) external view returns (bool);

	/// Returns an address effective stake
	/// The effective stake is derived from a guardian delegate stake and selfs stake  
	/// @return effectiveStake is the guardian's effective stake
	function getEffectiveStake(address guardian) external view returns (uint effectiveStake);

	/// Returns the current committee along with the guardians' Orbs address and IP
	/// @return committee is a list of the committee members' guardian addresses
	/// @return weights is a list of the committee members' weight (effective stake)
	/// @return orbsAddrs is a list of the committee members' orbs address
	/// @return certification is a list of bool indicating the committee members certification
	/// @return ips is a list of the committee members' ip
	function getCommittee() external view returns (address[] memory committee, uint256[] memory weights, address[] memory orbsAddrs, bool[] memory certification, bytes4[] memory ips);

	// Vote-unready

	/// Casts an unready vote on a subject guardian
	/// @dev Called by a guardian as part of the automatic vote-unready flow
	/// @dev The transaction may be sent from the guardian or orbs address.
	/// @param subject is the subject guardian to vote out
	/// @param expiration is the expiration time of the vote unready to prevent counting of a vote that is already irrelevant.
	function voteUnready(address subject, uint expiration) external;

	/// Returns the current vote unready vote for a voter and a subject pair
	/// @param voter is the voting guardian address
	/// @param subject is the subject guardian address
	/// @return valid indicates whether there is a valid vote
	/// @return expiration returns the votes expiration time
	function getVoteUnreadyVote(address voter, address subject) external view returns (bool valid, uint256 expiration);

	/// Returns the current vote-unready status of a subject guardian.
	/// @dev the committee and certification data is used to check the certified and committee threshold
	/// @param subject is the subject guardian address
	/// @return committee is a list of the current committee members
	/// @return weights is a list of the current committee members weight
	/// @return certification is a list of bool indicating the committee members certification
	/// @return votes is a list of bool indicating the members that votes the subject unready
	/// @return subjectInCommittee indicates that the subject is in the committee
	/// @return subjectInCertifiedCommittee indicates that the subject is in the certified committee
	function getVoteUnreadyStatus(address subject) external view returns (
		address[] memory committee,
		uint256[] memory weights,
		bool[] memory certification,
		bool[] memory votes,
		bool subjectInCommittee,
		bool subjectInCertifiedCommittee
	);

	// Vote-out

	/// Casts a voteOut vote by the sender to the given address
	/// @dev the transaction is sent from the guardian address
	/// @param subject is the subject guardian address
	function voteOut(address subject) external;

	/// Returns the subject address the addr has voted-out against
	/// @param voter is the voting guardian address
	/// @return subject is the subject the voter has voted out
	function getVoteOutVote(address voter) external view returns (address);

	/// Returns the governance voteOut status of a guardian.
	/// @dev A guardian is voted out if votedStake / totalDelegatedStake (in percent mille) > threshold
	/// @param subject is the subject guardian address
	/// @return votedOut indicates whether the subject was voted out
	/// @return votedStake is the total stake voting against the subject
	/// @return totalDelegatedStake is the total delegated stake
	function getVoteOutStatus(address subject) external view returns (bool votedOut, uint votedStake, uint totalDelegatedStake);

	/*
	 * Notification functions from other PoS contracts
	 */

	/// Notifies a delegated stake change event
	/// @dev Called by: delegation contract
	/// @param delegate is the delegate to update
	/// @param selfStake is the delegate self stake (0 if not self-delegating)
	/// @param delegatedStake is the delegate delegated stake (0 if not self-delegating)
	/// @param totalDelegatedStake is the total delegated stake
	function delegatedStakeChange(address delegate, uint256 selfStake, uint256 delegatedStake, uint256 totalDelegatedStake) external /* onlyDelegationsContract onlyWhenActive */;

	/// Notifies a new guardian was unregistered
	/// @dev Called by: guardian registration contract
	/// @dev when a guardian unregisters its status is updated to not ready to sync and is removed from the committee
	/// @param guardian is the address of the guardian that unregistered
	function guardianUnregistered(address guardian) external /* onlyGuardiansRegistrationContract */;

	/// Notifies on a guardian certification change
	/// @dev Called by: guardian registration contract
	/// @param guardian is the address of the guardian to update
	/// @param isCertified indicates whether the guardian is certified
	function guardianCertificationChanged(address guardian, bool isCertified) external /* onlyCertificationContract */;


	/*
     * Governance functions
	 */

	event VoteUnreadyTimeoutSecondsChanged(uint32 newValue, uint32 oldValue);
	event VoteOutPercentMilleThresholdChanged(uint32 newValue, uint32 oldValue);
	event VoteUnreadyPercentMilleThresholdChanged(uint32 newValue, uint32 oldValue);
	event MinSelfStakePercentMilleChanged(uint32 newValue, uint32 oldValue);

	/// Sets the minimum self stake requirement for the effective stake
	/// @dev governance function called only by the functional manager
	/// @param minSelfStakePercentMille the minimum self stake in percent-mille units 
	function setMinSelfStakePercentMille(uint32 minSelfStakePercentMille) external /* onlyFunctionalManager onlyWhenActive */;

	/// Returns the minimum self-stake required for the effective stake
	/// @return minSelfStakePercentMille is the minimum self stake in percent-mille (0-100,000)
	function getMinSelfStakePercentMille() external view returns (uint32);

	/// Sets the vote-out threshold
	/// @dev governance function called only by the functional manager
	/// @param voteUnreadyPercentMilleThreshold is the minimum threshold in percent-mille (0-100,000)
	function setVoteOutPercentMilleThreshold(uint32 voteUnreadyPercentMilleThreshold) external /* onlyFunctionalManager onlyWhenActive */;

	/// Returns the vote-out threshold
	/// @return voteOutPercentMilleThreshold is the minimum threshold in percent-mille (0-100,000)
	function getVoteOutPercentMilleThreshold() external view returns (uint32);

	/// Sets the vote-unready threshold
	/// @dev governance function called only by the functional manager
	/// @param voteUnreadyPercentMilleThreshold is the minimum threshold in percent-mille (0-100,000)
	function setVoteUnreadyPercentMilleThreshold(uint32 voteUnreadyPercentMilleThreshold) external /* onlyFunctionalManager onlyWhenActive */;

	/// Returns the vote-unready threshold
	/// @return voteUnreadyPercentMilleThreshold is the minimum threshold in percent-mille (0-100,000)
	function getVoteUnreadyPercentMilleThreshold() external view returns (uint32);

	/// Returns the contract's settings 
	/// @return minSelfStakePercentMille is the minimum self stake in percent-mille (0-100,000)
	/// @return voteUnreadyPercentMilleThreshold is the minimum threshold in percent-mille (0-100,000)
	/// @return voteOutPercentMilleThreshold is the minimum threshold in percent-mille (0-100,000)
	function getSettings() external view returns (
		uint32 minSelfStakePercentMille,
		uint32 voteUnreadyPercentMilleThreshold,
		uint32 voteOutPercentMilleThreshold
	);

	/// Initializes the ready for committee notification for the committee guardians
	/// @dev governance function called only by the initialization manager during migration 
	/// @dev identical behaviour as if each guardian sent readyForCommittee() 
	/// @param guardians a list of guardians addresses to update
	function initReadyForCommittee(address[] calldata guardians) external /* onlyInitializationAdmin */;

}
