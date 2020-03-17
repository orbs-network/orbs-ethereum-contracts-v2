pragma solidity 0.5.16;

import "./IContractRegistry.sol";

/// @title Elections contract interface
interface IElections /* is IStakeChangeNotifier */ {
    // Election state change events
    event ValidatorVotedUnready(address validator);
    event ValidatorVotedOut(address validator);

    // Function calls
    event VoteUnreadyCasted(address voter, address subject);
    event VoteOutCasted(address voter, address[] subjects);
    event ReadyForSync(address validator);
    event ReadyForCommitee(address validator);
	event StakeChanged(address addr, uint256 selfStake, uint256 delegated_stake, uint256 effective_stake);

	/*
     * External methods
     */

    /// @dev Called by a validator as part of the automatic vote unready flow
	function voteUnready(address subject_addr) external;

    /// @dev Called by a validator as part of the vote-out flow
	function voteOut(address[] calldata subject_addrs) external;

	/// @dev Called by a validator when ready to join the committee, typically after syncing is complete or after being voted unready
	function readyForSync() external;

	/// @dev Called by a validator when ready to join the committee, typically after syncing is complete or after being voted unready
	function readyForCommittee() external;

	/*
     * Methods restricted to other Orbs contracts
     */

	/// @dev Called by: delegation contract
	/// Notifies a delegated stake change event
	/// total_delegated_stake = 0 if addr delegates to another validator
	function delegatedStakeChange(address addr, uint256 selfStake, uint256 total_delegated, uint256 delta_total_delegated, bool sign_total_delegated); /* onlyDelegationContract */;

	/// @dev Called by: delegation contract
	/// Notifies a batch of delegated stake updates - TBD if needed
	function delegatedStakeChangeBatch(address[] calldata addr, uint256[] calldata selfStake, uint256[] calldata delegated_stake); /* onlyDelegationContract */;    

	/// @dev Called by: validator registration contract
	/// Notifies a new validator was registered
	function validatorRegistred(address addr); /* onlyValidatorsRegistrationContract */;    

	/// @dev Called by: validator registration contract
	/// Notifies a new validator was unregistered
	function validatorunegistred(address addr); /* onlyValidatorsRegistrationContract */;    

	/*
	 * Governance
	 */
	
    /// @dev Updates the address calldata of the contract registry
	function setContractRegistry(IContractRegistry _contractRegistry) external /* onlyOwner */;

}
