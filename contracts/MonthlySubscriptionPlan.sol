// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./Subscriptions.sol";
import "./ContractRegistry.sol";

/// @title monthly subscription plan contract
contract MonthlySubscriptionPlan is ContractRegistryAccessor {

    string public tier;
    uint256 public monthlyRate;

    IERC20 public erc20;

    /// Constructor
    /// @param _contractRegistry is the contract registry address
    /// @param _registryAdmin is the registry admin address
    /// @param _erc20 is the token used for virtual chains fees
    /// @param _tier is the virtual chain tier for the monthly subscription plan
    /// @param _monthlyRate is the virtual chain tier rate
    constructor(IContractRegistry _contractRegistry, address _registryAdmin, IERC20 _erc20, string memory _tier, uint256 _monthlyRate) ContractRegistryAccessor(_contractRegistry, _registryAdmin) public {
        require(bytes(_tier).length > 0, "must specify a valid tier label");

        tier = _tier;
        erc20 = _erc20;
        monthlyRate = _monthlyRate;
    }

    /*
     *   External functions
     */

    /// Creates a new virtual chain
    /// @dev the virtual chain tier and rate are determined by the contract
    /// @dev the contract calls the subscription contract that stores the virtual chain data and allocates a virtual chain ID
    /// @dev the msg.sender that created the virtual chain is set as the initial virtual chain owner
    /// @dev the initial amount paid for the virtual chain must be large than minimumInitialVcPayment
    /// @param name is the virtual chain name
    /// @param amount is the amount paid for the virtual chain initial subscription
    /// @param isCertified indicates the virtual is run by the certified committee
    /// @param deploymentSubset indicates the code deployment subset the virtual chain uses such as main or canary  
    function createVC(string calldata name, uint256 amount, bool isCertified, string calldata deploymentSubset) external {
        require(amount > 0, "must include funds");

        ISubscriptions subs = ISubscriptions(getSubscriptionsContract());
        require(erc20.transferFrom(msg.sender, address(this), amount), "failed to transfer subscription fees");
        require(erc20.approve(address(subs), amount), "failed to transfer subscription fees");
        subs.createVC(name, tier, monthlyRate, amount, msg.sender, isCertified, deploymentSubset);
    }

    /// Extends the subscription of an existing virtual chain.
    /// @dev may be called by anyone, not only the virtual chain owner
    /// @dev assumes that the amount has been approved by the msg.sender prior to calling the function 
    /// @param vcId is the virtual chain ID
    /// @param amount is the amount paid for the virtual chain subscription extension
    function extendSubscription(uint256 vcId, uint256 amount) external {
        require(amount > 0, "must include funds");

        ISubscriptions subs = ISubscriptions(getSubscriptionsContract());
        require(erc20.transferFrom(msg.sender, address(this), amount), "failed to transfer subscription fees from vc payer to subscriber");
        require(erc20.approve(address(subs), amount), "failed to approve subscription fees to subscriptions by subscriber");
        subs.extendSubscription(vcId, amount, tier, monthlyRate, msg.sender);
    }

}
