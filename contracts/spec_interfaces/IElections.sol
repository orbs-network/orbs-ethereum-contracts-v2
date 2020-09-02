pragma solidity 0.5.16;

import "./IContractRegistry.sol";

/// @title Elections contract interface
interface IElections /* is IStakeChangeNotifier */ {
    // Election state change events
    event GuardianVotedUnready(address guardian);
    event GuardianVotedOut(address guardian);
	event GuardianVotedIn(address guardian);

    // Function calls
    event VoteUnreadyCasted(address voter, address subject, uint expiration);
    event VoteOutCasted(address voter, address[] subjects);
	event StakeChanged(address addr, uint256 selfStake, uint256 delegated_stake, uint256 effective_stake);

	// Guardian readiness
	event GuardianStatusUpdated(address addr, bool readyToSync, bool readyForCommittee);

	// Governance
	event VoteUnreadyTimeoutSecondsChanged(uint32 newValue, uint32 oldValue);
	event MinSelfStakePercentMilleChanged(uint32 newValue, uint32 oldValue);
	event VoteOutLockTimeoutSecondsChanged(uint32 newValue, uint32 oldValue);
	event VoteOutPercentMilleThresholdChanged(uint32 newValue, uint32  oldValue);
	event VoteUnreadyPercentMilleThresholdChanged(uint32 newValue, uint32 oldValue);


	/*
     * External methods
     */

    /// @dev Called by a guardian as part of the automatic vote unready flow
	function voteUnready(address subject_addr) external;

    /// @dev Called by a guardian as part of the vote-out flow
	function voteOut(address[] calldata subject_addrs) external;

	/// @dev Called by a guardian when ready to join the committee, typically after syncing is complete or after being voted unready
	function readyForSync() external;

	/// @dev Called by a guardian when ready to join the committee, typically after syncing is complete or after being voted unready
	function readyForCommittee() external;

	/*
     * Methods restricted to other Orbs contracts
     */

	/// @dev Called by: delegation contract
	/// Notifies a delegated stake change event
	/// total_delegated_stake = 0 if addr delegates to another guardian
	function delegatedStakeChange(address addr, uint256 selfStake, uint256 total_delegated, uint256 delta_total_delegated, bool sign_total_delegated) external /* onlyDelegationContract */;

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

    /// @dev Updates the address calldata of the contract registry
	function setContractRegistry(IContractRegistry _contractRegistry) external /* onlyMigrationManager */;

}
