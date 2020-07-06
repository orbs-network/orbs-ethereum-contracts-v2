pragma solidity 0.5.16;

import "../spec_interfaces/IContractRegistry.sol";
import "../IStakeChangeNotifier.sol";

/// @title Elections contract interface
interface IElections /* is IStakeChangeNotifier */ {
	// Election state change events
	event ValidatorVotedUnready(address validator);
	event ValidatorVotedOut(address validator);
	event ValidatorVotedIn(address validator);

	// Function calls
	event VoteUnreadyCasted(address voter, address subject);
	event VoteOutCasted(address voter, address[] subjects);
	event ReadyToSync(address validator);
	event ReadyForCommittee(address validator);
	event StakeChanged(address addr, uint256 selfStake, uint256 delegated_stake, uint256 effective_stake);

	event ValidatorStatusUpdated(address addr, bool readyToSync, bool readyForCommittee);

	/*
	 *   External methods
	 */
	/// @dev Called by a validator as part of the automatic vote-out flow
	function voteUnready(address subjectAddr) external;

	/// @dev casts a voteOut vote by the sender to the given address
	function voteOut(address[] calldata subjectAddrs) external;

	/// @dev Called by a validator when ready to start syncing with other nodes
	function readyToSync() external;

	/// @dev Called by a validator when ready to join the committee, typically after syncing is complete or after being voted out
	function readyForCommittee() external;

	/*
	 *   Methods restricted to other Orbs contracts
	 */

	/// @dev Called by: validator registration contract
	/// Notifies a new validator was registered
	function validatorRegistered(address addr) external /* onlyValidatorsRegistrationContract */;

	/// @dev Called by: validator registration contract
	/// Notifies a new validator was unregistered
	function validatorUnregistered(address addr) external /* onlyValidatorsRegistrationContract */;

	/// @dev Called by: validator registration contract
	/// Notifies on a validator compliance change
	function validatorComplianceChanged(address addr, bool isCompliant) external /* onlyComplianceContract */;

	function delegatedStakeChange(address addr, uint256 selfStake, uint256 totalDelegated, uint256 deltaTotalDelegated, bool signDeltaTotalDelegated) external /* onlyDelegationContract */;

	function getSettings() external view returns (
		uint32 voteUnreadyTimeoutSeconds,
		uint32 maxDelegationRatio,
		uint32 voteOutLockTimeoutSeconds,
		uint8 voteUnreadyPercentageThreshold,
		uint8 voteOutPercentageThreshold
	);

	/*
     * Governance
	 */

	function setVoteUnreadyTimeoutSeconds(uint32 voteUnreadyTimeoutSeconds) external /* onlyFunctionalOwner onlyWhenActive */;
	function setMaxDelegationRatio(uint32 maxDelegationRatio) external /* onlyFunctionalOwner onlyWhenActive */;
	function setVoteOutLockTimeoutSeconds(uint32 voteOutLockTimeoutSeconds) external /* onlyFunctionalOwner onlyWhenActive */;
	function setVoteOutPercentageThreshold(uint8 voteUnreadyPercentageThreshold) external /* onlyFunctionalOwner onlyWhenActive */;
	function setVoteUnreadyPercentageThreshold(uint8 voteUnreadyPercentageThreshold) external /* onlyFunctionalOwner onlyWhenActive */;

	event VoteUnreadyTimeoutSecondsChanged(uint32 newValue, uint32 oldValue);
	event MaxDelegationRatioChanged(uint32 newValue, uint32 oldValue);
	event VoteOutLockTimeoutSecondsChanged(uint32 newValue, uint32 oldValue);
	event VoteOutPercentageThresholdChanged(uint8 newValue, uint8 oldValue);
	event VoteUnreadyPercentageThresholdChanged(uint8 newValue, uint8 oldValue);

}

