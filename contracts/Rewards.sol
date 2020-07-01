pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./spec_interfaces/IContractRegistry.sol";
import "./spec_interfaces/ICommittee.sol";
import "./spec_interfaces/IProtocolWallet.sol";
import "./ContractRegistryAccessor.sol";
import "./Erc20AccessorWithTokenGranularity.sol";
import "./WithClaimableFunctionalOwnership.sol";

contract Rewards is IRewards, ContractRegistryAccessor, ERC20AccessorWithTokenGranularity, WithClaimableFunctionalOwnership, Lockable {
    using SafeMath for uint256;
    using SafeMath for uint48; // TODO this is meaningless for overflow detection, SafeMath is only for uint256. Should still detect underflows

    struct Settings {
        uint48 generalCommitteeAnnualBootstrap;
        uint48 complianceCommitteeAnnualBootstrap;
        uint48 annualRateInPercentMille;
        uint48 annualCap;
        uint32 maxDelegatorsStakingRewardsPercentMille;
    }
    Settings settings;

    struct PoolsAndTotalBalances {
        uint48 bootstrapPool;
        uint48 stakingPool;
        uint48 bootstrapRewardsTotalBalance;
        uint48 feesTotalBalance;
        uint48 stakingRewardsTotalBalance;
    }
    PoolsAndTotalBalances poolsAndTotalBalances;

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

    function setGeneralCommitteeAnnualBootstrap(uint256 annual_amount) external onlyFunctionalOwner onlyWhenActive {
        settings.generalCommitteeAnnualBootstrap = toUint48Granularity(annual_amount);
    }

    function setComplianceCommitteeAnnualBootstrap(uint256 annual_amount) external onlyFunctionalOwner onlyWhenActive {
        settings.complianceCommitteeAnnualBootstrap = toUint48Granularity(annual_amount);
    }

    function setMaxDelegatorsStakingRewardsPercentMille(uint32 maxDelegatorsStakingRewardsPercentMille) external onlyFunctionalOwner onlyWhenActive {
        require(maxDelegatorsStakingRewardsPercentMille <= 100000, "maxDelegatorsStakingRewardsPercentMille must not be larger than 100000");
        settings.maxDelegatorsStakingRewardsPercentMille = maxDelegatorsStakingRewardsPercentMille;
        emit MaxDelegatorsStakingRewardsChanged(maxDelegatorsStakingRewardsPercentMille);
    }

    function topUpBootstrapPool(uint256 amount) external onlyWhenActive {
        uint48 _amount48 = toUint48Granularity(amount);
        uint48 bootstrapPool = uint48(poolsAndTotalBalances.bootstrapPool.add(_amount48)); // todo may overflow
        poolsAndTotalBalances.bootstrapPool = bootstrapPool;
        require(transferFrom(bootstrapToken, msg.sender, address(this), _amount48), "Rewards::topUpFixedPool - insufficient allowance");
        emit BootstrapAddedToPool(amount, toUint256Granularity(bootstrapPool));
    }

    function getBootstrapBalance(address addr) external view returns (uint256) {
        return toUint256Granularity(balances[addr].bootstrapRewards);
    }

    function assignRewards() public onlyWhenActive {
        (address[] memory committee, uint256[] memory weights, bool[] memory compliance) = getCommitteeContract().getCommittee();
        _assignRewardsToCommittee(committee, weights, compliance);
    }

    function assignRewardsToCommittee(address[] calldata committee, uint256[] calldata committeeWeights, bool[] calldata compliance) external onlyCommitteeContract onlyWhenActive {
        _assignRewardsToCommittee(committee, committeeWeights, compliance);
    }

    struct Totals {
        uint48 bootstrapRewardsTotalBalance;
        uint48 feesTotalBalance;
        uint48 stakingRewardsTotalBalance;
    }

    function _assignRewardsToCommittee(address[] memory committee, uint256[] memory committeeWeights, bool[] memory compliance) private {
        Settings memory _settings = settings;

        (uint256 generalValidatorBootstrap, uint256 certifiedValidatorBootstrap) = collectBootstrapRewards(_settings);
        (uint256 generalValidatorFee, uint256 certifiedValidatorFee) = collectFees(committee, compliance);
        (uint256[] memory stakingRewards) = collectStakingRewards(committee, committeeWeights, _settings);

        PoolsAndTotalBalances memory totals = poolsAndTotalBalances;

        Totals memory origTotals = Totals({
            bootstrapRewardsTotalBalance: totals.bootstrapRewardsTotalBalance,
            feesTotalBalance: totals.feesTotalBalance,
            stakingRewardsTotalBalance: totals.stakingRewardsTotalBalance
        });

        Balance memory balance;
        for (uint i = 0; i < committee.length; i++) {
            balance = balances[committee[i]];

            balance.bootstrapRewards += toUint48Granularity(compliance[i] ? certifiedValidatorBootstrap : generalValidatorBootstrap);
            balance.fees += toUint48Granularity(compliance[i] ? certifiedValidatorFee : generalValidatorFee);
            balance.stakingRewards += toUint48Granularity(stakingRewards[i]);

            totals.bootstrapRewardsTotalBalance += toUint48Granularity(compliance[i] ? certifiedValidatorBootstrap : generalValidatorBootstrap); // todo may overflow
            totals.feesTotalBalance += toUint48Granularity(compliance[i] ? certifiedValidatorFee : generalValidatorFee); // todo may overflow
            totals.stakingRewardsTotalBalance += toUint48Granularity(stakingRewards[i]); // todo may overflow

            balances[committee[i]] = balance;
        }

//        require(toUint256Granularity(uint48(totals.stakingRewardsTotalBalance.sub(origTotals.stakingRewardsTotalBalance))) <  20000000000000000000000, "aaaa");
        getStakingRewardsWallet().withdraw(toUint256Granularity(uint48(totals.stakingRewardsTotalBalance.sub(origTotals.stakingRewardsTotalBalance))));

        poolsAndTotalBalances = totals;
        lastAssignedAt = now;

        emit StakingRewardsAssigned(committee, stakingRewards);
        emit BootstrapRewardsAssigned(generalValidatorBootstrap, certifiedValidatorBootstrap);
        emit FeesAssigned(generalValidatorFee, certifiedValidatorFee);
    }

    function collectBootstrapRewards(Settings memory _settings) private view returns (uint256 generalValidatorBootstrap, uint256 certifiedValidatorBootstrap){
        uint256 duration = now.sub(lastAssignedAt);
        generalValidatorBootstrap = toUint256Granularity(uint48(_settings.generalCommitteeAnnualBootstrap.mul(duration).div(365 days)));
        certifiedValidatorBootstrap = generalValidatorBootstrap + toUint256Granularity(uint48(_settings.complianceCommitteeAnnualBootstrap.mul(duration).div(365 days)));
    }

    function withdrawBootstrapFunds() external onlyWhenActive {
        uint48 amount = balances[msg.sender].bootstrapRewards;

        PoolsAndTotalBalances memory _poolsAndTotalBalances = poolsAndTotalBalances;

        require(amount <= _poolsAndTotalBalances.bootstrapPool, "not enough balance in the bootstrap pool for this withdrawal");
        balances[msg.sender].bootstrapRewards = 0;
        _poolsAndTotalBalances.bootstrapRewardsTotalBalance = uint48(_poolsAndTotalBalances.bootstrapRewardsTotalBalance.sub(amount));
        _poolsAndTotalBalances.bootstrapPool = uint48(_poolsAndTotalBalances.bootstrapPool.sub(amount));
        poolsAndTotalBalances = _poolsAndTotalBalances;

        emit BootstrapRewardsWithdrawn(msg.sender, toUint256Granularity(amount));
        require(transfer(bootstrapToken, msg.sender, amount), "Rewards::withdrawBootstrapFunds - insufficient funds");
    }

    // staking rewards

    function setAnnualStakingRewardsRate(uint256 annual_rate_in_percent_mille, uint256 annual_cap) external onlyFunctionalOwner onlyWhenActive {
        Settings memory _settings = settings;
        _settings.annualRateInPercentMille = uint48(annual_rate_in_percent_mille);
        _settings.annualCap = toUint48Granularity(annual_cap);
        settings = _settings;
    }

    function topUpStakingRewardsPool(uint256 amount) external onlyWhenActive {
        uint48 amount48 = toUint48Granularity(amount);
        uint48 total48 = uint48(poolsAndTotalBalances.stakingPool.add(amount48));
        poolsAndTotalBalances.stakingPool = total48;
        emit StakingRewardsAddedToPool(amount, toUint256Granularity(total48));
        require(erc20.transferFrom(msg.sender, address(this), amount), "Rewards::topUpProRataPool - insufficient allowance");

        IProtocolWallet wallet = getStakingRewardsWallet();
        require(erc20.approve(address(wallet), amount), "Rewards::topUpProRataPool - approve failed");
        wallet.topUp(amount);
    }

    function getStakingRewardBalance(address addr) external view returns (uint256) {
        return toUint256Granularity(balances[addr].stakingRewards);
    }

    function getLastRewardAssignmentTime() external view returns (uint256) {
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
                curAmount = toUint48Granularity(weights[i].mul(annualRateInPercentMille).mul(duration).div(36500000 days));
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

    function isDelegatorRewardsBelowThreshold(uint256 delegatorRewards, uint256 totalRewards) private view returns (bool) {
        return delegatorRewards.mul(100000) <= uint(settings.maxDelegatorsStakingRewardsPercentMille).mul(totalRewards);
    }

    struct VistributeOrbsTokenStakingRewardsVars {
        bool firstTxBySender;
        address guardianAddr;
    }
    function distributeOrbsTokenStakingRewards(uint256 totalAmount, uint256 fromBlock, uint256 toBlock, uint split, uint txIndex, address[] calldata to, uint256[] calldata amounts) external onlyWhenActive {
        require(to.length > 0, "list must containt at least one recipient");
        require(to.length == amounts.length, "expected to and amounts to be of same length");
        uint48 totalAmount_uint48 = toUint48Granularity(totalAmount);
        require(totalAmount == toUint256Granularity(totalAmount_uint48), "totalAmount must divide by 1e15");

        VistributeOrbsTokenStakingRewardsVars memory vars;

        vars.guardianAddr = getValidatorsRegistrationContract().resolveGuardianAddress(msg.sender);
        require(to[0] == vars.guardianAddr, "first member in list must be the the guardian address");
        require(isDelegatorRewardsBelowThreshold(totalAmount.sub(amounts[0]), totalAmount), "Total delegators reward (to[1:n]) must be less then maxDelegatorsStakingRewardsPercentMille of total amount");

        DistributorBatchState memory ds = distributorBatchState[vars.guardianAddr];
        vars.firstTxBySender = ds.nextTxIndex == 0;

        require(!vars.firstTxBySender || fromBlock == 0, "on the first batch fromBlock must be 0");

        if (vars.firstTxBySender || fromBlock == ds.toBlock + 1) { // New distribution batch
            require(txIndex == 0, "txIndex must be 0 for the first transaction of a new distribution batch");
            require(toBlock < block.number, "toBlock must be in the past");
            require(toBlock >= fromBlock, "toBlock must be at least fromBlock");
            ds.fromBlock = fromBlock;
            ds.toBlock = toBlock;
            ds.split = split;
            ds.nextTxIndex = 1;
            distributorBatchState[vars.guardianAddr] = ds;
        } else {
            require(txIndex == ds.nextTxIndex, "txIndex mismatch");
            require(toBlock == ds.toBlock, "toBlock mismatch");
            require(fromBlock == ds.fromBlock, "fromBlock mismatch");
            require(split == ds.split, "split mismatch");
            distributorBatchState[vars.guardianAddr].nextTxIndex = txIndex + 1;
        }

        require(totalAmount_uint48 <= balances[vars.guardianAddr].stakingRewards, "not enough member balance for this distribution");

        PoolsAndTotalBalances memory _poolsAndTotalBalances = poolsAndTotalBalances;

        require(totalAmount_uint48 <= _poolsAndTotalBalances.stakingPool, "not enough balance in the staking pool for this distribution");

        _poolsAndTotalBalances.stakingPool = uint48(_poolsAndTotalBalances.stakingPool.sub(totalAmount_uint48));
        balances[vars.guardianAddr].stakingRewards = uint48(balances[vars.guardianAddr].stakingRewards.sub(totalAmount_uint48));
        _poolsAndTotalBalances.stakingRewardsTotalBalance = uint48(_poolsAndTotalBalances.stakingRewardsTotalBalance.sub(totalAmount_uint48));

        poolsAndTotalBalances = _poolsAndTotalBalances;

        IStakingContract stakingContract = getStakingContract();

        approve(erc20, address(stakingContract), totalAmount_uint48);
        stakingContract.distributeRewards(totalAmount, to, amounts); // TODO should we rely on staking contract to verify total amount?

        emit StakingRewardsDistributed(vars.guardianAddr, fromBlock, toBlock, split, txIndex, to, amounts);
    }

    // fees

    function getFeeBalance(address addr) external view returns (uint256) {
        return toUint256Granularity(balances[addr].fees);
    }

    uint constant MAX_FEE_BUCKET_ITERATIONS = 24;

    function collectFees(address[] memory committee, bool[] memory compliance) private returns (uint256 generalValidatorFee, uint256 certifiedValidatorFee) {
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

    function divideFees(address[] memory committee, bool[] memory compliance, uint256 amount, bool isCompliant) private returns (uint256 validatorFee) {
        uint n = committee.length;
        if (isCompliant)  {
            n = 0; // todo - this is calculated in other places, get as argument to save gas
            for (uint i = 0; i < committee.length; i++) {
                if (compliance[i]) n++;
            }
        }
        if (n > 0) {
            validatorFee = toUint256Granularity(toUint48Granularity(amount.div(n)));
        }

        uint256 remainder = amount.sub(validatorFee.mul(n));
        if (remainder > 0) {
            fillFeeBucket(_bucketTime(now), remainder, isCompliant);
        }
    }

    function fillGeneralFeeBuckets(uint256 amount, uint256 monthlyRate, uint256 fromTimestamp) external onlyWhenActive {
        fillFeeBuckets(amount, monthlyRate, fromTimestamp, false);
    }

    function fillComplianceFeeBuckets(uint256 amount, uint256 monthlyRate, uint256 fromTimestamp) external onlyWhenActive {
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

        require(erc20.transferFrom(msg.sender, address(this), amount), "failed to transfer subscription fees from subscriptions to rewards");
    }

    function withdrawFeeFunds() external onlyWhenActive {
        uint48 amount = balances[msg.sender].fees;
        balances[msg.sender].fees = 0;
        poolsAndTotalBalances.feesTotalBalance = uint48(poolsAndTotalBalances.feesTotalBalance.sub(amount));
        emit FeesWithdrawn(msg.sender, toUint256Granularity(amount));
        require(transfer(erc20, msg.sender, amount), "Rewards::claimExternalTokenRewards - insufficient funds");
    }

    function getTotalBalances() external view returns (uint256 feesTotalBalance, uint256 stakingRewardsTotalBalance, uint256 bootstrapRewardsTotalBalance) {
        PoolsAndTotalBalances memory totals = poolsAndTotalBalances;
        return (toUint256Granularity(totals.feesTotalBalance), toUint256Granularity(totals.stakingRewardsTotalBalance), toUint256Granularity(totals.bootstrapRewardsTotalBalance));
    }

    function _bucketTime(uint256 time) private pure returns (uint256) {
        return time - time % feeBucketTimePeriod;
    }

}
