pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./spec_interfaces/ISubscriptions.sol";
import "./spec_interfaces/IProtocol.sol";
import "./ContractRegistryAccessor.sol";
import "./WithClaimableFunctionalOwnership.sol";

contract Subscriptions is ISubscriptions, ContractRegistryAccessor, WithClaimableFunctionalOwnership {
    using SafeMath for uint256;

    enum CommitteeType {
        General,
        Compliance
    }

    struct VirtualChain {
        string tier;
        uint256 rate;
        uint expiresAt;
        uint256 genRefTime;
        address owner;
        string deploymentSubset;
        bool isCompliant;

        mapping (string => string) configRecords;
    }

    mapping (address => bool) authorizedSubscribers;
    mapping (uint => VirtualChain) virtualChains;

    uint nextVcid;
    uint genesisRefTimeDelay;

    IERC20 erc20;

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

        authorizedSubscribers[addr] = true;
    }

    function createVC(string calldata tier, uint256 rate, uint256 amount, address owner, bool isCompliant, string calldata deploymentSubset) external onlyWhenActive returns (uint, uint) {
        require(authorizedSubscribers[msg.sender], "must be an authorized subscriber");
        require(getProtocolContract().deploymentSubsetExists(deploymentSubset) == true, "No such deployment subset");

        uint vcid = nextVcid++;
        VirtualChain memory vc = VirtualChain({
            expiresAt: block.timestamp,
            genRefTime: now + genesisRefTimeDelay,
            owner: owner,
            tier: tier,
            rate: rate,
            deploymentSubset: deploymentSubset,
            isCompliant: isCompliant
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

        IRewards rewardsContract = getRewardsContract();
        require(erc20.transfer(address(rewardsContract), amount), "failed to transfer subscription fees");
        if (vc.isCompliant) {
            rewardsContract.fillComplianceFeeBuckets(amount, vc.rate, vc.expiresAt);
        } else {
            rewardsContract.fillGeneralFeeBuckets(amount, vc.rate, vc.expiresAt);
        }
        vc.expiresAt = vc.expiresAt.add(amount.mul(30 days).div(vc.rate));

        emit SubscriptionChanged(vcid, vc.genRefTime, vc.expiresAt, vc.tier, vc.deploymentSubset);
        emit Payment(vcid, payer, amount, vc.tier, vc.rate);
    }

    function setGenesisRefTimeDelay(uint256 newGenesisRefTimeDelay) external onlyFunctionalOwner onlyWhenActive {
        genesisRefTimeDelay = newGenesisRefTimeDelay;
    }

    function getGenesisRefTimeDelay() external view returns (uint) {
        return genesisRefTimeDelay;
    }
}
