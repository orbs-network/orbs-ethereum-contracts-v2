pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./spec_interfaces/IFees.sol";
import "./spec_interfaces/ICommittee.sol";
import "./ContractRegistryAccessor.sol";

contract Fees is IFees, ContractRegistryAccessor {
    using SafeMath for uint256;

    uint256 constant bucketTimePeriod = 30 days;

    mapping(uint256 => uint256) generalFeePoolBuckets;
    mapping(uint256 => uint256) compliantFeePoolBuckets;

    uint256 lastPayedAt;

    mapping(address => uint256) orbsBalance;

    IERC20 erc20;

    modifier onlyElectionsContract() {
        require(msg.sender == address(getElectionsContract()), "caller is not the elections");

        _;
    }

    constructor(IERC20 _erc20) public {
        require(address(_erc20) != address(0), "erc20 must not be 0");

        erc20 = _erc20;
        lastPayedAt = now;
    }

    function getOrbsBalance(address addr) external view returns (uint256) {
        return orbsBalance[addr];
    }

    function getLastFeesAssignment() external view returns (uint256) {
        return lastPayedAt;
    }

    uint constant MAX_REWARD_BUCKET_ITERATIONS = 6;

    function assignFees(address[] calldata generalCommittee, bool[] calldata compliance) external onlyElectionsContract {
        _assignFees(generalCommittee, compliance);
    }

    function _assignFees(address[] memory generalCommittee, bool[] memory compliance) private {
        // TODO we often do integer division for rate related calculation, which floors the result. Do we need to address this?
        // TODO for an empty committee or a committee with 0 total stake the divided amounts will be locked in the contract FOREVER

        // Fee pool
        uint bucketsPayed = 0;
        uint generalFeePoolAmount = 0;
        uint complianceFeePoolAmount = 0;
        while (bucketsPayed < MAX_REWARD_BUCKET_ITERATIONS && lastPayedAt < now) {
            uint256 bucketStart = _bucketTime(lastPayedAt);
            uint256 bucketEnd = bucketStart.add(bucketTimePeriod);
            uint256 payUntil = Math.min(bucketEnd, now);
            uint256 bucketDuration = payUntil.sub(lastPayedAt);
            uint256 remainingBucketTime = bucketEnd.sub(lastPayedAt);

            uint256 amount = generalFeePoolBuckets[bucketStart] * bucketDuration / remainingBucketTime;
            generalFeePoolAmount += amount;
            generalFeePoolBuckets[bucketStart] = generalFeePoolBuckets[bucketStart].sub(amount);

            amount = compliantFeePoolBuckets[bucketStart] * bucketDuration / remainingBucketTime;
            complianceFeePoolAmount += amount;
            compliantFeePoolBuckets[bucketStart] = compliantFeePoolBuckets[bucketStart].sub(amount);

            lastPayedAt = payUntil;

            assert(lastPayedAt <= bucketEnd);
            if (lastPayedAt == bucketEnd) {
                delete generalFeePoolBuckets[bucketStart];
                delete compliantFeePoolBuckets[bucketStart];
            }

            bucketsPayed++;
        }

        assignAmountFixed(generalCommittee, compliance, generalFeePoolAmount, false);
        assignAmountFixed(generalCommittee, compliance, complianceFeePoolAmount, true);
    }

    function assignAmountFixed(address[] memory committee, bool[] memory compliance, uint256 amount, bool isCompliant /* todo - use */) private {
        uint256[] memory assignedFees = new uint256[](committee.length);

        uint n = committee.length;
        if (isCompliant)  {
            n = 0;
            for (uint i = 0; i < committee.length; i++) {
                if (compliance[i]) n++;
            }
        }
        if (n == 0) return;

        uint256 totalAssigned = 0;

        uint256 curAmount = amount.div(n);
        for (uint i = 0; i < committee.length; i++) {
            if (!isCompliant || compliance[i]) {
                assignedFees[i] = curAmount;
                totalAssigned = totalAssigned.add(curAmount);
            }
        }

        uint256 remainder = amount.sub(totalAssigned);
        if (remainder > 0 && n > 0) {
            uint ind = now % committee.length;
            if (isCompliant) {
                while (!compliance[ind]) { // todo: This is not a fair draw - instead take now % n and find the n'th member.
                    ind = (ind + 1) % committee.length;
                }
            }
            assignedFees[ind] = assignedFees[ind].add(remainder);
        }

        for (uint i = 0; i < committee.length; i++) {
            addToBalance(committee[i], assignedFees[i]);
        }
        emit FeesAssigned(committee, assignedFees);
    }

    function addToBalance(address addr, uint256 amount) private {
        orbsBalance[addr] = orbsBalance[addr].add(amount);
    }

    function fillGeneralFeeBuckets(uint256 amount, uint256 monthlyRate, uint256 fromTimestamp) external {
        fillFeeBuckets(amount, monthlyRate, fromTimestamp, false);
    }

    function fillComplianceFeeBuckets(uint256 amount, uint256 monthlyRate, uint256 fromTimestamp) external {
        fillFeeBuckets(amount, monthlyRate, fromTimestamp, true);
    }

    function fillBucket(uint256 bucketId, uint256 amount, bool isCompliant) private {
        uint256 total;
        if (isCompliant) {
            total = compliantFeePoolBuckets[bucketId].add(amount);
            compliantFeePoolBuckets[bucketId] = total;
        } else {
            total = generalFeePoolBuckets[bucketId].add(amount);
            generalFeePoolBuckets[bucketId] = total;
        }

        emit FeesAddedToBucket(bucketId, amount, total, isCompliant);
    }

    function fillFeeBuckets(uint256 amount, uint256 monthlyRate, uint256 fromTimestamp, bool isCompliant) private {
        (address[] memory committee,, bool[] memory compliance) = getCommitteeContract().getCommittee();
        _assignFees(committee, compliance); // to handle rate change in the middle of a bucket time period (TBD - this is nice to have, consider removing)

        uint256 bucket = _bucketTime(fromTimestamp);
        uint256 _amount = amount;

        // add the partial amount to the first bucket
        uint256 bucketAmount = Math.min(amount, monthlyRate.mul(bucketTimePeriod - fromTimestamp % bucketTimePeriod).div(bucketTimePeriod));
        fillBucket(bucket, bucketAmount, isCompliant);
        _amount = _amount.sub(bucketAmount);

        // following buckets are added with the monthly rate
        while (_amount > 0) {
            bucket = bucket.add(bucketTimePeriod);
            bucketAmount = Math.min(monthlyRate, _amount);
            fillBucket(bucket, bucketAmount, isCompliant);
            _amount = _amount.sub(bucketAmount);
        }

        assert(_amount == 0);
    }

    function withdrawFunds() external {
        uint256 amount = orbsBalance[msg.sender];
        orbsBalance[msg.sender] = 0;
        require(erc20.transfer(msg.sender, amount), "Rewards::claimExternalTokenRewards - insufficient funds");
    }

    function _bucketTime(uint256 time) private pure returns (uint256) {
        return time - time % bucketTimePeriod;
    }

}
