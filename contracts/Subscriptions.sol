// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./spec_interfaces/ISubscriptions.sol";
import "./spec_interfaces/IProtocol.sol";
import "./spec_interfaces/IFeesWallet.sol";
import "./ManagedContract.sol";

/// @title Subscriptions contract
contract Subscriptions is ISubscriptions, ManagedContract {
    using SafeMath for uint256;

    struct VirtualChain {
        string name;
        string tier;
        uint256 rate;
        uint expiresAt;
        uint256 genRefTime;
        address owner;
        string deploymentSubset;
        bool isCertified;
    }

    mapping(uint => mapping(string => string)) configRecords;
    mapping(address => bool) public authorizedSubscribers;
    mapping(uint => VirtualChain) virtualChains;

    uint public nextVcId;

    struct Settings {
        uint genesisRefTimeDelay;
        uint256 minimumInitialVcPayment;
    }
    Settings settings;

    IERC20 public erc20;

    /// Constructor
    /// @dev the next allocated virtual chain id on createVC is the next ID after the maximum between the migrated virtual chains and the initialNextVcId
    /// @param _contractRegistry is the contract registry address
    /// @param _registryAdmin is the registry admin address
    /// @param _erc20 is the token used for virtual chains fees 
    /// @param _genesisRefTimeDelay is the initial genesis virtual chain reference time delay from the creation time
    /// @param _minimumInitialVcPayment is the minimum payment required for the initial subscription
    /// @param vcIds is a list of virtual chain ids to migrate from the previous subscription contract
    /// @param initialNextVcId is the initial virtual chain id
    /// @param previousSubscriptionsContract is the previous subscription contract to migrate virtual chains from
    constructor (IContractRegistry _contractRegistry, address _registryAdmin, IERC20 _erc20, uint256 _genesisRefTimeDelay, uint256 _minimumInitialVcPayment, uint[] memory vcIds, uint256 initialNextVcId, ISubscriptions previousSubscriptionsContract) ManagedContract(_contractRegistry, _registryAdmin) public {
        require(address(_erc20) != address(0), "erc20 must not be 0");

        erc20 = _erc20;
        nextVcId = initialNextVcId;

        setGenesisRefTimeDelay(_genesisRefTimeDelay);
        setMinimumInitialVcPayment(_minimumInitialVcPayment);

        for (uint i = 0; i < vcIds.length; i++) {
            importSubscription(vcIds[i], previousSubscriptionsContract);
        }
    }

    modifier onlySubscriber {
        require(authorizedSubscribers[msg.sender], "sender must be an authorized subscriber");

        _;
    }

    /*
     *   External functions
     */

    /// Creates a new virtual chain
    /// @dev Called only by: an authorized subscription plan contract
    /// @dev the initial amount paid for the virtual chain must be large than minimumInitialVcPayment
    /// @param name is the virtual chain name
    /// @param tier is the virtual chain tier
    /// @param rate is the virtual chain tier rate as determined by the subscription plan
    /// @param amount is the amount paid for the virtual chain initial subscription
    /// @param owner is the virtual chain owner. The owner may change virtual chain properties or ser config records
    /// @param isCertified indicates the virtual is run by the certified committee
    /// @param deploymentSubset indicates the code deployment subset the virtual chain uses such as main or canary
    /// @return vcId is the virtual chain ID allocated to the new virtual chain
    /// @return genRefTime is the virtual chain genesis reference time that determines the first block committee
    function createVC(string calldata name, string calldata tier, uint256 rate, uint256 amount, address owner, bool isCertified, string calldata deploymentSubset) external override onlySubscriber onlyWhenActive returns (uint vcId, uint genRefTime) {
        require(owner != address(0), "vc owner cannot be the zero address");
        require(protocolContract.deploymentSubsetExists(deploymentSubset) == true, "No such deployment subset");
        require(amount >= settings.minimumInitialVcPayment, "initial VC payment must be at least minimumInitialVcPayment");

        vcId = nextVcId++;
        genRefTime = now + settings.genesisRefTimeDelay;
        VirtualChain memory vc = VirtualChain({
            name: name,
            expiresAt: block.timestamp,
            genRefTime: genRefTime,
            owner: owner,
            tier: tier,
            rate: rate,
            deploymentSubset: deploymentSubset,
            isCertified: isCertified
        });
        virtualChains[vcId] = vc;

        emit VcCreated(vcId);

        _extendSubscription(vcId, amount, tier, rate, owner);
    }

    /// Extends the subscription of an existing virtual chain.
    /// @dev Called only by: an authorized subscription plan contract
    /// @param vcId is the virtual chain ID
    /// @param amount is the amount paid for the virtual chain subscription extension
    /// @param tier is the virtual chain tier, must match the tier selected in the virtual creation
    /// @param rate is the virtual chain tier rate as determined by the subscription plan
    /// @param payer is the address paying for the subscription extension
    function extendSubscription(uint256 vcId, uint256 amount, string calldata tier, uint256 rate, address payer) external override onlySubscriber onlyWhenActive {
        _extendSubscription(vcId, amount, tier, rate, payer);
    }

    /// Sets a virtual chain config record
    /// @dev may be called only by the virtual chain owner
    /// @param vcId is the virtual chain ID
    /// @param key is the name of the config record to update
    /// @param value is the config record value
    function setVcConfigRecord(uint256 vcId, string calldata key, string calldata value) external override onlyWhenActive {
        require(msg.sender == virtualChains[vcId].owner, "only vc owner can set a vc config record");
        configRecords[vcId][key] = value;
        emit VcConfigRecordChanged(vcId, key, value);
    }

    /// Returns the value of a virtual chain config record
    /// @param vcId is the virtual chain ID
    /// @param key is the name of the config record to query
    /// @return value is the config record value
    function getVcConfigRecord(uint256 vcId, string calldata key) external override view returns (string memory) {
        return configRecords[vcId][key];
    }

    /// Transfers a virtual chain ownership to a new owner 
    /// @dev may be called only by the current virtual chain owner
    /// @param vcId is the virtual chain ID
    /// @param owner is the address of the new owner
    function setVcOwner(uint256 vcId, address owner) external override onlyWhenActive {
        require(msg.sender == virtualChains[vcId].owner, "only the vc owner can transfer ownership");
        require(owner != address(0), "cannot transfer ownership to the zero address");

        virtualChains[vcId].owner = owner;
        emit VcOwnerChanged(vcId, msg.sender, owner);
    }

    /// Returns the data of a virtual chain
    /// @dev does not include config records data
    /// @param vcId is the virtual chain ID
    /// @return name is the virtual chain name
    /// @return tier is the virtual chain tier
    /// @return rate is the virtual chain tier rate
    /// @return expiresAt the virtual chain subscription expiration time
    /// @return genRefTime is the virtual chain genesis reference time
    /// @return owner is the virtual chain owner. The owner may change virtual chain properties or ser config records
    /// @return deploymentSubset indicates the code deployment subset the virtual chain uses such as main or canary
    /// @return isCertified indicates the virtual is run by the certified committee
    function getVcData(uint256 vcId) external override view returns (
        string memory name,
        string memory tier,
        uint256 rate,
        uint expiresAt,
        uint256 genRefTime,
        address owner,
        string memory deploymentSubset,
        bool isCertified
    ) {
        VirtualChain memory vc = virtualChains[vcId];
        name = vc.name;
        tier = vc.tier;
        rate = vc.rate;
        expiresAt = vc.expiresAt;
        genRefTime = vc.genRefTime;
        owner = vc.owner;
        deploymentSubset = vc.deploymentSubset;
        isCertified = vc.isCertified;
    }

    /*
     *   Governance functions
     */

    /// Adds a subscription plan contract to the authorized subscribers list
    /// @dev governance function called only by the functional manager
    /// @param addr is the address of the subscription plan contract
    function addSubscriber(address addr) external override onlyFunctionalManager {
        authorizedSubscribers[addr] = true;
        emit SubscriberAdded(addr);
    }

    /// Removes a subscription plan contract to the authorized subscribers list
    /// @dev governance function called only by the functional manager
    /// @param addr is the address of the subscription plan contract
    function removeSubscriber(address addr) external override onlyFunctionalManager {
        require(authorizedSubscribers[addr], "given add is not an authorized subscriber");

        authorizedSubscribers[addr] = false;
        emit SubscriberRemoved(addr);
    }

    /// Sets the delay between a virtual chain genesis reference time and the virtual chain creation time
    /// @dev governance function called only by the functional manager
    /// @dev the reference time delay allows the guardian to be ready with the virtual chain resources for the first block consensus
    /// @param newGenesisRefTimeDelay is the delay time in seconds
    function setGenesisRefTimeDelay(uint256 newGenesisRefTimeDelay) public override onlyFunctionalManager {
        settings.genesisRefTimeDelay = newGenesisRefTimeDelay;
        emit GenesisRefTimeDelayChanged(newGenesisRefTimeDelay);
    }

    /// Returns the genesis reference time delay
    /// @return genesisRefTimeDelay is the delay time in seconds
    function getGenesisRefTimeDelay() external override view returns (uint) {
        return settings.genesisRefTimeDelay;
    }

    /// Sets the minimum initial virtual chain payment 
    /// @dev Prevents abuse of the guardian nodes resources
    /// @param newMinimumInitialVcPayment is the minimum payment required for the initial subscription
    function setMinimumInitialVcPayment(uint256 newMinimumInitialVcPayment) public override onlyFunctionalManager {
        settings.minimumInitialVcPayment = newMinimumInitialVcPayment;
        emit MinimumInitialVcPaymentChanged(newMinimumInitialVcPayment);
    }

    /// Returns the minimum initial virtual chain payment 
    /// @return minimumInitialVcPayment is the minimum payment required for the initial subscription
    function getMinimumInitialVcPayment() external override view returns (uint) {
        return settings.minimumInitialVcPayment;
    }

    /// Returns the settings of this contract
    /// @return genesisRefTimeDelay is the delay time in seconds
    /// @return minimumInitialVcPayment is the minimum payment required for the initial subscription
    function getSettings() external override view returns(
        uint genesisRefTimeDelay,
        uint256 minimumInitialVcPayment
    ) {
        Settings memory _settings = settings;
        genesisRefTimeDelay = _settings.genesisRefTimeDelay;
        minimumInitialVcPayment = _settings.minimumInitialVcPayment;
    }

    /// Imports virtual chain subscription from a previous subscriptions contract
    /// @dev governance function called only by the initialization admin during migration
    /// @dev if the migrated vcId is larger or equal to the next virtual chain ID to allocate, increment the next virtual chain ID
    /// @param vcId is the virtual chain ID to migrate
    /// @param previousSubscriptionsContract is the address of the previous subscription contract
    function importSubscription(uint vcId, ISubscriptions previousSubscriptionsContract) public override onlyInitializationAdmin {
        require(virtualChains[vcId].owner == address(0), "the vcId already exists");

        (string memory name,
        string memory tier,
        uint256 rate,
        uint expiresAt,
        uint256 genRefTime,
        address owner,
        string memory deploymentSubset,
        bool isCertified) = previousSubscriptionsContract.getVcData(vcId);

        virtualChains[vcId] = VirtualChain({
            name: name,
            tier: tier,
            rate: rate,
            expiresAt: expiresAt,
            genRefTime: genRefTime,
            owner: owner,
            deploymentSubset: deploymentSubset,
            isCertified: isCertified
        });

        if (vcId >= nextVcId) {
            nextVcId = vcId + 1;
        }

        emit SubscriptionChanged(vcId, owner, name, genRefTime, tier, rate, expiresAt, isCertified, deploymentSubset);
    }

    /*
    * Private functions
    */

    /// Extends the subscription of an existing virtual chain.
    /// @dev used by createVC and extendSubscription functions for subscription payment
    /// @dev assumes that the msg.sender approved the amount prior to the call
    /// @param vcId is the virtual chain ID
    /// @param amount is the amount paid for the virtual chain subscription extension
    /// @param tier is the virtual chain tier, must match the tier selected in the virtual creation
    /// @param rate is the virtual chain tier rate as determined by the subscription plan
    /// @param payer is the address paying for the subscription extension
    function _extendSubscription(uint256 vcId, uint256 amount, string memory tier, uint256 rate, address payer) private {
        VirtualChain memory vc = virtualChains[vcId];
        require(vc.genRefTime != 0, "vc does not exist");
        require(keccak256(bytes(tier)) == keccak256(bytes(virtualChains[vcId].tier)), "given tier must match the VC tier");

        IFeesWallet feesWallet = vc.isCertified ? certifiedFeesWallet : generalFeesWallet;
        require(erc20.transferFrom(msg.sender, address(this), amount), "failed to transfer subscription fees from subscriber to subscriptions");
        require(erc20.approve(address(feesWallet), amount), "failed to approve rewards to acquire subscription fees");

        uint fromTimestamp = vc.expiresAt > now ? vc.expiresAt : now;
        feesWallet.fillFeeBuckets(amount, rate, fromTimestamp);

        vc.expiresAt = fromTimestamp.add(amount.mul(30 days).div(rate));
        vc.rate = rate;

        // commit new expiration timestamp to storage
        virtualChains[vcId].expiresAt = vc.expiresAt;
        virtualChains[vcId].rate = vc.rate;

        emit SubscriptionChanged(vcId, vc.owner, vc.name, vc.genRefTime, vc.tier, vc.rate, vc.expiresAt, vc.isCertified, vc.deploymentSubset);
        emit Payment(vcId, payer, amount, vc.tier, vc.rate);
    }

    /*
     * Contracts topology / registry interface
     */

    IFeesWallet generalFeesWallet;
    IFeesWallet certifiedFeesWallet;
    IProtocol protocolContract;

    /// Refreshes the address of the other contracts the contract interacts with
    /// @dev called by the registry contract upon an update of a contract in the registry
    function refreshContracts() external override {
        generalFeesWallet = IFeesWallet(getGeneralFeesWallet());
        certifiedFeesWallet = IFeesWallet(getCertifiedFeesWallet());
        protocolContract = IProtocol(getProtocolContract());
    }
}
