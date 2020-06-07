pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./spec_interfaces/IContractRegistry.sol";
import "./spec_interfaces/ICommittee.sol";
import "./ContractRegistryAccessor.sol";
import "./Erc20AccessorWithTokenGranularity.sol";
import "./WithClaimableFunctionalOwnership.sol";

contract Rewards is IRewards, ContractRegistryAccessor, ERC20AccessorWithTokenGranularity, WithClaimableFunctionalOwnership {
    using SafeMath for uint256;
    using SafeMath for uint48; // TODO this is meaningless for overflow detection, SafeMath is only for uint256. Should still detect underflows


    struct Settings {
        uint48 generalCommitteeAnnualBootstrap;
        uint48 complianceCommitteeAnnualBootstrap;
        uint48 annualRateInPercentMille;
        uint48 annualCap;
    }
    Settings settings;

    struct Pools {
        uint48 bootstrapPool;
        uint48 stakingPool;
    }
    Pools pools;

    struct TotalBalances {
        uint48 bootstrapRewardsTotalBalance;
        uint48 feesTotalBalance;
        uint48 stakingRewardsTotalBalance;
    }
    TotalBalances totalBalances;

    struct Balance {
        uint48 bootstrapRewards;
        uint48 fees;
        uint48 stakingRewards;
    }
    mapping(address => Balance) balances;

    uint256 constant feeBucketTimePeriod = 30 days;
    mapping(uint256 => uint256) generalFeePoolBuckets;
    mapping(uint256 => uint256) compliantFeePoolBuckets;

    IERC20 bootstrapToken;
    IERC20 erc20;
    uint256 lastAssignedAt;

    modifier onlyCommitteeContract() {
        require(msg.sender == address(getCommitteeContract()), "caller is not the committee contract");

        _;
    }

    constructor(IERC20 _erc20, IERC20 _bootstrapToken) public {
        require(address(_bootstrapToken) != address(0), "bootstrapToken must not be 0");
        require(address(_erc20) != address(0), "erc20 must not be 0");

        erc20 = _erc20;
        bootstrapToken = _bootstrapToken;
        // TODO - The initial lastPayedAt should be set in the first assignRewards.
        lastAssignedAt = now;
    }

    // bootstrap rewards

    function setGeneralCommitteeAnnualBootstrap(uint256 annual_amount) external onlyFunctionalOwner {
        assignRewards();
        settings.generalCommitteeAnnualBootstrap = toUint48Granularity(annual_amount);
    }

    function setComplianceCommitteeAnnualBootstrap(uint256 annual_amount) external onlyFunctionalOwner {
        assignRewards();
        settings.complianceCommitteeAnnualBootstrap = toUint48Granularity(annual_amount);
    }

    function topUpBootstrapPool(uint256 amount) external {
        uint48 _amount48 = toUint48Granularity(amount);
        uint48 bootstrapPool = uint48(pools.bootstrapPool.add(_amount48)); // todo may overflow
        pools.bootstrapPool = bootstrapPool;
        require(transferFrom(bootstrapToken, msg.sender, address(this), _amount48), "Rewards::topUpFixedPool - insufficient allowance");
        emit BootstrapAddedToPool(amount, toUint256Granularity(bootstrapPool));
    }

    function getBootstrapBalance(address addr) external view returns (uint256) {
        return toUint256Granularity(balances[addr].bootstrapRewards);
    }

    function assignRewards() public {
        (address[] memory committee, uint256[] memory weights, bool[] memory compliance) = getCommitteeContract().getCommittee();
        _assignRewardsToCommittee(committee, weights, compliance);
    }

    function assignRewardsToCommittee(address[] calldata committee, uint256[] calldata committeeWeights, bool[] calldata compliance) external onlyCommitteeContract {
        _assignRewardsToCommittee(committee, committeeWeights, compliance);
    }

    function _assignRewardsToCommittee(address[] memory committee, uint256[] memory committeeWeights, bool[] memory compliance) private {
        Settings memory _settings = settings;

        (uint48 generalValidatorBootstrap, uint48 certifiedValidatorBootstrap) = collectBootstrapRewards(committee, _settings);
        (uint48 generalValidatorFee, uint48 certifiedValidatorFee) = collectFees(committee, compliance);
        uint256[] memory stakingRewards = collectStakingRewards(committee, committeeWeights, _settings);

        TotalBalances memory totals = totalBalances;
        Balance memory balance;
        for (uint i = 0; i < committee.length; i++) {
            balance = balances[committee[i]];

            balance.bootstrapRewards += (compliance[i] ? certifiedValidatorBootstrap : generalValidatorBootstrap); // todo may overflow
            balance.fees += (compliance[i] ? certifiedValidatorFee : generalValidatorFee); // todo may overflow
            balance.stakingRewards += toUint48Granularity(stakingRewards[i]); // todo may overflow

            totals.bootstrapRewardsTotalBalance += (compliance[i] ? certifiedValidatorBootstrap : generalValidatorBootstrap); // todo may overflow
            totals.feesTotalBalance += (compliance[i] ? certifiedValidatorFee : generalValidatorFee); // todo may overflow
            totals.stakingRewardsTotalBalance += toUint48Granularity(stakingRewards[i]); // todo may overflow

            balances[committee[i]] = balance;
        }

        totalBalances = totals;
        lastAssignedAt = now;

        emit StakingRewardsAssigned(committee, stakingRewards);
        emit BootstrapRewardsAssigned(toUint256Granularity(generalValidatorBootstrap), toUint256Granularity(certifiedValidatorBootstrap));
        emit FeesAssigned(toUint256Granularity(generalValidatorFee), toUint256Granularity(certifiedValidatorFee));
    }

    function collectBootstrapRewards(address[] memory committee, Settings memory _settings) private view returns (uint48 generalValidatorBootstrap, uint48 certifiedValidatorBootstrap){
        if (committee.length > 0) {
            uint256 duration = now.sub(lastAssignedAt);
            generalValidatorBootstrap = uint48(_settings.generalCommitteeAnnualBootstrap.mul(duration).div(365 days));
            certifiedValidatorBootstrap = generalValidatorBootstrap + uint48(_settings.complianceCommitteeAnnualBootstrap.mul(duration).div(365 days));
        }
    }

    function withdrawBootstrapFunds() external {
        uint48 amount = balances[msg.sender].bootstrapRewards;
        uint48 pool = pools.bootstrapPool;
        require(amount <= pool, "not enough balance in the bootstrap pool for this withdrawal");
        balances[msg.sender].bootstrapRewards = 0;
        totalBalances.bootstrapRewardsTotalBalance = uint48(totalBalances.bootstrapRewardsTotalBalance.sub(amount));
        pools.bootstrapPool = uint48(pool.sub(amount));
        require(transfer(bootstrapToken, msg.sender, amount), "Rewards::withdrawBootstrapFunds - insufficient funds");
    }

    // staking rewards

    function setAnnualStakingRewardsRate(uint256 annual_rate_in_percent_mille, uint256 annual_cap) external onlyFunctionalOwner {
        assignRewards();
        Settings memory _settings = settings;
        _settings.annualRateInPercentMille = uint48(annual_rate_in_percent_mille);
        _settings.annualCap = toUint48Granularity(annual_cap);
        settings = _settings;
    }

    function topUpStakingRewardsPool(uint256 amount) external {
        uint48 amount48 = toUint48Granularity(amount);
        pools.stakingPool = uint48(pools.stakingPool.add(amount48)); // todo overflow
        require(transferFrom(erc20, msg.sender, address(this), amount48), "Rewards::topUpProRataPool - insufficient allowance");
    }

    function getStakingRewardBalance(address addr) external view returns (uint256) {
        return toUint256Granularity(balances[addr].stakingRewards);
    }

    function getLastRewardAssignment() external view returns (uint256) {
        return lastAssignedAt;
    }

    function collectStakingRewards(address[] memory committee, uint256[] memory weights, Settings memory _settings) private view returns (uint256[] memory assignedRewards) {
        // TODO we often do integer division for rate related calculation, which floors the result. Do we need to address this?
        // TODO for an empty committee or a committee with 0 total stake the divided amounts will be locked in the contract FOREVER
        assignedRewards = new uint256[](committee.length);

        uint256 totalWeight = 0;
        for (uint i = 0; i < committee.length; i++) {
            totalWeight = totalWeight.add(weights[i]);
        }

        if (totalWeight > 0) { // TODO - handle the case of totalStake == 0. consider also an empty committee. consider returning a boolean saying if the amount was successfully distributed or not and handle on caller side.
            uint256 duration = now.sub(lastAssignedAt);

            uint annualRateInPercentMille = Math.min(uint(_settings.annualRateInPercentMille), toUint256Granularity(_settings.annualCap).mul(100000).div(totalWeight)); // todo make 100000 constant?
            uint48 curAmount;
            for (uint i = 0; i < committee.length; i++) {
                curAmount = toUint48Granularity(weights[i].mul(annualRateInPercentMille).div(100000)); // todo may overflow
                curAmount = uint48(uint(curAmount).mul(duration).div(365 days));
                assignedRewards[i] = toUint256Granularity(curAmount);
            }
        }
    }

    struct DistributorBatchState {
        uint256 fromBlock;
        uint256 toBlock;
        uint256 nextTxIndex;
        uint split;
    }
    mapping (address => DistributorBatchState) distributorBatchState;

    function distributeOrbsTokenStakingRewards(uint256 totalAmount, uint256 fromBlock, uint256 toBlock, uint split, uint txIndex, address[] calldata to, uint256[] calldata amounts) external {
        require(to.length == amounts.length, "expected to and amounts to be of same length");
        uint48 totalAmount_uint48 = toUint48Granularity(totalAmount);
        require(totalAmount == toUint256Granularity(totalAmount_uint48), "totalAmount must divide by 1e15");

        DistributorBatchState memory ds = distributorBatchState[msg.sender];
        bool firstTxBySender = ds.nextTxIndex == 0;

        require(!firstTxBySender || fromBlock == 0, "on the first batch fromBlock must be 0");

        if (firstTxBySender || fromBlock == ds.toBlock + 1) { // New distribution batch
            require(txIndex == 0, "txIndex must be 0 for the first transaction of a new distribution batch");
            require(toBlock < block.number, "toBlock must be in the past");
            require(toBlock >= fromBlock, "toBlock must be at least fromBlock");
            ds.fromBlock = fromBlock;
            ds.toBlock = toBlock;
            ds.split = split;
            ds.nextTxIndex = 1;
            distributorBatchState[msg.sender] = ds;
        } else {
            require(txIndex == ds.nextTxIndex, "txIndex mismatch");
            require(toBlock == ds.toBlock, "toBlock mismatch");
            require(fromBlock == ds.fromBlock, "fromBlock mismatch");
            require(split == ds.split, "split mismatch");
            distributorBatchState[msg.sender].nextTxIndex = txIndex + 1;
        }

        require(totalAmount_uint48 <= balances[msg.sender].stakingRewards, "not enough member balance for this distribution");

        uint48 stakingPool = pools.stakingPool;
        require(totalAmount_uint48 <= stakingPool, "not enough balance in the staking pool for this distribution");

        pools.stakingPool = uint48(stakingPool.sub(totalAmount_uint48));
        balances[msg.sender].stakingRewards = uint48(balances[msg.sender].stakingRewards.sub(totalAmount_uint48));
        totalBalances.stakingRewardsTotalBalance = uint48(totalBalances.stakingRewardsTotalBalance.sub(totalAmount_uint48));

        IStakingContract stakingContract = getStakingContract();
        approve(erc20, address(stakingContract), totalAmount_uint48);
        stakingContract.distributeRewards(totalAmount, to, amounts); // TODO should we rely on staking contract to verify total amount?

        emit StakingRewardsDistributed(msg.sender, fromBlock, toBlock, split, txIndex, to, amounts);
    }

    // fees

    function getFeeBalance(address addr) external view returns (uint256) {
        return toUint256Granularity(balances[addr].fees);
    }

    uint constant MAX_FEE_BUCKET_ITERATIONS = 6;

    function collectFees(address[] memory committee, bool[] memory compliance) private returns (uint48 generalValidatorFee, uint48 certifiedValidatorFee) {
        // TODO we often do integer division for rate related calculation, which floors the result. Do we need to address this?
        // TODO for an empty committee or a committee with 0 total stake the divided amounts will be locked in the contract FOREVER

        // Fee pool
        uint _lastAssignedAt = lastAssignedAt;
        uint bucketsPayed = 0;
        uint generalFeePoolAmount = 0;
        uint complianceFeePoolAmount = 0;
        while (bucketsPayed < MAX_FEE_BUCKET_ITERATIONS && _lastAssignedAt < now) {
            uint256 bucketStart = _bucketTime(_lastAssignedAt);
            uint256 bucketEnd = bucketStart.add(feeBucketTimePeriod);
            uint256 payUntil = Math.min(bucketEnd, now);
            uint256 bucketDuration = payUntil.sub(_lastAssignedAt);
            uint256 remainingBucketTime = bucketEnd.sub(_lastAssignedAt);

            uint256 bucketTotal = generalFeePoolBuckets[bucketStart];
            uint256 amount = bucketTotal * bucketDuration / remainingBucketTime;
            generalFeePoolAmount += amount;
            bucketTotal = bucketTotal.sub(amount);
            generalFeePoolBuckets[bucketStart] = bucketTotal;
            emit FeesWithdrawnFromBucket(bucketStart, amount, bucketTotal, false);

            bucketTotal = compliantFeePoolBuckets[bucketStart];
            amount = bucketTotal * bucketDuration / remainingBucketTime;
            complianceFeePoolAmount += amount;
            bucketTotal = bucketTotal.sub(amount);
            compliantFeePoolBuckets[bucketStart] = bucketTotal;
            emit FeesWithdrawnFromBucket(bucketStart, amount, bucketTotal, true);

            _lastAssignedAt = payUntil;

            assert(_lastAssignedAt <= bucketEnd);
            if (_lastAssignedAt == bucketEnd) {
                delete generalFeePoolBuckets[bucketStart];
                delete compliantFeePoolBuckets[bucketStart];
            }

            bucketsPayed++;
        }

        generalValidatorFee = divideFees(committee, compliance, generalFeePoolAmount, false);
        certifiedValidatorFee = generalValidatorFee + divideFees(committee, compliance, complianceFeePoolAmount, true);
    }

    function divideFees(address[] memory committee, bool[] memory compliance, uint256 amount, bool isCompliant) private returns (uint48 validatorFee) {
        uint n = committee.length;
        if (isCompliant)  {
            n = 0; // todo - this is calculated in other places, get as argument to save gas
            for (uint i = 0; i < committee.length; i++) {
                if (compliance[i]) n++;
            }
        }
        if (n > 0) {
            validatorFee = toUint48Granularity(amount.div(n));
        }

        uint48 remainder = toUint48Granularity(amount.sub(toUint256Granularity(validatorFee).mul(n)));
        if (remainder > 0) {
            fillFeeBucket(_bucketTime(now), remainder, isCompliant);
        }
    }

    function fillGeneralFeeBuckets(uint256 amount, uint256 monthlyRate, uint256 fromTimestamp) external {
        fillFeeBuckets(amount, monthlyRate, fromTimestamp, false);
    }

    function fillComplianceFeeBuckets(uint256 amount, uint256 monthlyRate, uint256 fromTimestamp) external {
        fillFeeBuckets(amount, monthlyRate, fromTimestamp, true);
    }

    function fillFeeBucket(uint256 bucketId, uint256 amount, bool isCompliant) private {
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
        assignRewards(); // to handle rate change in the middle of a bucket time period (TBD - this is nice to have, consider removing)

        uint256 bucket = _bucketTime(fromTimestamp);
        uint256 _amount = amount;

        // add the partial amount to the first bucket
        uint256 bucketAmount = Math.min(amount, monthlyRate.mul(feeBucketTimePeriod - fromTimestamp % feeBucketTimePeriod).div(feeBucketTimePeriod));
        fillFeeBucket(bucket, bucketAmount, isCompliant);
        _amount = _amount.sub(bucketAmount);

        // following buckets are added with the monthly rate
        while (_amount > 0) {
            bucket = bucket.add(feeBucketTimePeriod);
            bucketAmount = Math.min(monthlyRate, _amount);
            fillFeeBucket(bucket, bucketAmount, isCompliant);
            _amount = _amount.sub(bucketAmount);
        }

        assert(_amount == 0);
    }

    function withdrawFeeFunds() external {
        uint48 amount = balances[msg.sender].fees;
        balances[msg.sender].fees = 0;
        totalBalances.feesTotalBalance = uint48(totalBalances.feesTotalBalance.sub(amount));
        require(transfer(erc20, msg.sender, amount), "Rewards::claimExternalTokenRewards - insufficient funds");
    }

    function getTotalBalances() external view returns (uint256 feesTotalBalance, uint256 stakingRewardsTotalBalance, uint256 bootstrapRewardsTotalBalance) {
        TotalBalances memory totals = totalBalances;
        return (toUint256Granularity(totals.feesTotalBalance), toUint256Granularity(totals.stakingRewardsTotalBalance), toUint256Granularity(totals.bootstrapRewardsTotalBalance));
    }

    function _bucketTime(uint256 time) private pure returns (uint256) {
        return time - time % feeBucketTimePeriod;
    }

}
