pragma solidity 0.5.16;

import "./IContractRegistry.sol";

/// @title Elections contract interface
interface IDelegations /* is IStakeChangeNotifier */ {
    // Delegation state change events
    event DelegatedStakeChanged(address addr, uint256 selfStake, uint256 delegatedStake);

    // Function calls
	event Delegated(address from, address to);

	/*
     * External methods
     */

	/// @dev Stake delegation
	function delegate(address to) external;

	/*
	 * Governance
	 */

    /// @dev Updates the address calldata of the contract registry
	function setContractRegistry(IContractRegistry _contractRegistry) external /* onlyOwner */;

	/*
	 * Getters
	 */

}
