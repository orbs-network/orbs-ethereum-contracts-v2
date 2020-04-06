pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "./spec_interfaces/ISubscriptions.sol";
import "./spec_interfaces/IContractRegistry.sol";
import "./spec_interfaces/IProtocol.sol";
import "./Fees.sol";

contract Subscriptions is ISubscriptions, Ownable{
    using SafeMath for uint256;

    IContractRegistry contractRegistry;

    enum CommitteeType {
        General,
        Compliance
    }

    struct VirtualChain {
        string tier;
        uint256 rate;
        uint expiresAt;
        uint genRef;
        address owner;
        string deploymentSubset;
        CommitteeType committeeType;

        mapping (string => string) configRecords;
    }

    mapping (address => bool) authorizedSubscribers;
    mapping (uint => VirtualChain) virtualChains;

    uint nextVcid;

    IERC20 erc20;

    constructor (IERC20 _erc20) public {
        require(address(_erc20) != address(0), "erc20 must not be 0");

        nextVcid = 1000000;
        erc20 = _erc20;
    }

    function setContractRegistry(IContractRegistry _contractRegistry) external onlyOwner {
        require(address(_contractRegistry) != address(0), "contractRegistry must not be 0");
        contractRegistry = _contractRegistry;
    }

    function setVcConfigRecord(uint256 vcid, string calldata key, string calldata value) external {
        require(msg.sender == virtualChains[vcid].owner, "only vc owner can set a vc config record");
        virtualChains[vcid].configRecords[key] = value;
        emit VcConfigRecordChanged(vcid, key, value);
    }

    function getVcConfigRecord(uint256 vcid, string calldata key) external view returns (string memory) {
        return virtualChains[vcid].configRecords[key];
    }

    function addSubscriber(address addr) external onlyOwner {
        require(addr != address(0), "must provide a valid address");

        authorizedSubscribers[addr] = true;
    }

    function createVC(string calldata tier, uint256 rate, uint256 amount, address owner, string calldata compliance, string calldata deploymentSubset) external returns (uint, uint) {
        require(authorizedSubscribers[msg.sender], "must be an authorized subscriber");
        require(IProtocol(contractRegistry.get("protocol")).deploymentSubsetExists(deploymentSubset) == true, "No such deployment subset");

        uint vcid = nextVcid++;
        VirtualChain memory vc = VirtualChain({
            expiresAt: block.timestamp,
            genRef: block.number + 300,
            owner: owner,
            tier: tier,
            rate: rate,
            deploymentSubset: deploymentSubset,
            committeeType: _complianceToCommitteeType(compliance)
        });
        virtualChains[vcid] = vc;

        emit VcCreated(vcid, owner);

        _extendSubscription(vcid, amount, owner);
        return (vcid, vc.genRef);
    }

    function extendSubscription(uint256 vcid, uint256 amount, address payer) external {
        _extendSubscription(vcid, amount, payer);
    }

    function setVcOwner(uint256 vcid, address owner) external {
        require(msg.sender == virtualChains[vcid].owner, "only the vc owner can transfer ownership");

        virtualChains[vcid].owner = owner;
        emit VcOwnerChanged(vcid, msg.sender, owner);
    }

    function _extendSubscription(uint256 vcid, uint256 amount, address payer) private {
        VirtualChain storage vc = virtualChains[vcid];

        Fees feesContract = Fees(contractRegistry.get("fees"));
        require(erc20.transfer(address(feesContract), amount), "failed to transfer subscription fees");
        if (vc.committeeType == CommitteeType.General) {
            feesContract.fillGeneralFeeBuckets(amount, vc.rate, vc.expiresAt);
        } else {
            assert(vc.committeeType == CommitteeType.Compliance);
            feesContract.fillComplianceFeeBuckets(amount, vc.rate, vc.expiresAt);
        }
        vc.expiresAt = vc.expiresAt.add(amount.mul(30 days).div(vc.rate));

        emit SubscriptionChanged(vcid, vc.genRef, vc.expiresAt, vc.tier, vc.deploymentSubset);
        emit Payment(vcid, payer, amount, vc.tier, vc.rate);
    }

    function compareStrings(string memory a, string memory b) private pure returns (bool) { // TODO find a better way
        return keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b)));
    }

    function isComplianceType(string memory compliance) private pure returns (bool) {
        return compareStrings(compliance, "Compliance"); // TODO where should this constant be?
    }

    function isGeneralType(string memory compliance) private pure returns (bool) {
        return compareStrings(compliance, "General"); // TODO where should this constant be?
    }

    function _complianceToCommitteeType(string memory compliance) private pure returns (CommitteeType) {
        if (isComplianceType(compliance)) {
            return CommitteeType.Compliance;
        } else if (isGeneralType(compliance)) {
            return CommitteeType.General; // TODO assert
        }

        revert("Unknown compliance type");
    }

}
