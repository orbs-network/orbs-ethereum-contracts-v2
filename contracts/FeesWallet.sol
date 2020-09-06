pragma solidity 0.5.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./spec_interfaces/IContractRegistry.sol";
import "./spec_interfaces/IMigratableFeesWallet.sol";
import "./spec_interfaces/IFeesWallet.sol";
import "./spec_interfaces/IRewards.sol";
import "./ContractRegistryAccessor.sol";
import "./Lockable.sol";
import "./ManagedContract.sol";


/// @title Fees Wallet contract interface, manages the fee buckets
contract FeesWallet is IFeesWallet, ManagedContract {
    using SafeMath for uint256;

    event FeesWithdrawnFromBucket(uint256 bucketId, uint256 withdrawn, uint256 total);
    event FeesAddedToBucket(uint256 bucketId, uint256 added, uint256 total);

    IERC20 token;

    uint256 constant BUCKET_TIME_PERIOD = 30 days;
    uint constant MAX_FEE_BUCKET_ITERATIONS = 24;

    mapping(uint256 => uint256) buckets;
    uint256 lastCollectedAt;

    modifier onlyRewardsContract() {
        require(msg.sender == address(rewardsContract), "caller is not the rewards contract");

        _;
    }

    constructor(IContractRegistry _contractRegistry, address _registryAdmin, IERC20 _token) ManagedContract(_contractRegistry, _registryAdmin) public {
        token = _token;
        lastCollectedAt = now;
    }

    /// @dev collect fees from the buckets since the last call and transfers the amount back.
    /// Called by: only Rewards contract.
    function collectFees() external onlyRewardsContract returns (uint256 collectedFees)  {
        // TODO we often do integer division for rate related calculation, which floors the result. Do we need to address this?
        // TODO for an empty committee or a committee with 0 total stake the divided amounts will be locked in the contract FOREVER

        // Fee pool
        uint _lastCollectedAt = lastCollectedAt;
        uint bucketsPayed = 0;
        while (bucketsPayed < MAX_FEE_BUCKET_ITERATIONS && _lastCollectedAt < now) {
            uint256 bucketStart = _bucketTime(_lastCollectedAt);
            uint256 bucketEnd = bucketStart.add(BUCKET_TIME_PERIOD);
            uint256 payUntil = Math.min(bucketEnd, now);
            uint256 bucketDuration = payUntil.sub(_lastCollectedAt);
            uint256 remainingBucketTime = bucketEnd.sub(_lastCollectedAt);

            uint256 bucketTotal = buckets[bucketStart];
            uint256 amount = bucketTotal * bucketDuration / remainingBucketTime;
            collectedFees += amount;
            bucketTotal = bucketTotal.sub(amount);
            buckets[bucketStart] = bucketTotal;
            emit FeesWithdrawnFromBucket(bucketStart, amount, bucketTotal);

            _lastCollectedAt = payUntil;

            assert(_lastCollectedAt <= bucketEnd);
            if (_lastCollectedAt == bucketEnd) {
                delete buckets[bucketStart];
            }

            bucketsPayed++;
        }

        lastCollectedAt = _lastCollectedAt;

        require(token.transfer(msg.sender, collectedFees), "FeesWallet::failed to transfer collected fees to rewards"); // TODO in that case, transfer the remaining balance?
    }

    /*
     *   External methods
     */

    /// @dev Called by: subscriptions contract.
    /// Top-ups the fee pool with the given amount at the given rate (typically called by the subscriptions contract).
    function fillFeeBuckets(uint256 amount, uint256 monthlyRate, uint256 fromTimestamp) external {
        uint256 bucket = _bucketTime(fromTimestamp);
        require(bucket >= _bucketTime(now), "FeeWallet::cannot fill bucket from the past");

        uint256 _amount = amount;

        // add the partial amount to the first bucket
        uint256 bucketAmount = Math.min(amount, monthlyRate.mul(BUCKET_TIME_PERIOD - fromTimestamp % BUCKET_TIME_PERIOD).div(BUCKET_TIME_PERIOD));
        fillFeeBucket(bucket, bucketAmount);
        _amount = _amount.sub(bucketAmount);

        // following buckets are added with the monthly rate
        while (_amount > 0) {
            bucket = bucket.add(BUCKET_TIME_PERIOD);
            bucketAmount = Math.min(monthlyRate, _amount);
            fillFeeBucket(bucket, bucketAmount);

            _amount = _amount.sub(bucketAmount);
        }

        require(token.transferFrom(msg.sender, address(this), amount), "failed to transfer fees into fee wallet");
    }

    function fillFeeBucket(uint256 bucketId, uint256 amount) private {
        uint256 bucketTotal = buckets[bucketId].add(amount);
        buckets[bucketId] = bucketTotal;
        emit FeesAddedToBucket(bucketId, amount, bucketTotal);
    }

    /// @dev Called by the old FeesWallet contract.
    /// Part of the IMigratableFeesWallet interface.
    function acceptBucketMigration(uint256 bucketStartTime, uint256 amount) external {
        require(_bucketTime(bucketStartTime) == bucketStartTime,  "bucketStartTime must be the  start time of a bucket");
        fillFeeBucket(bucketStartTime, amount);
        require(token.transferFrom(msg.sender, address(this), amount), "failed to transfer fees into fee wallet on bucket migration");
    }

    /*
     * General governance
     */

    /// @dev migrates the fees of bucket starting at startTimestamp.
    /// bucketStartTime must be a bucket's start time.
    /// Calls acceptBucketMigration in the destination contract.
    function migrateBucket(IMigratableFeesWallet destination, uint256 bucketStartTime) external onlyMigrationManager {
        require(_bucketTime(bucketStartTime) == bucketStartTime,  "bucketStartTime must be the  start time of a bucket");

        uint bucketAmount = buckets[bucketStartTime];
        if (bucketAmount == 0) return;

        buckets[bucketStartTime] = 0;
        emit FeesWithdrawnFromBucket(bucketStartTime, bucketAmount, 0);

        token.approve(address(destination), bucketAmount);
        destination.acceptBucketMigration(bucketStartTime, bucketAmount);
    }

    /*
     * Emergency
     */

    /// @dev an emergency withdrawal enables withdrawal of all funds to an escrow account. To be use in emergencies only.
    function emergencyWithdraw() external onlyMigrationManager {
        emit EmergencyWithdrawal(msg.sender);
        require(token.transfer(msg.sender, token.balanceOf(address(this))), "IFeesWallet::emergencyWithdraw - transfer failed (fee token)");
    }

    function _bucketTime(uint256 time) private pure returns (uint256) {
        return time - time % BUCKET_TIME_PERIOD;
    }

    IRewards rewardsContract;
    function refreshContracts() external {
        rewardsContract = IRewards(getRewardsContract());
    }

}
