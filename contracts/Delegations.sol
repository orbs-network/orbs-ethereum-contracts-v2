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
	using SafeMath for uint128;

	// TODO consider using structs instead of multiple mappings
	struct StakeOwnerData {
		address delegation;
		bool isSelfStakeInitialized;
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
	}

	function getDelegateStatus(address addr) private view returns (DelegateStatus memory status) {
		status.addr = addr;
		status.uncappedStakes = uncappedStakes[addr];
		status.isSelfDelegating = _isSelfDelegating(addr);
		status.delegatedStake = status.isSelfDelegating ? status.uncappedStakes : 0;

		return status;
	}

	function delegateFrom(address from, address to, bool notifyElections) private {
		address prevDelegate = getDelegation(from);

		require(to != address(0), "cannot delegate to a zero address");

		DelegateStatus memory prevDelegateStatusBefore = getDelegateStatus(prevDelegate);
		DelegateStatus memory newDelegateStatusBefore = getDelegateStatus(to);

		stakeOwnersData[from].delegation = to;

		uint256 delegatorStake = getStakingContract().getStakeBalanceOf(from);

		if (stakeOwnersData[from].isSelfStakeInitialized) {
			uncappedStakes[prevDelegate] = prevDelegateStatusBefore.uncappedStakes.sub(delegatorStake);
		} else {
			stakeOwnersData[from].isSelfStakeInitialized = true;
		}
		uncappedStakes[to] = newDelegateStatusBefore.uncappedStakes.add(delegatorStake);

		DelegateStatus memory prevDelegateStatusAfter = getDelegateStatus(prevDelegate);
		DelegateStatus memory newDelegateStatusAfter = getDelegateStatus(to);

		totalDelegatedStake = totalDelegatedStake.sub(
			prevDelegateStatusBefore.delegatedStake
		).add(
			prevDelegateStatusAfter.delegatedStake
		).sub(
			newDelegateStatusBefore.delegatedStake
		).add(
			newDelegateStatusAfter.delegatedStake
		);

		if (notifyElections) {
			IElections elections = getElectionsContract();
			IStakingContract staking = getStakingContract();

			elections.delegatedStakeChange(
				prevDelegate,
				staking.getStakeBalanceOf(prevDelegate),
				prevDelegateStatusAfter.delegatedStake
			);

			elections.delegatedStakeChange(
				to,
				staking.getStakeBalanceOf(to),
				newDelegateStatusAfter.delegatedStake
			);
		}

		emit Delegated(from, to);

		if (delegatorStake != 0 && prevDelegate != to) {
			emitDelegatedStakeChanged(prevDelegate, from, 0);
			emitDelegatedStakeChanged(to, from, delegatorStake);
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
			_stakeChange(from[i], 0, true, getStakingContract().getStakeBalanceOf(from[i]), notifyElections);
			delegateFrom(from[i], to[i], notifyElections);
		}

		emit DelegationsImported(from, to, notifyElections);
	}

	function finalizeDelegationImport() external onlyMigrationOwner onlyDuringDelegationImport {
		delegationImportFinalized = true;
		emit DelegationImportFinalized();
	}

	function refreshStakeNotification(address addr) external onlyWhenActive {
		_stakeChange(addr, 0, true, getStakingContract().getStakeBalanceOf(addr), true);
	}

	function stakeChange(address _stakeOwner, uint256 _amount, bool _sign, uint256 _updatedStake) external onlyStakingContract onlyWhenActive {
		_stakeChange(_stakeOwner, _amount, _sign, _updatedStake, true);
	}

	function emitDelegatedStakeChanged(address _delegate, address delegator, uint256 delegatorStake) private {
		address[] memory delegators = new address[](1);
		uint256[] memory delegatorTotalStakes = new uint256[](1);

		delegators[0] = delegator;
		delegatorTotalStakes[0] = delegatorStake;

		emit DelegatedStakeChanged(
			_delegate,
			getSelfDelegatedStake(_delegate),
			uncappedStakes[_delegate],
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

		_processStakeChangeBatch(_stakeOwners, _amounts, _signs, _updatedStakes);
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

	function _processStakeChangeBatch(address[] memory stakeOwners, uint256[] memory amounts, bool[] memory signs, uint256[] memory updatedStakes) private {
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

				if (!curStakeOwnerData.isSelfStakeInitialized) {
					amounts[i] = updatedStakes[i];
					signs[i] = true;
					stakeOwnersData[stakeOwners[i]].isSelfStakeInitialized = true;
				}

				currentUncappedStake = signs[i] ?
					currentUncappedStake.add(amounts[i]) :
					currentUncappedStake.sub(amounts[i]);
			}

			// closing sequence
			uncappedStakes[sequenceDelegate] = currentUncappedStake;
			emitDelegatedStakeChangedSlice(sequenceDelegate, stakeOwners, updatedStakes, sequenceStartIdx, i - sequenceStartIdx);
			delegateSelfStake = getStakingContract().getStakeBalanceOf(sequenceDelegate);

			if (_isSelfDelegating(sequenceDelegate)) {
				totalDelegatedStake = totalDelegatedStake.sub(prevUncappedStake).add(currentUncappedStake);
			}
		}
	}

	function _stakeChange(address _stakeOwner, uint256 _amount, bool _sign, uint256 _updatedStake, bool notifyElections) private {
		StakeOwnerData memory stakeOwnerData = getStakeOwnerData(_stakeOwner);

		uint256 prevUncappedStake = uncappedStakes[stakeOwnerData.delegation];

		if (!stakeOwnerData.isSelfStakeInitialized) {
			_amount = _updatedStake;
			_sign = true;
			stakeOwnersData[_stakeOwner].isSelfStakeInitialized = true;
		}

		uint256 newUncappedStake = _sign ? prevUncappedStake.add(_amount) : prevUncappedStake.sub(_amount);

		uncappedStakes[stakeOwnerData.delegation] = newUncappedStake;

		bool isSelfDelegating = _isSelfDelegating(stakeOwnerData.delegation);
		if (isSelfDelegating) {
			totalDelegatedStake = _sign ? totalDelegatedStake.add(_amount) : totalDelegatedStake.sub(_amount);
		}

		if (notifyElections) {
			getElectionsContract().delegatedStakeChange(
				stakeOwnerData.delegation,
				getStakingContract().getStakeBalanceOf(stakeOwnerData.delegation),
				isSelfDelegating ? newUncappedStake : 0
			);
		}

		if (_amount > 0) {
			emitDelegatedStakeChanged(stakeOwnerData.delegation, _stakeOwner, _updatedStake);
		}
	}

	function getDelegatedStakes(address addr) external view returns (uint256) {
		return _isSelfDelegating(addr) ? uncappedStakes[addr] : 0;
	}

	function getSelfDelegatedStake(address addr) public view returns (uint256) {
		return _isSelfDelegating(addr) ? getStakingContract().getStakeBalanceOf(addr) : 0;
	}

	function _isSelfDelegating(address addr) private view returns (bool) {
		return  getDelegation(addr) == addr;
	}
}
