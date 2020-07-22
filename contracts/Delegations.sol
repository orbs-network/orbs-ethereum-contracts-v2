pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "./spec_interfaces/ICommitteeListener.sol";
import "./interfaces/IElections.sol";
import "./spec_interfaces/IGuardiansRegistration.sol";
import "./IStakingContract.sol";
import "./spec_interfaces/ICommittee.sol";
import "./spec_interfaces/ICertification.sol";
import "./ContractRegistryAccessor.sol";
import "./spec_interfaces/IDelegation.sol";
import "./WithClaimableFunctionalOwnership.sol";
import "./IStakeChangeNotifier.sol";

contract Delegations is IDelegations, IStakeChangeNotifier, ContractRegistryAccessor, WithClaimableFunctionalOwnership, Lockable {
	using SafeMath for uint256;
	using SafeMath for uint96;

	// TODO consider using structs instead of multiple mappings
	struct StakeOwnerData {
		address delegation;
		uint96 stake;
	}
	mapping (address => StakeOwnerData) stakeOwnersData;
	mapping (address => uint256) uncappedStakes;

	uint256 totalDelegatedStake;

	modifier onlyStakingContract() {
		require(msg.sender == address(getStakingContract()), "caller is not the staking contract");

		_;
	}

	constructor() public {}

	function getTotalDelegatedStake() external view returns (uint256) {
		return totalDelegatedStake;
	}

	struct DelegateStatus {
		address addr;
		uint256 uncappedStakes;
		bool isSelfDelegating;
		uint256 delegatedStake;
		uint96 selfDelegatedStake;
	}

	function getDelegateStatus(address addr) private view returns (DelegateStatus memory status) {
		StakeOwnerData memory data = getStakeOwnerData(addr);

		status.addr = addr;
		status.uncappedStakes = uncappedStakes[addr];
		status.isSelfDelegating = data.delegation == addr;
		status.selfDelegatedStake = status.isSelfDelegating ? data.stake : 0;
		status.delegatedStake = status.isSelfDelegating ? status.uncappedStakes : 0;

		return status;
	}

	function delegateFrom(address from, address to, bool notifyElections) private {
		require(to != address(0), "cannot delegate to a zero address");

		StakeOwnerData memory delegatorData = getStakeOwnerData(from);
		address prevDelegate = delegatorData.delegation;

		DelegateStatus memory prevDelegateStatusBefore = getDelegateStatus(prevDelegate);
		DelegateStatus memory newDelegateStatusBefore = getDelegateStatus(to);

		stakeOwnersData[from].delegation = to;

		uint256 delegatorStake = delegatorData.stake;

		uncappedStakes[prevDelegate] = prevDelegateStatusBefore.uncappedStakes.sub(delegatorStake);
		uncappedStakes[to] = newDelegateStatusBefore.uncappedStakes.add(delegatorStake);

		DelegateStatus memory prevDelegateStatusAfter = getDelegateStatus(prevDelegate);
		DelegateStatus memory newDelegateStatusAfter = getDelegateStatus(to);

		uint256 _totalDelegatedStake = totalDelegatedStake.sub(
			prevDelegateStatusBefore.delegatedStake
		).add(
			prevDelegateStatusAfter.delegatedStake
		).sub(
			newDelegateStatusBefore.delegatedStake
		).add(
			newDelegateStatusAfter.delegatedStake
		);

		totalDelegatedStake = _totalDelegatedStake;

		uint256 prevDelegateSelfDelegatedStake = prevDelegateStatusAfter.selfDelegatedStake;
		uint256 newDelegateSelfDelegatedStake = newDelegateStatusAfter.selfDelegatedStake;

		if (notifyElections) {
			IElections elections = getElectionsContract();

			elections.delegatedStakeChange(
				prevDelegate,
				prevDelegateSelfDelegatedStake,
				prevDelegateStatusAfter.delegatedStake,
				_totalDelegatedStake
			);

			elections.delegatedStakeChange(
				to,
				newDelegateSelfDelegatedStake,
				newDelegateStatusAfter.delegatedStake,
				_totalDelegatedStake
			);
		}

		emit Delegated(from, to);

		if (delegatorStake != 0 && prevDelegate != to) {
			emitDelegatedStakeChanged(prevDelegate, from, 0, prevDelegateSelfDelegatedStake, prevDelegateStatusAfter.delegatedStake);
			emitDelegatedStakeChanged(to, from, delegatorStake, newDelegateSelfDelegatedStake, newDelegateStatusAfter.delegatedStake);
		}
	}

	function delegate(address to) external onlyWhenActive {
		delegateFrom(msg.sender, to, true);
	}

	bool public delegationImportFinalized;

	modifier onlyDuringDelegationImport {
		require(!delegationImportFinalized, "delegation import was finalized");

		_;
	}

	function importDelegations(address[] calldata from, address[] calldata to, bool notifyElections) external onlyMigrationOwner onlyDuringDelegationImport {
		require(from.length == to.length, "from and to arrays must be of same length");

		for (uint i = 0; i < from.length; i++) {
			_stakeChange(from[i], getStakingContract().getStakeBalanceOf(from[i]), notifyElections);
			delegateFrom(from[i], to[i], notifyElections);
		}

		emit DelegationsImported(from, to, notifyElections);
	}

	function finalizeDelegationImport() external onlyMigrationOwner onlyDuringDelegationImport {
		delegationImportFinalized = true;
		emit DelegationImportFinalized();
	}

	function refreshStakeNotification(address addr) external onlyWhenActive {
		_stakeChange(addr, getStakingContract().getStakeBalanceOf(addr), true);
	}

	function stakeChange(address _stakeOwner, uint256, bool, uint256 _updatedStake) external onlyStakingContract onlyWhenActive {
		_stakeChange(_stakeOwner, _updatedStake, true);
	}

	function emitDelegatedStakeChanged(address _delegate, address delegator, uint256 delegatorStake, uint256 delegateSelfDelegatedStake, uint256 delegateTotalDelegatedStake) private {
		address[] memory delegators = new address[](1);
		uint256[] memory delegatorTotalStakes = new uint256[](1);

		delegators[0] = delegator;
		delegatorTotalStakes[0] = delegatorStake;

		emit DelegatedStakeChanged(
			_delegate,
			delegateSelfDelegatedStake,
			delegateTotalDelegatedStake,
			delegators,
			delegatorTotalStakes
		);
	}

	function emitDelegatedStakeChangedSlice(address commonDelegate, address[] memory delegators, uint256[] memory delegatorsStakes, uint startIdx, uint sliceLen) private {
		address[] memory delegatorsSlice = new address[](sliceLen);
		uint256[] memory delegatorTotalStakesSlice = new uint256[](sliceLen);

		for (uint j = 0; j < sliceLen; j++) {
			delegatorsSlice[j] = delegators[j + startIdx];
			delegatorTotalStakesSlice[j] = delegatorsStakes[j + startIdx];
		}

		emit DelegatedStakeChanged(
			commonDelegate,
			getSelfDelegatedStake(commonDelegate),
			uncappedStakes[commonDelegate],
			delegatorsSlice,
			delegatorTotalStakesSlice
		);
	}

	// TODO add tests to equivalence of batched and non batched notifications
	function stakeChangeBatch(address[] calldata _stakeOwners, uint256[] calldata _amounts, bool[] calldata _signs, uint256[] calldata _updatedStakes) external onlyStakingContract onlyWhenActive {
		uint batchLength = _stakeOwners.length;
		require(batchLength == _amounts.length, "_stakeOwners, _amounts - array length mismatch");
		require(batchLength == _signs.length, "_stakeOwners, _signs - array length mismatch");
		require(batchLength == _updatedStakes.length, "_stakeOwners, _updatedStakes - array length mismatch");

		_processStakeChangeBatch(_stakeOwners, _updatedStakes);
	}

	function getDelegation(address addr) public view returns (address) {
		return getStakeOwnerData(addr).delegation;
	}

	function getStakeOwnerData(address addr) private view returns (StakeOwnerData memory data) {
		data = stakeOwnersData[addr];
		data.delegation = (data.delegation == address(0)) ? addr : data.delegation;
		return data;
	}

	function stakeMigration(address _stakeOwner, uint256 _amount) external onlyStakingContract onlyWhenActive {}

	function _processStakeChangeBatch(address[] memory stakeOwners, uint256[] memory updatedStakes) private {
		uint delegateSelfStake;

		uint i = 0;
		while (i < stakeOwners.length) {
			// init sequence
			StakeOwnerData memory curStakeOwnerData = getStakeOwnerData(stakeOwners[i]);
			address sequenceDelegate = curStakeOwnerData.delegation;
			uint currentUncappedStake = uncappedStakes[sequenceDelegate];
			uint prevUncappedStake = currentUncappedStake;

			uint sequenceStartIdx = i;
			for (i = sequenceStartIdx; i < stakeOwners.length; i++) { // aggregate sequence stakes changes
				if (i != sequenceStartIdx) curStakeOwnerData = getStakeOwnerData(stakeOwners[i]);
				if (sequenceDelegate != curStakeOwnerData.delegation) break;

				currentUncappedStake = currentUncappedStake
				.sub(curStakeOwnerData.stake)
				.add(updatedStakes[i]);

				require(uint256(uint96(uint96(updatedStakes[i]))) == updatedStakes[i], "Delegations::updatedStakes value too big (>96 bits)");
				stakeOwnersData[stakeOwners[i]].stake = uint96(updatedStakes[i]);
			}

			// closing sequence
			uncappedStakes[sequenceDelegate] = currentUncappedStake;
			emitDelegatedStakeChangedSlice(sequenceDelegate, stakeOwners, updatedStakes, sequenceStartIdx, i - sequenceStartIdx);
			delegateSelfStake = getStakeOwnerData(sequenceDelegate).stake;

			if (_isSelfDelegating(sequenceDelegate)) {
				totalDelegatedStake = totalDelegatedStake.sub(prevUncappedStake).add(currentUncappedStake);
			}
		}
	}

	function _stakeChange(address _stakeOwner, uint256 _updatedStake, bool notifyElections) private {
		StakeOwnerData memory stakeOwnerData = getStakeOwnerData(_stakeOwner);

		uint256 prevUncappedStake = uncappedStakes[stakeOwnerData.delegation];

		require(uint256(uint96(_updatedStake)) == _updatedStake, "Delegations::updatedStakes value too big (>96 bits)");
		uint256 newUncappedStake = prevUncappedStake.sub(stakeOwnerData.stake).add(_updatedStake);

		uncappedStakes[stakeOwnerData.delegation] = newUncappedStake;

		stakeOwnersData[_stakeOwner].stake = uint96(_updatedStake);

		bool isSelfDelegating = _isSelfDelegating(stakeOwnerData.delegation);
		uint256 _totalDelegatedStake = totalDelegatedStake;
		if (isSelfDelegating) {
			_totalDelegatedStake = _totalDelegatedStake.sub(stakeOwnerData.stake).add(_updatedStake);
			totalDelegatedStake = _totalDelegatedStake;
		}

		uint256 delegateSelfDelegatedStake = isSelfDelegating ? getStakingContract().getStakeBalanceOf(stakeOwnerData.delegation) : 0;
		if (notifyElections) {
			getElectionsContract().delegatedStakeChange(
				stakeOwnerData.delegation,
				delegateSelfDelegatedStake,
				isSelfDelegating ? newUncappedStake : 0,
				_totalDelegatedStake
			);
		}

		if (_updatedStake != stakeOwnerData.stake) {
			emitDelegatedStakeChanged(stakeOwnerData.delegation, _stakeOwner, _updatedStake, delegateSelfDelegatedStake, isSelfDelegating ? newUncappedStake : 0);
		}
	}

	function getDelegatedStakes(address addr) external view returns (uint256) {
		return _isSelfDelegating(addr) ? uncappedStakes[addr] : 0;
	}

	function getSelfDelegatedStake(address addr) public view returns (uint256) {
		return _isSelfDelegating(addr) ? getStakingContract().getStakeBalanceOf(addr) : 0;
	}

	function _isSelfDelegating(address addr) private view returns (bool) {
		return getDelegation(addr) == addr;
	}
}
