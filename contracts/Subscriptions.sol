pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./spec_interfaces/ISubscriptions.sol";
import "./spec_interfaces/IProtocol.sol";
import "./ContractRegistryAccessor.sol";
import "./spec_interfaces/IFeesWallet.sol";
import "./Lockable.sol";
import "./ManagedContract.sol";

contract Subscriptions is ISubscriptions, ManagedContract {
    using SafeMath for uint256;

    enum CommitteeType {
        General,
        Certification
    }

    struct VirtualChain {
        string name;
        string tier;
        uint256 rate;
        uint expiresAt;
        uint256 genRefTime;
        address owner;
        string deploymentSubset;
        bool isCertified;

        mapping (string => string) configRecords;
    }

    mapping (address => bool) public authorizedSubscribers;
    mapping (uint => VirtualChain) public virtualChains;

    uint public nextVcid;
    uint public genesisRefTimeDelay;
    uint256 public minimumInitialVcPayment;

    IERC20 public erc20;

    constructor (IContractRegistry _contractRegistry, address _registryAdmin, IERC20 _erc20, uint256 _genesisRefTimeDelay, uint256 _minimumInitialVcPayment) ManagedContract(_contractRegistry, _registryAdmin) public {
        require(address(_erc20) != address(0), "erc20 must not be 0");

        erc20 = _erc20;
        nextVcid = 1000000;

        setGenesisRefTimeDelay(_genesisRefTimeDelay);
        setMinimumInitialVcPayment(_minimumInitialVcPayment);
    }

    function setVcConfigRecord(uint256 vcid, string calldata key, string calldata value) external onlyWhenActive {
        require(msg.sender == virtualChains[vcid].owner, "only vc owner can set a vc config record");
        virtualChains[vcid].configRecords[key] = value;
        emit VcConfigRecordChanged(vcid, key, value);
    }

    function getVcConfigRecord(uint256 vcid, string calldata key) external view returns (string memory) {
        return virtualChains[vcid].configRecords[key];
    }

    function addSubscriber(address addr) external onlyFunctionalManager onlyWhenActive {
        // todo: emit event
        authorizedSubscribers[addr] = true;

        emit SubscriberAdded(addr);
    }

    function removeSubscriber(address addr) external onlyFunctionalManager onlyWhenActive {
        require(authorizedSubscribers[addr], "given add is not an authorized subscriber");

        authorizedSubscribers[addr] = false;

        emit SubscriberRemoved(addr);
    }

    function createVC(string calldata name, string calldata tier, uint256 rate, uint256 amount, address owner, bool isCertified, string calldata deploymentSubset) external onlyWhenActive returns (uint, uint) {
        require(authorizedSubscribers[msg.sender], "must be an authorized subscriber");
        require(protocolContract.deploymentSubsetExists(deploymentSubset) == true, "No such deployment subset");
        require(amount >= minimumInitialVcPayment, "initial VC payment must be at least minimumInitialVcPayment");

        uint vcid = nextVcid++;
        VirtualChain memory vc = VirtualChain({
            name: name,
            expiresAt: block.timestamp,
            genRefTime: now + genesisRefTimeDelay,
            owner: owner,
            tier: tier,
            rate: rate,
            deploymentSubset: deploymentSubset,
            isCertified: isCertified
        });
        virtualChains[vcid] = vc;

        emit VcCreated(vcid, owner);

        _extendSubscription(vcid, amount, owner);
        return (vcid, vc.genRefTime);
    }

    function extendSubscription(uint256 vcid, uint256 amount, address payer) external onlyWhenActive {
        _extendSubscription(vcid, amount, payer);
    }

    function setVcOwner(uint256 vcid, address owner) external onlyWhenActive {
        require(msg.sender == virtualChains[vcid].owner, "only the vc owner can transfer ownership");

        virtualChains[vcid].owner = owner;
        emit VcOwnerChanged(vcid, msg.sender, owner);
    }

    function _extendSubscription(uint256 vcid, uint256 amount, address payer) private {
        VirtualChain storage vc = virtualChains[vcid];

        IFeesWallet feesWallet = vc.isCertified ? certifiedFeesWallet : generalFeesWallet;
        require(erc20.transferFrom(msg.sender, address(this), amount), "failed to transfer subscription fees from subscriber to subscriptions");
        require(erc20.approve(address(feesWallet), amount), "failed to approve rewards to acquire subscription fees");

        feesWallet.fillFeeBuckets(amount, vc.rate, vc.expiresAt);

        vc.expiresAt = vc.expiresAt.add(amount.mul(30 days).div(vc.rate));

        emit SubscriptionChanged(vcid, vc.name, vc.genRefTime, vc.expiresAt, vc.tier, vc.deploymentSubset);
        emit Payment(vcid, payer, amount, vc.tier, vc.rate);
    }

    function setGenesisRefTimeDelay(uint256 newGenesisRefTimeDelay) public onlyFunctionalManager onlyWhenActive {
        genesisRefTimeDelay = newGenesisRefTimeDelay;
        emit GenesisRefTimeDelayChanged(newGenesisRefTimeDelay);
    }

    function setMinimumInitialVcPayment(uint256 newMinimumInitialVcPayment) public onlyFunctionalManager {
        minimumInitialVcPayment = newMinimumInitialVcPayment;
        emit MinimumInitialVcPaymentChanged(newMinimumInitialVcPayment);
    }

    function getGenesisRefTimeDelay() external view returns (uint) {
        return genesisRefTimeDelay;
    }

    function getMinimumInitialVcPayment() external view returns (uint) {
        return minimumInitialVcPayment;
    }

    function getVcData(uint256 vcId) external view returns (
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

    IFeesWallet generalFeesWallet;
    IFeesWallet certifiedFeesWallet;
    IProtocol protocolContract;
    function refreshContracts() external {
        generalFeesWallet = IFeesWallet(getGeneralFeesWallet());
        certifiedFeesWallet = IFeesWallet(getCertifiedFeesWallet());
        protocolContract = IProtocol(getProtocolContract());
    }

}
