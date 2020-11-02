// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./SafeMath96.sol";
import "./spec_interfaces/IElections.sol";
import "./spec_interfaces/IDelegations.sol";
import "./IStakeChangeNotifier.sol";
import "./spec_interfaces/IStakingContractHandler.sol";
import "./spec_interfaces/IStakingRewards.sol";
import "./ManagedContract.sol";

/// @title Delegations contract
contract Delegations is IDelegations, IStakeChangeNotifier, ManagedContract {
	using SafeMath for uint256;
	using SafeMath96 for uint96;

	address constant public VOID_ADDR = address(-1);

	struct StakeOwnerData {
		address delegation;
		uint96 stake;
	}
	mapping(address => StakeOwnerData) public stakeOwnersData;
	mapping(address => uint256) public uncappedDelegatedStake;

	uint256 totalDelegatedStake;

	struct DelegateStatus {
		address addr;
		uint256 uncappedDelegatedStake;
		bool isSelfDelegating;
		uint256 delegatedStake;
		uint96 selfDelegatedStake;
	}

    /// Constructor
    /// @param _contractRegistry is the contract registry address
    /// @param _registryAdmin is the registry admin address
	constructor(IContractRegistry _contractRegistry, address _registryAdmin) ManagedContract(_contractRegistry, _registryAdmin) public {
		address VOID_ADDRESS_DUMMY_DELEGATION = address(-2);
		assert(VOID_ADDR != VOID_ADDRESS_DUMMY_DELEGATION && VOID_ADDR != address(0) && VOID_ADDRESS_DUMMY_DELEGATION != address(0));
		stakeOwnersData[VOID_ADDR].delegation = VOID_ADDRESS_DUMMY_DELEGATION;
	}

	modifier onlyStakingContractHandler() {
		require(msg.sender == address(stakingContractHandler), "caller is not the staking contract handler");

		_;
	}

	/*
	* External functions
	*/

    /// Delegate your stake
    /// @dev updates the election contract on the changes in the delegated stake
    /// @dev updates the rewards contract on the upcoming change in the delegator's delegation state
    /// @param to is the address to delegate to
	function delegate(address to) external override onlyWhenActive {
		delegateFrom(msg.sender, to);
	}

    /// Refresh the address stake for delegation power based on the staking contract
    /// @dev Disabled stake change update notifications from the staking contract may create mismatches
    /// @dev refreshStake re-syncs the stake data with the staking contract
    /// @param addr is the address to refresh its stake
	function refreshStake(address addr) external override onlyWhenActive {
		_stakeChange(addr, stakingContractHandler.getStakeBalanceOf(addr));
	}

    /// Refresh the addresses stake for delegation power based on the staking contract
    /// @dev Batched version of refreshStake
    /// @dev Disabled stake change update notifications from the staking contract may create mismatches
    /// @dev refreshStakeBatch re-syncs the stake data with the staking contract
    /// @param addrs is the list of addresses to refresh their stake
	function refreshStakeBatch(address[] calldata addrs) external override onlyWhenActive {
		for (uint i = 0; i < addrs.length; i++) {
			_stakeChange(addrs[i], stakingContractHandler.getStakeBalanceOf(addrs[i]));
		}
	}

    /// Returns the delegate address of the given address
    /// @param addr is the address to query
    /// @return delegation is the address the addr delegated to
	function getDelegation(address addr) external override view returns (address) {
		return getStakeOwnerData(addr).delegation;
	}

    /// Returns a delegator info
    /// @param addr is the address to query
    /// @return delegation is the address the addr delegated to
    /// @return delegatorStake is the stake of the delegator as reflected in the delegation contract
	function getDelegationInfo(address addr) external override view returns (address delegation, uint256 delegatorStake) {
		StakeOwnerData memory data = getStakeOwnerData(addr);
		return (data.delegation, data.stake);
	}

    /// Returns the delegated stake of an addr 
    /// @dev an address that is not self delegating has a 0 delegated stake
    /// @param addr is the address to query
    /// @return delegatedStake is the address delegated stake
	function getDelegatedStake(address addr) external override view returns (uint256) {
		return getDelegateStatus(addr).delegatedStake;
	}

    /// Returns the total delegated stake
    /// @dev delegatedStake - the total stake delegated to an address that is self delegating
    /// @dev the delegated stake of a non self-delegated address is 0
    /// @return totalDelegatedStake is the total delegatedStake of all the addresses
	function getTotalDelegatedStake() external override view returns (uint256) {
		return totalDelegatedStake;
	}

	/*
	* Notifications from staking contract (IStakeChangeNotifier)
	*/

    /// Notifies of stake change event.
    /// @param _stakeOwner is the address of the subject stake owner.
    /// @param _updatedStake is the updated total staked amount.
	function stakeChange(address _stakeOwner, uint256, bool, uint256 _updatedStake) external override onlyStakingContractHandler onlyWhenActive {
		_stakeChange(_stakeOwner, _updatedStake);
	}

    /// Notifies of multiple stake change events.
    /// @param _stakeOwners is the addresses of subject stake owners.
    /// @param _amounts is the differences in total staked amounts.
    /// @param _signs is the signs of the added (true) or subtracted (false) amounts.
    /// @param _updatedStakes is the updated total staked amounts.
	function stakeChangeBatch(address[] calldata _stakeOwners, uint256[] calldata _amounts, bool[] calldata _signs, uint256[] calldata _updatedStakes) external override onlyStakingContractHandler onlyWhenActive {
		uint batchLength = _stakeOwners.length;
		require(batchLength == _amounts.length, "_stakeOwners, _amounts - array length mismatch");
		require(batchLength == _signs.length, "_stakeOwners, _signs - array length mismatch");
		require(batchLength == _updatedStakes.length, "_stakeOwners, _updatedStakes - array length mismatch");

		for (uint i = 0; i < _stakeOwners.length; i++) {
			_stakeChange(_stakeOwners[i], _updatedStakes[i]);
		}
	}

    /// Notifies of stake migration event.
    /// @dev Empty function. A staking contract migration may be handled in the future in the StakingContractHandler 
    /// @param _stakeOwner address The address of the subject stake owner.
    /// @param _amount uint256 The migrated amount.
	function stakeMigration(address _stakeOwner, uint256 _amount) external override onlyStakingContractHandler onlyWhenActive {}

	/*
	* Governance functions
	*/

    /// Imports delegations during initial migration
    /// @dev initialization function called only by the initializationManager
    /// @dev Does not update the Rewards or Election contracts
    /// @dev assumes deactivated Rewards
    /// @param from is a list of delegator addresses
    /// @param to is the address the delegators delegate to
	function importDelegations(address[] calldata from, address to) external override onlyInitializationAdmin {
		require(to != address(0), "to must be a non zero address");
		require(from.length > 0, "from array must contain at least one address");
		(uint96 stakingRewardsPerWeight, ) = stakingRewardsContract.getStakingRewardsState();
		require(stakingRewardsPerWeight == 0, "no rewards may be allocated prior to importing delegations");

		uint256 uncappedDelegatedStakeDelta = 0;
		StakeOwnerData memory data;
		uint256 newTotalDelegatedStake = totalDelegatedStake;
		DelegateStatus memory delegateStatus = getDelegateStatus(to);
		IStakingContractHandler _stakingContractHandler = stakingContractHandler;
		uint256 delegatorUncapped;
		uint256[] memory delegatorsStakes = new uint256[](from.length);
		for (uint i = 0; i < from.length; i++) {
			data = stakeOwnersData[from[i]];
			require(data.delegation == address(0), "import allowed only for uninitialized accounts. existing delegation detected");
			require(from[i] != to, "import cannot be used for self-delegation (already self delegated)");
			require(data.stake == 0 , "import allowed only for uninitialized accounts. existing stake detected");

			// from[i] stops being self delegating. any uncappedDelegatedStake it has now stops being counted towards totalDelegatedStake
			delegatorUncapped = uncappedDelegatedStake[from[i]];
			if (delegatorUncapped > 0) {
				newTotalDelegatedStake = newTotalDelegatedStake.sub(delegatorUncapped);
				emit DelegatedStakeChanged(
					from[i],
					0,
					0,
					from[i],
					0
				);
			}

			// update state
			data.delegation = to;
			data.stake = uint96(_stakingContractHandler.getStakeBalanceOf(from[i]));
			stakeOwnersData[from[i]] = data;

			uncappedDelegatedStakeDelta = uncappedDelegatedStakeDelta.add(data.stake);

			// store individual stake for event
			delegatorsStakes[i] = data.stake;

			emit Delegated(from[i], to);

			emit DelegatedStakeChanged(
				to,
				delegateStatus.selfDelegatedStake,
				delegateStatus.isSelfDelegating ? delegateStatus.delegatedStake.add(uncappedDelegatedStakeDelta) : 0,
				from[i],
				data.stake
			);
		}

		// update totals
		uncappedDelegatedStake[to] = uncappedDelegatedStake[to].add(uncappedDelegatedStakeDelta);

		if (delegateStatus.isSelfDelegating) {
			newTotalDelegatedStake = newTotalDelegatedStake.add(uncappedDelegatedStakeDelta);
		}
		totalDelegatedStake = newTotalDelegatedStake;

		// emit events
		emit DelegationsImported(from, to);
	}

    /// Initializes the delegation of an address during initial migration 
    /// @dev initialization function called only by the initializationManager
    /// @dev behaves identically to a delegate transaction sent by the delegator
    /// @param from is the delegator addresses
    /// @param to is the delegator delegates to
	function initDelegation(address from, address to) external override onlyInitializationAdmin {
		delegateFrom(from, to);
		emit DelegationInitialized(from, to);
	}

	/*
	* Private functions
	*/

    /// Generates and returns an internal memory structure with a Delegate status
    /// @dev updated based on the up to date state
    /// @dev status.addr is the queried address
    /// @dev status.uncappedDelegatedStake is the amount delegated to address including self-delegated stake
    /// @dev status.isSelfDelegating indicates whether the address is self-delegated
    /// @dev status.selfDelegatedStake if the addr is self-delegated is  the addr self stake. 0 if not self-delegated
    /// @dev status.delegatedStake if the addr is self-delegated is the mount delegated to address. 0 if not self-delegated
	function getDelegateStatus(address addr) private view returns (DelegateStatus memory status) {
		StakeOwnerData memory data = getStakeOwnerData(addr);

		status.addr = addr;
		status.uncappedDelegatedStake = uncappedDelegatedStake[addr];
		status.isSelfDelegating = data.delegation == addr;
		status.selfDelegatedStake = status.isSelfDelegating ? data.stake : 0;
		status.delegatedStake = status.isSelfDelegating ? status.uncappedDelegatedStake : 0;

		return status;
	}

    /// Returns an address stake and delegation data. 
    /// @dev implicitly self-delegated addresses (delegation = 0) return delegation to the address
	function getStakeOwnerData(address addr) private view returns (StakeOwnerData memory data) {
		data = stakeOwnersData[addr];
		data.delegation = (data.delegation == address(0)) ? addr : data.delegation;
		return data;
	}

	struct DelegateFromVars {
		DelegateStatus prevDelegateStatusBefore;
		DelegateStatus newDelegateStatusBefore;
		DelegateStatus prevDelegateStatusAfter;
		DelegateStatus newDelegateStatusAfter;
	}

    /// Handles a delegation change
    /// @dev notifies the rewards contract on the expected change (with data prior to the change)
    /// @dev updates the impacted delegates delegated stake and the total stake
    /// @dev notifies the election contract on changes in the impacted delegates delegated stake
    /// @param from is the delegator address 
    /// @param to is the delegate address
	function delegateFrom(address from, address to) private {
		require(to != address(0), "cannot delegate to a zero address");

		DelegateFromVars memory vars;

		StakeOwnerData memory delegatorData = getStakeOwnerData(from);

		// Optimization - no need for the full flow in the case of a zero staked delegator with no delegations
		if (delegatorData.stake == 0 && uncappedDelegatedStake[from] == 0) {
			stakeOwnersData[from].delegation = to;
			emit Delegated(from, to);
			return;
		}

		address prevDelegate = delegatorData.delegation;

		vars.prevDelegateStatusBefore = getDelegateStatus(prevDelegate);
		vars.newDelegateStatusBefore = getDelegateStatus(to);

		stakingRewardsContract.delegationWillChange(prevDelegate, vars.prevDelegateStatusBefore.delegatedStake, from, delegatorData.stake, to, vars.newDelegateStatusBefore.delegatedStake);

		stakeOwnersData[from].delegation = to;

		uint256 delegatorStake = delegatorData.stake;

		uncappedDelegatedStake[prevDelegate] = vars.prevDelegateStatusBefore.uncappedDelegatedStake.sub(delegatorStake);
		uncappedDelegatedStake[to] = vars.newDelegateStatusBefore.uncappedDelegatedStake.add(delegatorStake);

		vars.prevDelegateStatusAfter = getDelegateStatus(prevDelegate);
		vars.newDelegateStatusAfter = getDelegateStatus(to);

		uint256 _totalDelegatedStake = totalDelegatedStake.sub(
			vars.prevDelegateStatusBefore.delegatedStake
		).add(
			vars.prevDelegateStatusAfter.delegatedStake
		).sub(
			vars.newDelegateStatusBefore.delegatedStake
		).add(
			vars.newDelegateStatusAfter.delegatedStake
		);

		totalDelegatedStake = _totalDelegatedStake;

		emit Delegated(from, to);

		IElections _electionsContract = electionsContract;

		if (vars.prevDelegateStatusBefore.delegatedStake != vars.prevDelegateStatusAfter.delegatedStake) {
			_electionsContract.delegatedStakeChange(
				prevDelegate,
				vars.prevDelegateStatusAfter.selfDelegatedStake,
				vars.prevDelegateStatusAfter.delegatedStake,
				_totalDelegatedStake
			);

			emit DelegatedStakeChanged(
				prevDelegate,
				vars.prevDelegateStatusAfter.selfDelegatedStake,
				vars.prevDelegateStatusAfter.delegatedStake,
				from,
				0
			);
		}

		if (vars.newDelegateStatusBefore.delegatedStake != vars.newDelegateStatusAfter.delegatedStake) {
			_electionsContract.delegatedStakeChange(
				to,
				vars.newDelegateStatusAfter.selfDelegatedStake,
				vars.newDelegateStatusAfter.delegatedStake,
				_totalDelegatedStake
			);

			emit DelegatedStakeChanged(
				to,
				vars.newDelegateStatusAfter.selfDelegatedStake,
				vars.newDelegateStatusAfter.delegatedStake,
				from,
				delegatorStake
			);
		}
	}

    /// Handles a change in a stake owner stake
    /// @dev notifies the rewards contract on the expected change (with data prior to the change)
    /// @dev updates the impacted delegate delegated stake and the total stake
    /// @dev notifies the election contract on changes in the impacted delegate delegated stake
    /// @param _stakeOwner is the stake owner
    /// @param _updatedStake is the stake owner stake after the change
	function _stakeChange(address _stakeOwner, uint256 _updatedStake) private {
		StakeOwnerData memory stakeOwnerDataBefore = getStakeOwnerData(_stakeOwner);
		DelegateStatus memory delegateStatusBefore = getDelegateStatus(stakeOwnerDataBefore.delegation);

		uint256 prevUncappedStake = delegateStatusBefore.uncappedDelegatedStake;
		uint256 newUncappedStake = prevUncappedStake.sub(stakeOwnerDataBefore.stake).add(_updatedStake);

		stakingRewardsContract.delegationWillChange(stakeOwnerDataBefore.delegation, delegateStatusBefore.delegatedStake, _stakeOwner, stakeOwnerDataBefore.stake, stakeOwnerDataBefore.delegation, delegateStatusBefore.delegatedStake);

		uncappedDelegatedStake[stakeOwnerDataBefore.delegation] = newUncappedStake;

		require(uint256(uint96(_updatedStake)) == _updatedStake, "Delegations::updatedStakes value too big (>96 bits)");
		stakeOwnersData[_stakeOwner].stake = uint96(_updatedStake);

		uint256 _totalDelegatedStake = totalDelegatedStake;
		if (delegateStatusBefore.isSelfDelegating) {
			_totalDelegatedStake = _totalDelegatedStake.sub(stakeOwnerDataBefore.stake).add(_updatedStake);
			totalDelegatedStake = _totalDelegatedStake;
		}

		DelegateStatus memory delegateStatusAfter = getDelegateStatus(stakeOwnerDataBefore.delegation);

		electionsContract.delegatedStakeChange(
			stakeOwnerDataBefore.delegation,
			delegateStatusAfter.selfDelegatedStake,
			delegateStatusAfter.delegatedStake,
			_totalDelegatedStake
		);

		if (_updatedStake != stakeOwnerDataBefore.stake) {
			emit DelegatedStakeChanged(
				stakeOwnerDataBefore.delegation,
				delegateStatusAfter.selfDelegatedStake,
				delegateStatusAfter.delegatedStake,
				_stakeOwner,
				_updatedStake
			);
		}
	}

	/*
     * Contracts topology / registry interface
     */

	IElections electionsContract;
	IStakingRewards stakingRewardsContract;
	IStakingContractHandler stakingContractHandler;

    /// Refreshes the address of the other contracts the contract interacts with
    /// @dev called by the registry contract upon an update of a contract in the registry
	function refreshContracts() external override {
		electionsContract = IElections(getElectionsContract());
		stakingContractHandler = IStakingContractHandler(getStakingContractHandler());
		stakingRewardsContract = IStakingRewards(getStakingRewardsContract());
	}

}
