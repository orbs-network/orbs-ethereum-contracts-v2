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

	modifier onlyStakingContract() {
		require(msg.sender == address(getStakingContract()), "caller is not the staking contract");

		_;
	}
	event debug(address elections);

	constructor() public {
	}

	function delegate(address to) external {
		getElectionsContract().delegate1(msg.sender, to);
		emit Delegated(msg.sender, to);
	}

	function stakeChange(address _stakeOwner, uint256 _amount, bool _sign, uint256 _updatedStake) external onlyStakingContract {
		getElectionsContract().stakeChange1(_stakeOwner, _amount, _sign, _updatedStake);
		//emit DelegatedStakeChanged(address addr, uint256 selfSstake, uint256 delegatedStake);
	}

    function stakeChangeBatch(address[] calldata _stakeOwners, uint256[] calldata _amounts, bool[] calldata _signs, uint256[] calldata _updatedStakes) external onlyStakingContract {
		getElectionsContract().stakeChangeBatch1(_stakeOwners, _amounts, _signs, _updatedStakes);
	}

	function getDelegation(address delegator) external view returns (address) {
		return getElectionsContract().getDelegation1(delegator);
	}

	function stakeMigration(address _stakeOwner, uint256 _amount) external onlyStakingContract {}

	function refreshStakes(address[] calldata addrs) external {
		getElectionsContract().refreshStakes1(addrs);
	}

}
