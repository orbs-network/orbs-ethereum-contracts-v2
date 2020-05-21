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

contract Delegations is IDelegations, IStakeChangeNotifier, ContractRegistryAccessor {
	using SafeMath for uint256;

	// TODO consider using structs instead of multiple mappings
	mapping (address => uint256) uncappedStakes;
	uint256 totalGovernanceStake; // TODO - move to elections

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

		uint256 prevGovStakePrevDelegate = getGovernanceEffectiveStake(prevDelegate);
		uint256 prevGovStakeNewDelegate = getGovernanceEffectiveStake(to);

		delegations[msg.sender] = to; // delegation!

		uint256 delegatorStake = getStakingContract().getStakeBalanceOf(msg.sender);

		uint256 newStakePrevDelegate = uncappedStakes[prevDelegate].sub(delegatorStake);
		uncappedStakes[prevDelegate] = newStakePrevDelegate;
		totalGovernanceStake = totalGovernanceStake.sub(prevGovStakePrevDelegate).add(getGovernanceEffectiveStake(prevDelegate));

		uint256 newStakeNewDelegate = uncappedStakes[to].add(delegatorStake);
		uncappedStakes[to] = newStakeNewDelegate;
		totalGovernanceStake = totalGovernanceStake.sub(prevGovStakeNewDelegate).add(getGovernanceEffectiveStake(to));

    	getElectionsContract().notifyDelegationChange(to, prevDelegate, newStakePrevDelegate, newStakeNewDelegate, prevGovStakePrevDelegate, prevGovStakeNewDelegate);

		emit Delegated(msg.sender, to);

		if (delegatorStake != 0) {
			emitDelegatedStakeChanged(prevDelegate, msg.sender, delegatorStake);
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

	function emitDelegatedStakeChangedBatch(address[] memory delegators, uint256[] memory delegatorsStakes, address[] memory delegates) private {
		uint delegatorsLength = delegators.length;

		address streakDelegate = (delegatorsLength > 0) ? getDelegation(delegators[0]): address(0);
		uint streakStartIdx = 0;

		for (uint i = 1; i < delegatorsLength; i++) { // group delegators by delegates. assume sorted by delegate
			address currentDelegate = delegates[i];

			if (currentDelegate == streakDelegate) {
				continue; // delegate streak continues
			}

			// end of common delegate streak - emit event
			emitDelegatedStakeChangedSlice(streakDelegate, delegators, delegatorsStakes, streakStartIdx, i - streakStartIdx);

			// reset vars for next streak
			streakDelegate = currentDelegate;
			streakStartIdx = i;
		}

		// final streak
		if (delegatorsLength > 0) {
			emitDelegatedStakeChangedSlice(streakDelegate, delegators, delegatorsStakes, streakStartIdx, delegatorsLength - streakStartIdx);
		}
	}

	// TODO add testing to this method - not sure a "late" notification will not break assumptions in Elections contract
	function stakeChangeBatch(address[] calldata _stakeOwners, uint256[] calldata _amounts, bool[] calldata _signs, uint256[] calldata _updatedStakes) external onlyStakingContract {
		uint batchLength = _stakeOwners.length;
		require(batchLength == _amounts.length, "_stakeOwners, _amounts - array length mismatch");
		require(batchLength == _signs.length, "_stakeOwners, _signs - array length mismatch");
		require(batchLength == _updatedStakes.length, "_stakeOwners, _updatedStakes - array length mismatch");

		address[] memory delegates = _stakeChangeBatch(_stakeOwners, _amounts, _signs);

		emitDelegatedStakeChangedBatch(_stakeOwners, _updatedStakes, delegates);

	}

	function getDelegation(address addr) public view returns (address) {
		address d = delegations[addr];
		return (d == address(0)) ? addr : d;
	}

	function stakeMigration(address _stakeOwner, uint256 _amount) external onlyStakingContract {}

	function _stakeChangeBatch(address[] memory _stakeOwners, uint256[] memory _amounts, bool[] memory _signs) private returns (address[] memory delegates){
		uint256[] memory newUncappedStakes = new uint256[](_stakeOwners.length);
		uint256[] memory prevGovStakeOwners = new uint256[](_stakeOwners.length);
		uint256[] memory prevGovStakeDelegates = new uint256[](_stakeOwners.length);
		delegates = new address[](_stakeOwners.length);

		for (uint i = 0; i < _stakeOwners.length; i++) {
			(newUncappedStakes[i], prevGovStakeOwners[i], delegates[i], prevGovStakeDelegates[i]) = _applyStakeChangeLocally(_stakeOwners[i], _amounts[i], _signs[i]);
		}

		getElectionsContract().notifyStakeChangeBatch(_stakeOwners, newUncappedStakes, prevGovStakeOwners, delegates, prevGovStakeDelegates);

		return delegates;
	}

	function _stakeChange(address _stakeOwner, uint256 _amount, bool _sign) private {
		(uint256 newUncappedStake, uint256 prevGovStakeOwner, address _delegate, uint256 prevGovStakeDelegate) = _applyStakeChangeLocally(_stakeOwner, _amount, _sign);
		getElectionsContract().notifyStakeChange(_stakeOwner, newUncappedStake, prevGovStakeOwner, _delegate, prevGovStakeDelegate);
	}

	function _applyStakeChangeLocally(address _stakeOwner, uint256 _amount, bool _sign) private returns (uint256 newUncappedStake, uint prevGovStakeOwner, address _delegate, uint256 prevGovStakeDelegate) {
		_delegate = getDelegation(_stakeOwner);

		prevGovStakeOwner = getGovernanceEffectiveStake(_stakeOwner);
		prevGovStakeDelegate = getGovernanceEffectiveStake(_delegate);

		if (_sign) {
			newUncappedStake = uncappedStakes[_delegate].add(_amount);
		} else {
			newUncappedStake = uncappedStakes[_delegate].sub(_amount);
		}

		uncappedStakes[_delegate] = newUncappedStake;

		totalGovernanceStake = totalGovernanceStake.sub(prevGovStakeDelegate).add(getGovernanceEffectiveStake(_delegate));

		return (newUncappedStake, prevGovStakeOwner, _delegate, prevGovStakeDelegate);
	}

	function getDelegatedStakes(address addr) external view returns (uint256) {
		return uncappedStakes[addr];
	}

	function getTotalGovernanceStake() public view returns (uint256) {
		return totalGovernanceStake;
	}

    function getGovernanceEffectiveStake(address v) public view returns (uint256) {
		return _isSelfDelegating(v) ? uncappedStakes[v] : 0;
	}

	function getSelfDelegatedStake(address addr) public view returns (uint256) {
		return _isSelfDelegating(addr) ? getStakingContract().getStakeBalanceOf(addr) : 0;
	}

	function _isSelfDelegating(address addr) private view returns (bool) {
		address d = delegations[addr];
		return  d == address(0) || d == addr;
	}
}
