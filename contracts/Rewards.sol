pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./spec_interfaces/IContractRegistry.sol";
import "./spec_interfaces/IBootstrapRewards.sol";
import "./spec_interfaces/ICommittee.sol";
import "./ContractRegistryAccessor.sol";

contract Rewards is IRewards, ContractRegistryAccessor {
    using SafeMath for uint256;

    struct BootstrapAndStaking {
        uint256 bootstrapPool;
        uint256 generalCommitteeAnnualBootstrap;
        uint256 complianceCommitteeAnnualBootstrap;

        uint256 stakingPool;
        uint256 annualRateInPercentMille;
        uint256 annualCap;
    }
    BootstrapAndStaking bootstrapAndStaking;

    struct Balance {
        uint256 bootstrapRewards;
        uint256 fees;
        uint256 stakingRewards;
    }
    mapping(address => Balance) balance;

    // Bootstrap
//    mapping(address => uint256) bootstrapBalance;
    IERC20 bootstrapToken;

    // Staking
//    mapping(address => uint256) stakingRewardsBalance;

    // Fees
    uint256 constant feeBucketTimePeriod = 30 days;
    mapping(uint256 => uint256) generalFeePoolBuckets;
    mapping(uint256 => uint256) compliantFeePoolBuckets;
//    mapping(address => uint256) feesBalance;


    IERC20 erc20;
    uint256 lastPayedAt;

    address rewardsGovernor;

    // TODO - add functionality similar to ownable (transfer governance, etc)
    modifier onlyRewardsGovernor() {
        require(msg.sender == rewardsGovernor, "caller is not the rewards governor");

        _;
    }

    modifier onlyElectionsContract() {
        require(msg.sender == address(getElectionsContract()), "caller is not the elections");

        _;
    }

    constructor(IERC20 _erc20, IERC20 _bootstrapToken, address _rewardsGovernor) public {
        require(address(_bootstrapToken) != address(0), "bootstrapToken must not be 0");
        require(address(_erc20) != address(0), "erc20 must not be 0");

        erc20 = _erc20;
        bootstrapToken = _bootstrapToken;
        // TODO - The initial lastPayedAt should be set in the first assignRewards.
        lastPayedAt = now;
        rewardsGovernor = _rewardsGovernor;
    }

    // bootstrap rewards

    function setGeneralCommitteeAnnualBootstrap(uint256 annual_amount) external {
        BootstrapAndStaking memory pools = bootstrapAndStaking;
        _assignBootstrapRewards(_getCommittee(false), _getCommittee(true), pools);
        pools.generalCommitteeAnnualBootstrap = annual_amount;
        bootstrapAndStaking = pools;
    }

    function setComplianceCommitteeAnnualBootstrap(uint256 annual_amount) external {
        BootstrapAndStaking memory pools = bootstrapAndStaking;
        _assignBootstrapRewards(_getCommittee(false), _getCommittee(true), pools);
        pools.complianceCommitteeAnnualBootstrap = annual_amount;
        bootstrapAndStaking = pools;
    }

    function topUpBootstrapPool(uint256 amount) external {
        uint bootstrapPool = bootstrapAndStaking.bootstrapPool.add(amount);
        bootstrapAndStaking.bootstrapPool = bootstrapPool.add(amount);
        require(bootstrapToken.transferFrom(msg.sender, address(this), amount), "Rewards::topUpFixedPool - insufficient allowance");
        emit BootstrapAddedToPool(amount, bootstrapPool);
    }

    function getBootstrapBalance(address addr) external view returns (uint256) {
        return balance[addr].bootstrapRewards;
    }

    function getLastBootstrapAssignment() external view returns (uint256) {
        return lastPayedAt;
    }

    function assignRewards(address[] calldata generalCommittee, uint256[] calldata generalCommitteeWeights, address[] calldata complianceCommittee) external onlyElectionsContract {
        BootstrapAndStaking memory pools = bootstrapAndStaking;
        _assignBootstrapRewards(generalCommittee, complianceCommittee, pools);
        _assignStakingRewards(generalCommittee, generalCommitteeWeights, pools);
        _assignFees(generalCommittee, complianceCommittee);
        bootstrapAndStaking = pools;
        lastPayedAt = now;
    }

    function _assignBootstrapRewards(address[] memory generalCommittee, address[] memory complianceCommittee, BootstrapAndStaking memory pools) private {
        _assignBootstrapRewardsToCommittee(generalCommittee, pools.generalCommitteeAnnualBootstrap, pools);
        _assignBootstrapRewardsToCommittee(complianceCommittee, pools.complianceCommitteeAnnualBootstrap, pools);
    }

    function _assignBootstrapRewardsToCommittee(address[] memory committee, uint256 annualBootstrapRewards, BootstrapAndStaking memory pools) private {
        if (committee.length > 0) {
            uint256 duration = now.sub(lastPayedAt);
            uint256 amountPerValidator = Math.min(annualBootstrapRewards.mul(duration).div(365 days), pools.bootstrapPool.div(committee.length));
            pools.bootstrapPool = pools.bootstrapPool.sub(amountPerValidator * committee.length);

            uint256[] memory assignedRewards = new uint256[](committee.length);

            for (uint i = 0; i < committee.length; i++) {
                addToBootstrapBalance(committee[i], amountPerValidator);
                assignedRewards[i] = amountPerValidator;
            }

            emit BootstrapRewardsAssigned(committee, assignedRewards); // TODO separate event per committee?
        }
    }

    function addToBootstrapBalance(address addr, uint256 amount) private {
        balance[addr].bootstrapRewards = balance[addr].bootstrapRewards.add(amount);
    }

    function withdrawBootstrapFunds() external {
        uint256 amount = balance[msg.sender].bootstrapRewards;
        balance[msg.sender].bootstrapRewards = balance[msg.sender].bootstrapRewards.sub(amount);
        require(bootstrapToken.transfer(msg.sender, amount), "Rewards::claimbootstrapTokenRewards - insufficient funds");
    }

    // staking rewards

    function setAnnualStakingRewardsRate(uint256 annual_rate_in_percent_mille, uint256 annual_cap) external onlyRewardsGovernor {
        (address[] memory committee, uint256[] memory weights) = getGeneralCommitteeContract().getCommittee2();
        BootstrapAndStaking memory pools = bootstrapAndStaking;
        _assignStakingRewards(committee, weights, bootstrapAndStaking);
        pools.annualRateInPercentMille = annual_rate_in_percent_mille;
        pools.annualCap = annual_cap;
        bootstrapAndStaking = pools;
    }

    function topUpStakingRewardsPool(uint256 amount) external {
        bootstrapAndStaking.stakingPool = bootstrapAndStaking.stakingPool.add(amount);
        require(erc20.transferFrom(msg.sender, address(this), amount), "Rewards::topUpProRataPool - insufficient allowance");
    }

    function getStakingRewardBalance(address addr) external view returns (uint256) {
        return balance[addr].stakingRewards;
    }

    function getLastRewardsAssignment() external view returns (uint256) {
        return lastPayedAt;
    }

    function _assignStakingRewards(address[] memory committee, uint256[] memory weights, BootstrapAndStaking memory pools) private {
        // TODO we often do integer division for rate related calculation, which floors the result. Do we need to address this?
        // TODO for an empty committee or a committee with 0 total stake the divided amounts will be locked in the contract FOREVER

        uint256 totalAssigned = 0;
        uint256 totalWeight = 0;
        for (uint i = 0; i < committee.length; i++) {
            totalWeight = totalWeight.add(weights[i]);
        }

        if (totalWeight > 0) { // TODO - handle the case of totalStake == 0. consider also an empty committee. consider returning a boolean saying if the amount was successfully distributed or not and handle on caller side.
            uint256 duration = now.sub(lastPayedAt);

            uint256 annualAmount = Math.min(pools.annualRateInPercentMille.mul(totalWeight).div(100000), pools.annualCap);
            uint256 amount = Math.min(annualAmount.mul(duration).div(365 days), pools.stakingPool);
            pools.stakingPool = pools.stakingPool.sub(amount);

            uint256[] memory assignedRewards = new uint256[](committee.length);

            for (uint i = 0; i < committee.length; i++) {
                uint256 curAmount = amount.mul(weights[i]).div(totalWeight);
                assignedRewards[i] = curAmount;
                totalAssigned = totalAssigned.add(curAmount);
            }

            uint256 remainder = amount.sub(totalAssigned);
            if (remainder > 0 && committee.length > 0) {
                uint ind = now % committee.length;
                assignedRewards[ind] = assignedRewards[ind].add(remainder);
            }

            for (uint i = 0; i < committee.length; i++) {
                addToStakingRewardsBalance(committee[i], assignedRewards[i]);
            }
        }
    }

    function addToStakingRewardsBalance(address addr, uint256 amount) private {
        balance[addr].stakingRewards = balance[addr].stakingRewards.add(amount);
        emit StakingRewardAssigned(addr, amount, balance[addr].stakingRewards); // TODO event per committee?
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
        require(totalAmount <= balance[msg.sender].stakingRewards, "not enough balance for this distribution");

        DistributorBatchState memory ds = distributorBatchState[msg.sender];

        bool firstTxBySender = ds.nextTxIndex == 0;
        if (firstTxBySender) {
            require(fromBlock == 0, "initial distribution tx must be with fromBlock == 0");
        }

        if (firstTxBySender || fromBlock == ds.toBlock + 1) { // New distribution batch
            require(toBlock < block.number, "toBlock must be in the past");
            require(toBlock >= fromBlock, "toBlock must be at least fromBlock");
            require(txIndex == 0, "txIndex must be 0 for the first transaction of a new distribution batch");
            ds.fromBlock = fromBlock;
            ds.toBlock = toBlock;
            ds.split = split;
            ds.nextTxIndex = 1;
            distributorBatchState[msg.sender] = ds;
        } else {
            require(toBlock == ds.toBlock, "toBlock mismatch");
            require(fromBlock == ds.fromBlock, "fromBlock mismatch");
            require(split == ds.split, "split mismatch");
            require(txIndex == ds.nextTxIndex, "txIndex mismatch");
            distributorBatchState[msg.sender].nextTxIndex = txIndex + 1;
        }

        balance[msg.sender].stakingRewards = balance[msg.sender].stakingRewards.sub(totalAmount);

        IStakingContract stakingContract = getStakingContract();
        erc20.approve(address(stakingContract), totalAmount);
        stakingContract.distributeRewards(totalAmount, to, amounts); // TODO should we rely on staking contract to verify total amount?

        emit StakingRewardsDistributed(msg.sender, fromBlock, toBlock, split, txIndex, to, amounts);
    }

    // fees

    function getFeeBalance(address addr) external view returns (uint256) {
        return balance[addr].fees;
    }

    function getLastFeesAssignment() external view returns (uint256) {
        return lastPayedAt;
    }

    uint constant MAX_FEE_BUCKET_ITERATIONS = 6;

    function _assignFees(address[] memory generalCommittee, address[] memory complianceCommittee) private {
        // TODO we often do integer division for rate related calculation, which floors the result. Do we need to address this?
        // TODO for an empty committee or a committee with 0 total stake the divided amounts will be locked in the contract FOREVER

        // Fee pool
        uint bucketsPayed = 0;
        uint generalFeePoolAmount = 0;
        uint complianceFeePoolAmount = 0;
        while (bucketsPayed < MAX_FEE_BUCKET_ITERATIONS && lastPayedAt < now) {
            uint256 bucketStart = _bucketTime(lastPayedAt);
            uint256 bucketEnd = bucketStart.add(feeBucketTimePeriod);
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

        assignFeeAmountFixed(generalFeePoolAmount, generalCommittee);
        assignFeeAmountFixed(complianceFeePoolAmount, complianceCommittee);
    }

    function assignFeeAmountFixed(uint256 amount, address[] memory committee) private {
        uint256[] memory assignedFees = new uint256[](committee.length);

        uint256 totalAssigned = 0;

        for (uint i = 0; i < committee.length; i++) {
            uint256 curAmount = amount.div(committee.length);
            assignedFees[i] = curAmount;
            totalAssigned = totalAssigned.add(curAmount);
        }

        uint256 remainder = amount.sub(totalAssigned);
        if (remainder > 0 && committee.length > 0) {
            uint ind = now % committee.length;
            assignedFees[ind] = assignedFees[ind].add(remainder);
        }

        for (uint i = 0; i < committee.length; i++) {
            addToFeeBalance(committee[i], assignedFees[i]);
        }
        emit FeesAssigned(committee, assignedFees);
    }

    function addToFeeBalance(address addr, uint256 amount) private {
        balance[addr].fees = balance[addr].fees.add(amount);
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
        _assignFees(_getCommittee(false), _getCommittee(true)); // to handle rate change in the middle of a bucket time period (TBD - this is nice to have, consider removing)

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
        uint256 amount = balance[msg.sender].fees;
        balance[msg.sender].fees = 0;
        require(erc20.transfer(msg.sender, amount), "Rewards::claimExternalTokenRewards - insufficient funds");
    }

    function _bucketTime(uint256 time) private pure returns (uint256) {
        return time - time % feeBucketTimePeriod;
    }

    function _getCommittee(bool isCompliant) private view returns (address[] memory) {
        address[] memory validators;
        if (isCompliant) {
            (validators,) =  getComplianceCommitteeContract().getCommittee();
        } else {
            (validators,) =  getGeneralCommitteeContract().getCommittee();
        }
        return validators;
    }

}
