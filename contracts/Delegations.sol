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
		address prevDelegatee = getDelegation(msg.sender);

		uint256 prevGovStakePrevDelegatee = getGovernanceEffectiveStake(prevDelegatee);
		uint256 prevGovStakeNewDelegatee = getGovernanceEffectiveStake(to);

		delegations[msg.sender] = to; // delegation!

		uint256 delegatorStake = getStakingContract().getStakeBalanceOf(msg.sender);

		uint256 newStakePrevDelegatee = uncappedStakes[prevDelegatee].sub(delegatorStake);
		uncappedStakes[prevDelegatee] = newStakePrevDelegatee;
		totalGovernanceStake = totalGovernanceStake.sub(prevGovStakePrevDelegatee).add(getGovernanceEffectiveStake(prevDelegatee));

		uint256 newStakeNewDelegatee = uncappedStakes[to].add(delegatorStake);
		uncappedStakes[to] = newStakeNewDelegatee;
		totalGovernanceStake = totalGovernanceStake.sub(prevGovStakeNewDelegatee).add(getGovernanceEffectiveStake(to));

    	getElectionsContract().notifyDelegationChange(to, prevDelegatee, newStakePrevDelegatee, newStakeNewDelegatee, prevGovStakePrevDelegatee, prevGovStakeNewDelegatee);

		emit Delegated(msg.sender, to);
		emitDelegatedStakeChanged(prevDelegatee, msg.sender, delegatorStake);
		if (prevDelegatee != to) {
			emitDelegatedStakeChanged(to, msg.sender, delegatorStake);
		}
	}

	function stakeChange(address _stakeOwner, uint256 _amount, bool _sign, uint256 _updatedStake) external onlyStakingContract {
		_stakeChange(_stakeOwner, _amount, _sign);
		emitDelegatedStakeChanged(getDelegation(_stakeOwner), _stakeOwner, _updatedStake);
	}

	function emitDelegatedStakeChanged(address _delegate, address delegator, uint256 delegatorStake) private {
		uint256 delegateSelfBalance = getStakingContract().getStakeBalanceOf(_delegate);
		address[] memory delegators = new address[](1);
		uint256[] memory delegatorTotalStakes = new uint256[](1);
		delegators[0] = delegator;
		delegatorTotalStakes[0] = delegatorStake;
		emit DelegatedStakeChanged(_delegate, delegateSelfBalance, uncappedStakes[_delegate], delegators, delegatorTotalStakes);
	}

	function emitDelegatedStakeChanged(address[] memory delegators, uint256[] memory delegatorsStakes) private {
		uint delegatorsLength = delegators.length;

		address streakDelegate = (delegatorsLength > 0) ? getDelegation(delegators[0]): address(0);
		uint streakStartIdx = 0;

		for (uint i = 1; i <= delegatorsLength; i++) { // group delegators by delegates. assume sorted by delegate

			bool closingIteration = i == delegatorsLength;
			if (!closingIteration && getDelegation(delegators[i]) == streakDelegate) {
				continue; // delegate streak continues
			}

			// end of delegate streak - emit event
			uint sliceLen =  i - streakStartIdx;
			address[] memory delegatorsSlice = new address[](sliceLen);
			uint256[] memory delegatorTotalStakesSlice = new uint256[](sliceLen);
			for (uint j = 0; j < sliceLen; j++) {
				delegatorsSlice[j] = delegators[j + streakStartIdx];
				delegatorTotalStakesSlice[j] = delegatorsStakes[j + streakStartIdx];
			}
			emit DelegatedStakeChanged(
				streakDelegate,
				getStakingContract().getStakeBalanceOf(streakDelegate),
				uncappedStakes[streakDelegate],
				delegatorsSlice,
				delegatorTotalStakesSlice
			);

			// reset vars for next streak
			if (!closingIteration) {
				streakDelegate = getDelegation(delegators[i]);
				streakStartIdx = i;
			}
		}
	}

	// TODO add testing to this method - not sure a "late" notification will not break assumptions in Elections contract
	function stakeChangeBatch(address[] calldata _stakeOwners, uint256[] calldata _amounts, bool[] calldata _signs, uint256[] calldata _updatedStakes) external onlyStakingContract {
		uint batchLength = _stakeOwners.length;
		require(batchLength == _amounts.length, "_stakeOwners, _amounts - array length mismatch");
		require(batchLength == _signs.length, "_stakeOwners, _signs - array length mismatch");
		require(batchLength == _updatedStakes.length, "_stakeOwners, _updatedStakes - array length mismatch");

		_stakeChangeBatch(_stakeOwners, _amounts, _signs);

		emitDelegatedStakeChanged(_stakeOwners, _updatedStakes);

	}

	function getDelegation(address addr) public view returns (address) {
		address d = delegations[addr];
		return (d == address(0)) ? addr : d;
	}

	function stakeMigration(address _stakeOwner, uint256 _amount) external onlyStakingContract {}

	function _stakeChangeBatch(address[] memory _stakeOwners, uint256[] memory _amounts, bool[] memory _signs) private {
		uint256[] memory newUncappedStakes = new uint256[](_stakeOwners.length);
		uint256[] memory  prevGovStakeOwners = new uint256[](_stakeOwners.length);
		address[] memory  delegatees = new address[](_stakeOwners.length);
		uint256[] memory  prevGovStakeDelegatees = new uint256[](_stakeOwners.length);

		for (uint i = 0; i < _stakeOwners.length; i++) {
			(newUncappedStakes[i], prevGovStakeOwners[i], delegatees[i], prevGovStakeDelegatees[i]) = _applyStakeChangeLocally(_stakeOwners[i], _amounts[i], _signs[i]);
		}

		getElectionsContract().notifyStakeChangeBatch(_stakeOwners, newUncappedStakes, prevGovStakeOwners, delegatees, prevGovStakeDelegatees);
	}

	function _stakeChange(address _stakeOwner, uint256 _amount, bool _sign) private {
		(uint256 newUncappedStake, uint256 prevGovStakeOwner, address delegatee, uint256 prevGovStakeDelegatee) = _applyStakeChangeLocally(_stakeOwner, _amount, _sign);
		getElectionsContract().notifyStakeChange(_stakeOwner, newUncappedStake, prevGovStakeOwner, delegatee, prevGovStakeDelegatee);
	}

	function _applyStakeChangeLocally(address _stakeOwner, uint256 _amount, bool _sign) private returns (uint256 newUncappedStake, uint prevGovStakeOwner, address delegatee, uint256 prevGovStakeDelegatee) {
		delegatee = getDelegation(_stakeOwner);

		prevGovStakeOwner = getGovernanceEffectiveStake(_stakeOwner);
		prevGovStakeDelegatee = getGovernanceEffectiveStake(delegatee);

		if (_sign) {
			newUncappedStake = uncappedStakes[delegatee].add(_amount);
		} else {
			newUncappedStake = uncappedStakes[delegatee].sub(_amount);
		}

		uncappedStakes[delegatee] = newUncappedStake;

		totalGovernanceStake = totalGovernanceStake.sub(prevGovStakeDelegatee).add(getGovernanceEffectiveStake(delegatee));

		return (newUncappedStake, prevGovStakeOwner, delegatee, prevGovStakeDelegatee);
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

	function _isSelfDelegating(address validator) private view returns (bool) {
		return delegations[validator] == address(0) || delegations[validator] == validator;
	}
}
