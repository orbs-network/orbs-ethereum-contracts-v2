// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;

import "../spec_interfaces/IContractRegistry.sol";
import "../IStakeChangeNotifier.sol";

/// @title Elections contract interface
interface IElections /* is IStakeChangeNotifier */ {
	// Election state change events
	event GuardianVotedUnready(address guardian);
	event GuardianVotedOut(address guardian);

	// Function calls
	event VoteUnreadyCasted(address voter, address subject, uint256 expiration);
	event VoteOutCasted(address voter, address subject);
	event StakeChanged(address addr, uint256 selfStake, uint256 delegated_stake, uint256 effective_stake);

	event GuardianStatusUpdated(address addr, bool readyToSync, bool readyForCommittee);

	// Governance
	event VoteUnreadyTimeoutSecondsChanged(uint32 newValue, uint32 oldValue);
	event MinSelfStakePercentMilleChanged(uint32 newValue, uint32 oldValue);
	event VoteOutPercentMilleThresholdChanged(uint32 newValue, uint32 oldValue);
	event VoteUnreadyPercentMilleThresholdChanged(uint32 newValue, uint32 oldValue);

	/*
	 * External methods
	 */

	/// @dev Called by a guardian as part of the automatic vote-out flow
	function voteUnready(address subject_addr, uint expiration) external;

	/// @dev casts a voteOut vote by the sender to the given address
	function voteOut(address subjectAddr) external;

	/// @dev Called by a guardian when ready to start syncing with other nodes
	function readyToSync() external;

	/// @dev Called by a guardian when ready to join the committee, typically after syncing is complete or after being voted out
	function readyForCommittee() external;

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
	function guardianUnregistered(address addr) external                      /* onlyGuardiansRegistrationContract */;

	/// @dev Called by: guardian registration contract
	/// Notifies on a guardian certification change
	function guardianCertificationChanged(address addr, bool isCertified) external /* onlyCertificationContract */;

	/*
     * Governance
	 */

	function setMinSelfStakePercentMille(uint32 minSelfStakePercentMille) external /* onlyFunctionalManager onlyWhenActive */;
	function setVoteOutPercentMilleThreshold(uint32 voteUnreadyPercentMilleThreshold) external /* onlyFunctionalManager onlyWhenActive */;
	function setVoteUnreadyPercentMilleThreshold(uint32 voteUnreadyPercentMilleThreshold) external /* onlyFunctionalManager onlyWhenActive */;

	function getMinSelfStakePercentMille() external view returns (uint32);
	function getVoteOutPercentMilleThreshold() external view returns (uint32);
	function getVoteUnreadyPercentMilleThreshold() external view returns (uint32);

	function getSettings() external view returns (
		uint32 minSelfStakePercentMille,
		uint32 voteUnreadyPercentMilleThreshold,
		uint32 voteOutPercentMilleThreshold
	);

	function getAccumulatedStakesForVoteOut(address addr) external view returns (uint256);
	function getVoteOutStatus(address subjectAddr) external view returns (uint votedStake, uint totalDelegatedStake);
	function getVoteOutVote(address addr) external view returns (address);
	function getVoteUnreadyStatus(address subjectAddr) external view returns
		(address[] memory committee, uint256[] memory weights, bool[] memory certification, bool[] memory votes, bool subjectInCommittee, bool subjectInCertifiedCommittee);
	function getEffectiveStake(address addr) external view returns (uint effectiveStake);
}

