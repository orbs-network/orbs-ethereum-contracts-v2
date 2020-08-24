pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./Subscriptions.sol";
import "./ContractRegistry.sol";

contract MonthlySubscriptionPlan is ContractRegistryAccessor, WithClaimableFunctionalOwnership {

    string public tier;
    uint256 public monthlyRate;

    IERC20 erc20;

    constructor(IContractRegistry _contractRegistry, IERC20 _erc20, string memory _tier, uint256 _monthlyRate) ContractRegistryAccessor(_contractRegistry) public {
        require(bytes(_tier).length > 0, "must specify a valid tier label");

        tier = _tier;
        erc20 = _erc20;
        monthlyRate = _monthlyRate;
    }

    function createVC(string calldata name, uint256 amount, bool isCertified, string calldata deploymentSubset) external {
        require(amount > 0, "must include funds");

        ISubscriptions subs = getSubscriptionsContract();
        require(erc20.transferFrom(msg.sender, address(this), amount), "failed to transfer subscription fees");
        require(erc20.approve(address(subs), amount), "failed to transfer subscription fees");
        subs.createVC(name, tier, monthlyRate, amount, msg.sender, isCertified, deploymentSubset);
    }

    function extendSubscription(uint256 vcid, uint256 amount) external {
        require(amount > 0, "must include funds");

        ISubscriptions subs = getSubscriptionsContract();

        require(erc20.transferFrom(msg.sender, address(this), amount), "failed to transfer subscription fees from vc payer to subscriber");
        require(erc20.approve(address(subs), amount), "failed to approve subscription fees to subscriptions by subscriber");
        subs.extendSubscription(vcid, amount, msg.sender);
    }

//    ISubscriptions subscriptionsContract;
//    function refreshContracts() external {
//        subscriptionsContract = getSubscriptionsContract();
//    }

}
