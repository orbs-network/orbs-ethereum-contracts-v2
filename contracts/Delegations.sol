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

contract Delegations is IDelegations, IStakeChangeNotifier, ContractRegistryAccessor, WithClaimableFunctionalOwnership {
	using SafeMath for uint256;

	// TODO consider using structs instead of multiple mappings
	mapping (address => uint256) uncappedStakes;

	mapping (address => address) delegations;

	modifier onlyStakingContract() {
		require(msg.sender == address(getStakingContract()), "caller is not the staking contract");

		_;
	}

	constructor() public {
	}

	function delegate(address to) external {
		address prevDelegate = getDelegation(msg.sender);

		require(to != address(0), "cannot delegate to a zero address");
		require(to != prevDelegate, "delegation already in place");

		uint256 prevStakePrevDelegate = uncappedStakes[prevDelegate];
		uint256 prevStakeNewDelegate = uncappedStakes[to];

		bool prevSelfDelegatingPrevDelegate = _isSelfDelegating(prevDelegate);
		bool prevSelfDelegatingNewDelegate = _isSelfDelegating(to);

		delegations[msg.sender] = to; // delegation!

		uint256 delegatorStake = getStakingContract().getStakeBalanceOf(msg.sender);

		uint256 newStakePrevDelegate = prevStakePrevDelegate.sub(delegatorStake);
		uncappedStakes[prevDelegate] = newStakePrevDelegate;

		uint256 newStakeNewDelegate = prevStakeNewDelegate.add(delegatorStake);
		uncappedStakes[to] = newStakeNewDelegate;

    	getElectionsContract().notifyDelegationChange(
			msg.sender,
			delegatorStake,
			to,
			prevDelegate,
			newStakePrevDelegate,
			newStakeNewDelegate,
			prevStakePrevDelegate,
			prevSelfDelegatingPrevDelegate,
			prevStakeNewDelegate,
			prevSelfDelegatingNewDelegate
		);

		emit Delegated(msg.sender, to);

		if (delegatorStake != 0) {
			emitDelegatedStakeChanged(prevDelegate, msg.sender, 0);
			emitDelegatedStakeChanged(to, msg.sender, delegatorStake);
		}
	}

	function stakeChange(address _stakeOwner, uint256 _amount, bool _sign, uint256 _updatedStake) external onlyStakingContract {
		_stakeChange(_stakeOwner, _amount, _sign);
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
	function stakeChangeBatch(address[] calldata _stakeOwners, uint256[] calldata _amounts, bool[] calldata _signs, uint256[] calldata _updatedStakes) external onlyStakingContract {
		uint batchLength = _stakeOwners.length;
		require(batchLength == _amounts.length, "_stakeOwners, _amounts - array length mismatch");
		require(batchLength == _signs.length, "_stakeOwners, _signs - array length mismatch");
		require(batchLength == _updatedStakes.length, "_stakeOwners, _updatedStakes - array length mismatch");

		ProcessSequencesParams memory params;
		params.stakeOwners = _stakeOwners;
		params.amounts = _amounts;
		params.signs = _signs;
		params.updatedStakes = _updatedStakes;

		_processStakeChangeBatch(params);
	}

	function getDelegation(address addr) public view returns (address) {
		address d = delegations[addr];
		return (d == address(0)) ? addr : d;
	}

	function stakeMigration(address _stakeOwner, uint256 _amount) external onlyStakingContract {}

	struct ProcessSequencesParams {
		address[] stakeOwners;
		uint256[] amounts;
		bool[] signs;
		uint256[] updatedStakes;
	}

	function _processStakeChangeBatch(ProcessSequencesParams memory params) private {
		uint batchLength = params.stakeOwners.length;
		if (batchLength == 0) {
			return;
		}
		address[] memory delegates = new address[](batchLength);

		// find delegates and number of sequences
		uint sequenceCount = 0;
		address sequenceDelegate = address(0);
		for (uint i = 0; i < batchLength; i++) { // count sequences and gather addresses
			delegates[i] = getDelegation(params.stakeOwners[i]);
			if (sequenceDelegate != delegates[i]) { // init record new delegate, and close previous one
				sequenceCount++;
				sequenceDelegate = delegates[i];
			}
		}

		uint256[] memory prevUncappedStakes = new uint256[](sequenceCount);
		uint256[] memory newUncappedStakes = new uint256[](sequenceCount);
		bool[] memory isSelfDelegatingDelegates = new bool[](sequenceCount);
		address[] memory seqDelegates = new address[](sequenceCount);

		sequenceCount = 0;
		sequenceDelegate = address(0);
		uint currentUncappedStake;
		uint sequenceStartIdx;
		uint sequenceLength;

		for (uint i = 0; i < batchLength; i++) {
			if (sequenceDelegate != delegates[i]) {
				if (sequenceCount > 0) { // close prev seq
					uncappedStakes[sequenceDelegate] = currentUncappedStake;
					newUncappedStakes[sequenceCount - 1] = currentUncappedStake;
					emitDelegatedStakeChangedSlice(sequenceDelegate, params.stakeOwners, params.updatedStakes, sequenceStartIdx, sequenceLength);
				}
				// init next seq
				sequenceDelegate = delegates[i];
				currentUncappedStake = uncappedStakes[sequenceDelegate];
				seqDelegates[sequenceCount] = sequenceDelegate;
				prevUncappedStakes[sequenceCount] = currentUncappedStake;
				isSelfDelegatingDelegates[sequenceCount] = _isSelfDelegating(sequenceDelegate);

				sequenceStartIdx = i;
				sequenceCount++;
				sequenceLength = 0;

			}
			sequenceLength++;

			if (params.signs[i]) {
				currentUncappedStake = currentUncappedStake.add(params.amounts[i]);
			} else {
				currentUncappedStake = currentUncappedStake.sub(params.amounts[i]);
			}
		}

		// close the last seq
		uncappedStakes[sequenceDelegate] = currentUncappedStake;
		newUncappedStakes[sequenceCount - 1] = currentUncappedStake;
		emitDelegatedStakeChangedSlice(sequenceDelegate, params.stakeOwners, params.updatedStakes, sequenceStartIdx, sequenceLength);

		getElectionsContract().notifyStakeChangeBatch(prevUncappedStakes, newUncappedStakes, seqDelegates, isSelfDelegatingDelegates);
	}

	function _stakeChange(address _stakeOwner, uint256 _amount, bool _sign) private {
		address _delegate = getDelegation(_stakeOwner);

		uint256 prevUncappedStake = uncappedStakes[_delegate];

		uint256 newUncappedStake;
		if (_sign) {
			newUncappedStake = prevUncappedStake.add(_amount);
		} else {
			newUncappedStake = prevUncappedStake.sub(_amount);
		}

		uncappedStakes[_delegate] = newUncappedStake;

		getElectionsContract().notifyStakeChange(prevUncappedStake, newUncappedStake, _delegate, _isSelfDelegating(_delegate));
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
