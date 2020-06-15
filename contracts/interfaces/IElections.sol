pragma solidity 0.5.16;

import "../spec_interfaces/IContractRegistry.sol";
import "../IStakeChangeNotifier.sol";

/// @title Elections contract interface
interface IElections /* is IStakeChangeNotifier */ {
	event StakeChanged(address addr, uint256 ownStake, uint256 uncappedStake, uint256 governanceStake, uint256 committeeStake, uint256 totalGovernanceStake);
	event CommitteeChanged(address[] addrs, address[] orbsAddrs, uint256[] stakes);
	event TopologyChanged(address[] orbsAddrs, bytes4[] ips);
	event VoteOut(address voter, address against);
	event VotedOutOfCommittee(address addr);
	event BanningVote(address voter, address[] against);
	event Banned(address validator);
	event Unbanned(address validator);
	event ValidatorStatusUpdated(address addr, bool readyToSync, bool readyForCommittee);

	/*
	 *   External methods
	 */

	/// @dev Called by a validator when ready to start syncing with other nodes
	function notifyReadyToSync() external;

	/// @dev Called by a validator when ready to join the committee, typically after syncing is complete or after being voted out
	function notifyReadyForCommittee() external;

	/// @dev Called by a validator as part of the automatic vote-out flow
	function voteOut(address addr) external;

	/// @dev casts a banning vote by the sender to the given address
	function setBanningVotes(address[] calldata addrs) external;

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

	function notifyStakeChange(uint256 prevDelegateTotalStake, uint256 newDelegateTotalStake, address delegate, bool isSelfDelegatingDelegate) external /*onlyDelegationsContract*/;
	function notifyStakeChangeBatch(uint256[] calldata prevDelegateTotalStakes, uint256[] calldata newDelegateTotalStakes, address[] calldata delegates, bool[] calldata isSelfDelegatingDelegates) external /*onlyDelegationsContract*/;
	function notifyDelegationChange(address delegator, uint256 delegatorSelfStake, address newDelegate, address prevDelegate, uint256 prevDelegateNewTotalStake, uint256 newDelegateNewTotalStake, uint256 prevDelegatePrevTotalStake, bool prevSelfDelegatingPrevDelegate, uint256 newDelegatePrevTotalStake, bool prevSelfDelegatingNewDelegate) external /*onlyDelegationsContract*/;
	function getTotalGovernanceStake() external view returns (uint256);

	function getSettings() external view returns (
		uint32 voteOutTimeoutSeconds,
		uint32 maxDelegationRatio,
		uint32 banningLockTimeoutSeconds,
		uint8 voteOutPercentageThreshold,
		uint8 banningPercentageThreshold
	);

	/*
     * Governance
	 */

	function setVoteOutTimeoutSeconds(uint32 voteOutTimeoutSeconds) external /* onlyFunctionalOwner onlyWhenActive */;
	function setMaxDelegationRatio(uint32 maxDelegationRatio) external /* onlyFunctionalOwner onlyWhenActive */;
	function setBanningLockTimeoutSeconds(uint32 banningLockTimeoutSeconds) external /* onlyFunctionalOwner onlyWhenActive */;
	function setVoteOutPercentageThreshold(uint8 voteOutPercentageThreshold) external /* onlyFunctionalOwner onlyWhenActive */;
	function setBanningPercentageThreshold(uint8 banningPercentageThreshold) external /* onlyFunctionalOwner onlyWhenActive */;

	event VoteOutTimeoutSecondsChanged(uint32 newValue, uint32 oldValue);
	event MaxDelegationRatioChanged(uint32 newValue, uint32 oldValue);
	event BanningLockTimeoutSecondsChanged(uint32 newValue, uint32 oldValue);
	event VoteOutPercentageThresholdChanged(uint8 newValue, uint8 oldValue);
	event BanningPercentageThresholdChanged(uint8 newValue, uint8 oldValue);

}

