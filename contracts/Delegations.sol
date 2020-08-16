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
import "./Lockable.sol";

contract Delegations is IDelegations, IStakeChangeNotifier, WithClaimableFunctionalOwnership, Lockable {
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
		require(msg.sender == address(stakingContract), "caller is not the staking contract");

		_;
	}

	constructor(IContractRegistry _contractRegistry, address _registryOwner) Lockable(_contractRegistry, _registryOwner) public {}

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

	function delegateFrom(address from, address to, bool refreshStakeNotification) private {
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

		if (refreshStakeNotification) {
			IElections _electionsContract = electionsContract;

			_electionsContract.delegatedStakeChange(
				prevDelegate,
				prevDelegateStatusAfter.selfDelegatedStake,
				prevDelegateStatusAfter.delegatedStake,
				_totalDelegatedStake
			);

			_electionsContract.delegatedStakeChange(
				to,
			    newDelegateStatusAfter.selfDelegatedStake,
				newDelegateStatusAfter.delegatedStake,
				_totalDelegatedStake
			);
		}

		emit Delegated(from, to);

		if (delegatorStake != 0 && prevDelegate != to) {
			emitDelegatedStakeChanged(prevDelegate, from, 0, prevDelegateStatusAfter.selfDelegatedStake, prevDelegateStatusAfter.delegatedStake);
			emitDelegatedStakeChanged(to, from, delegatorStake, newDelegateStatusAfter.selfDelegatedStake, newDelegateStatusAfter.delegatedStake);
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

	function importDelegations(address[] calldata from, address[] calldata to, bool refreshStakeNotification) external onlyMigrationOwner onlyDuringDelegationImport {
		require(from.length == to.length, "from and to arrays must be of same length");

		for (uint i = 0; i < from.length; i++) {
			_stakeChange(from[i], stakingContract.getStakeBalanceOf(from[i]), refreshStakeNotification);
			delegateFrom(from[i], to[i], refreshStakeNotification);
		}

		emit DelegationsImported(from, to, refreshStakeNotification);
	}

	function finalizeDelegationImport() external onlyMigrationOwner onlyDuringDelegationImport {
		delegationImportFinalized = true;
		emit DelegationImportFinalized();
	}

	function refreshStakeNotification(address addr) external onlyWhenActive {
		StakeOwnerData memory stakeOwnerData = getStakeOwnerData(addr);
		DelegateStatus memory delegateStatus = getDelegateStatus(stakeOwnerData.delegation);
		electionsContract.delegatedStakeChange(
			stakeOwnerData.delegation,
			delegateStatus.selfDelegatedStake,
			delegateStatus.delegatedStake,
			totalDelegatedStake
		);
	}

	function refreshStake(address addr) external onlyWhenActive {
		_stakeChange(addr, stakingContract.getStakeBalanceOf(addr), true);
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

		DelegateStatus memory delegateStatus = getDelegateStatus(commonDelegate);

		emit DelegatedStakeChanged(
			commonDelegate,
			delegateStatus.selfDelegatedStake,
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

				require(uint256(uint96(updatedStakes[i])) == updatedStakes[i], "Delegations::updatedStakes value too big (>96 bits)");
				stakeOwnersData[stakeOwners[i]].stake = uint96(updatedStakes[i]);
			}

			// closing sequence
			uncappedStakes[sequenceDelegate] = currentUncappedStake;
			if (_isSelfDelegating(sequenceDelegate)) {
				totalDelegatedStake = totalDelegatedStake.sub(prevUncappedStake).add(currentUncappedStake);
			}

			emitDelegatedStakeChangedSlice(sequenceDelegate, stakeOwners, updatedStakes, sequenceStartIdx, i - sequenceStartIdx);
		}
	}

	function _stakeChange(address _stakeOwner, uint256 _updatedStake, bool _refreshStakeNotification) private {
		StakeOwnerData memory stakeOwnerDataBefore = getStakeOwnerData(_stakeOwner);
		DelegateStatus memory delegateStatus = getDelegateStatus(stakeOwnerDataBefore.delegation);

		uint256 prevUncappedStake = delegateStatus.uncappedStakes;
		uint256 newUncappedStake = prevUncappedStake.sub(stakeOwnerDataBefore.stake).add(_updatedStake);

		uncappedStakes[stakeOwnerDataBefore.delegation] = newUncappedStake;

		require(uint256(uint96(_updatedStake)) == _updatedStake, "Delegations::updatedStakes value too big (>96 bits)");
		stakeOwnersData[_stakeOwner].stake = uint96(_updatedStake);

		uint256 _totalDelegatedStake = totalDelegatedStake;
		if (delegateStatus.isSelfDelegating) {
			_totalDelegatedStake = _totalDelegatedStake.sub(stakeOwnerDataBefore.stake).add(_updatedStake);
			totalDelegatedStake = _totalDelegatedStake;
		}

		delegateStatus = getDelegateStatus(stakeOwnerDataBefore.delegation);

		if (_refreshStakeNotification) {
			electionsContract.delegatedStakeChange(
				stakeOwnerDataBefore.delegation,
				delegateStatus.selfDelegatedStake,
				delegateStatus.delegatedStake,
				_totalDelegatedStake
			);
		}

		if (_updatedStake != stakeOwnerDataBefore.stake) {
			emitDelegatedStakeChanged(stakeOwnerDataBefore.delegation, _stakeOwner, _updatedStake, delegateStatus.selfDelegatedStake, delegateStatus.delegatedStake);
		}
	}

	function getDelegatedStakes(address addr) external view returns (uint256) {
		return _isSelfDelegating(addr) ? uncappedStakes[addr] : 0;
	}

	function getSelfDelegatedStake(address addr) public view returns (uint256) {
		return _isSelfDelegating(addr) ? stakingContract.getStakeBalanceOf(addr) : 0;
	}

	function _isSelfDelegating(address addr) private view returns (bool) {
		return getDelegation(addr) == addr;
	}

	IElections electionsContract;
	IStakingContract stakingContract;
	function refreshContracts() external {
		electionsContract = getElectionsContract();
		stakingContract = getStakingContract();
	}

}
