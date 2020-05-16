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
	}

	function stakeChange(address _stakeOwner, uint256 _amount, bool _sign, uint256 /* _updatedStake */) external onlyStakingContract {
		_stakeChange(_stakeOwner, _amount, _sign);
		//TODO? emit DelegatedStakeChanged(address addr, uint256 selfSstake, uint256 delegatedStake);
	}

	// TODO add testing to this method - not sure a "late" notification will not break assumptions in Elections contract
	function stakeChangeBatch(address[] calldata _stakeOwners, uint256[] calldata _amounts, bool[] calldata _signs, uint256[] calldata _updatedStakes) external onlyStakingContract {
		require(_stakeOwners.length == _amounts.length, "_stakeOwners, _amounts - array length mismatch");
		require(_stakeOwners.length == _signs.length, "_stakeOwners, _signs - array length mismatch");
		require(_stakeOwners.length == _updatedStakes.length, "_stakeOwners, _updatedStakes - array length mismatch");

		_stakeChangeBatch(_stakeOwners, _amounts, _signs);
		//TODO? emit DelegatedStakeChanged(address addr, uint256 selfSstake, uint256 delegatedStake);
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
