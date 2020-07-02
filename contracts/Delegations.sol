pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "./spec_interfaces/ICommitteeListener.sol";
import "./interfaces/IElections.sol";
import "./spec_interfaces/IValidatorsRegistration.sol";
import "./IStakingContract.sol";
import "./spec_interfaces/ICommittee.sol";
import "./spec_interfaces/ICompliance.sol";
import "./ContractRegistryAccessor.sol";
import "./spec_interfaces/IDelegation.sol";
import "./WithClaimableFunctionalOwnership.sol";
import "./IStakeChangeNotifier.sol";

contract Delegations is IDelegations, IStakeChangeNotifier, ContractRegistryAccessor, WithClaimableFunctionalOwnership, Lockable {
	using SafeMath for uint256;

	// TODO consider using structs instead of multiple mappings
	mapping (address => uint256) uncappedStakes;

	mapping (address => address) delegations;

	modifier onlyStakingContract() {
		require(msg.sender == address(getStakingContract()), "caller is not the staking contract");

		_;
	}

	constructor() public {}

	function notifyOnDelegationChange(address delegate, bool wasSelfDelegated, uint prevTotalUncapped, bool isSelfDelegated, uint currentTotalUncapped) private {
		uint prevTotal = wasSelfDelegated ? prevTotalUncapped : 0;
		uint currentTotal = isSelfDelegated ? currentTotalUncapped : 0;
		bool deltaSign = currentTotal > prevTotal;
		uint delta = deltaSign ? currentTotal.sub(prevTotal) : prevTotal.sub(currentTotal);

		getElectionsContract().delegatedStakeChange(
			delegate,
			getStakingContract().getStakeBalanceOf(delegate),
			currentTotal,
			delta,
			deltaSign
		);
	}

	function delegate(address to) external onlyWhenActive {
		address prevDelegate = getDelegation(msg.sender);

		require(to != address(0), "cannot delegate to a zero address");
		require(to != prevDelegate, "delegation already in place");

		uint256 prevStakePrevDelegate = uncappedStakes[prevDelegate];
		uint256 prevStakeNewDelegate = uncappedStakes[to];

		bool prevSelfDelegatingPrevDelegate = _isSelfDelegating(prevDelegate);
		bool prevSelfDelegatingNewDelegate = _isSelfDelegating(to);

		delegations[msg.sender] = to;

		uint256 delegatorStake = getStakingContract().getStakeBalanceOf(msg.sender);

		uint256 newStakePrevDelegate = prevStakePrevDelegate.sub(delegatorStake);
		uncappedStakes[prevDelegate] = newStakePrevDelegate;

		uint256 newStakeNewDelegate = prevStakeNewDelegate.add(delegatorStake);
		uncappedStakes[to] = newStakeNewDelegate;

		notifyOnDelegationChange(prevDelegate, prevSelfDelegatingPrevDelegate, prevStakePrevDelegate, _isSelfDelegating(prevDelegate), newStakePrevDelegate);
		notifyOnDelegationChange(to, prevSelfDelegatingNewDelegate, prevStakeNewDelegate, _isSelfDelegating(to), newStakeNewDelegate);

		emit Delegated(msg.sender, to);

		if (delegatorStake != 0) {
			emitDelegatedStakeChanged(prevDelegate, msg.sender, 0);
			emitDelegatedStakeChanged(to, msg.sender, delegatorStake);
		}
	}

	function stakeChange(address _stakeOwner, uint256 _amount, bool _sign, uint256 _updatedStake) external onlyStakingContract onlyWhenActive {
		_stakeChange(_stakeOwner, _amount, _sign, _updatedStake);
		emitDelegatedStakeChanged(getDelegation(_stakeOwner), _stakeOwner, _updatedStake);
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
		address d = delegations[addr];
		return (d == address(0)) ? addr : d;
	}

	function stakeMigration(address _stakeOwner, uint256 _amount) external onlyStakingContract onlyWhenActive {}

	function _processStakeChangeBatch(address[] memory stakeOwners, uint256[] memory amounts, bool[] memory signs, uint256[] memory updatedStakes) private {
		uint batchLength = stakeOwners.length;
		uint delegateSelfStake;
		uint delta;
		bool deltaSign;

		uint i = 0;
		while (i < batchLength) {
			// init sequence
			address sequenceDelegate = getDelegation(stakeOwners[i]);
			uint currentUncappedStake = uncappedStakes[sequenceDelegate];
			uint prevUncappedStake = currentUncappedStake;
			bool isSelfDelegatingDelegate = _isSelfDelegating(sequenceDelegate);

			uint sequenceStartIdx = i;

			do { // aggregate sequence stakes changes
				currentUncappedStake = signs[i] ?
					currentUncappedStake.add(amounts[i]) :
					currentUncappedStake.sub(amounts[i]);

				i++;
			} while (i < batchLength && sequenceDelegate == getDelegation(stakeOwners[i]));

			// closing sequence
			uncappedStakes[sequenceDelegate] = currentUncappedStake;
			emitDelegatedStakeChangedSlice(sequenceDelegate, stakeOwners, updatedStakes, sequenceStartIdx, i - sequenceStartIdx);
			delegateSelfStake = getStakingContract().getStakeBalanceOf(sequenceDelegate);

			if (!isSelfDelegatingDelegate) {
				getElectionsContract().delegatedStakeChange(sequenceDelegate, delegateSelfStake, currentUncappedStake, 0, true);
			} else {
				deltaSign = currentUncappedStake > prevUncappedStake;
				delta = deltaSign ? currentUncappedStake.sub(prevUncappedStake) : prevUncappedStake.sub(currentUncappedStake);
				getElectionsContract().delegatedStakeChange(sequenceDelegate, delegateSelfStake, currentUncappedStake, delta, deltaSign);
			}
		}
	}

	function _stakeChange(address _stakeOwner, uint256 _amount, bool _sign, uint256 _total) private {
		address _delegate = getDelegation(_stakeOwner);

		uint256 prevUncappedStake = uncappedStakes[_delegate];

		uint256 newUncappedStake;
		if (_sign) {
			newUncappedStake = prevUncappedStake.add(_amount);
		} else {
			newUncappedStake = prevUncappedStake.sub(_amount);
		}

		uncappedStakes[_delegate] = newUncappedStake;

		bool isSelfDelegating = _isSelfDelegating(_delegate);
		getElectionsContract().delegatedStakeChange(
			_delegate,
			getStakingContract().getStakeBalanceOf(_delegate),
			isSelfDelegating ? newUncappedStake : 0,
			isSelfDelegating ? _amount : 0,
			_sign
		);
	}

	function getDelegatedStakes(address addr) external view returns (uint256) {
		return uncappedStakes[addr];
	}

	function getSelfDelegatedStake(address addr) public view returns (uint256) {
		return _isSelfDelegating(addr) ? getStakingContract().getStakeBalanceOf(addr) : 0;
	}

	function _isSelfDelegating(address addr) private view returns (bool) {
		address d = delegations[addr];
		return  d == address(0) || d == addr;
	}
}
