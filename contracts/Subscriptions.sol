pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./spec_interfaces/ISubscriptions.sol";
import "./spec_interfaces/IProtocol.sol";
import "./ContractRegistryAccessor.sol";
import "./WithClaimableFunctionalOwnership.sol";
import "./spec_interfaces/IFeesWallet.sol";

contract Subscriptions is ISubscriptions, ContractRegistryAccessor, WithClaimableFunctionalOwnership, Lockable {
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

    constructor (IERC20 _erc20) public {
        require(address(_erc20) != address(0), "erc20 must not be 0");

        nextVcid = 1000000;
        genesisRefTimeDelay = 3 hours;
        erc20 = _erc20;
    }

    function setVcConfigRecord(uint256 vcid, string calldata key, string calldata value) external onlyWhenActive {
        require(msg.sender == virtualChains[vcid].owner, "only vc owner can set a vc config record");
        virtualChains[vcid].configRecords[key] = value;
        emit VcConfigRecordChanged(vcid, key, value);
    }

    function getVcConfigRecord(uint256 vcid, string calldata key) external view returns (string memory) {
        return virtualChains[vcid].configRecords[key];
    }

    function addSubscriber(address addr) external onlyFunctionalOwner onlyWhenActive {
        require(addr != address(0), "must provide a valid address");
        // todo: emit event
        authorizedSubscribers[addr] = true;

        emit SubscriberAdded(addr);
    }

    function removeSubscriber(address addr) external onlyFunctionalOwner onlyWhenActive {
        require(addr != address(0), "must provide a valid address");
        require(authorizedSubscribers[addr], "given add is not an authorized subscriber");

        authorizedSubscribers[addr] = false;

        emit SubscriberRemoved(addr);
    }

    function createVC(string calldata name, string calldata tier, uint256 rate, uint256 amount, address owner, bool isCertified, string calldata deploymentSubset) external onlyWhenActive returns (uint, uint) {
        require(authorizedSubscribers[msg.sender], "must be an authorized subscriber");
        require(getProtocolContract().deploymentSubsetExists(deploymentSubset) == true, "No such deployment subset");
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

        IFeesWallet feesWallet = vc.isCertified ? getCertifiedFeesWallet() : getGeneralFeesWallet();
        require(erc20.transferFrom(msg.sender, address(this), amount), "failed to transfer subscription fees from subscriber to subscriptions");
        require(erc20.approve(address(feesWallet), amount), "failed to approve rewards to acquire subscription fees");

        feesWallet.fillFeeBuckets(amount, vc.rate, vc.expiresAt);

        vc.expiresAt = vc.expiresAt.add(amount.mul(30 days).div(vc.rate));

        emit SubscriptionChanged(vcid, vc.name, vc.genRefTime, vc.expiresAt, vc.tier, vc.deploymentSubset);
        emit Payment(vcid, payer, amount, vc.tier, vc.rate);
    }

    function setGenesisRefTimeDelay(uint256 newGenesisRefTimeDelay) external onlyFunctionalOwner onlyWhenActive {
        genesisRefTimeDelay = newGenesisRefTimeDelay;
        emit GenesisRefTimeDelayChanged(newGenesisRefTimeDelay);
    }

    function setMinimumInitialVcPayment(uint256 newMinimumInitialVcPayment) external onlyFunctionalOwner {
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

}
