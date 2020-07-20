pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "./IStakingContract.sol";
import "./ContractRegistryAccessor.sol";
import "./WithClaimableFunctionalOwnership.sol";
import "./Erc20AccessorWithTokenGranularity.sol";

contract GuardiansWallet is IGuardiansWallet, ContractRegistryAccessor, WithClaimableFunctionalOwnership, ERC20AccessorWithTokenGranularity {
    using SafeMath for uint256;
    using SafeMath for uint48;

    IERC20 feesToken;
    IERC20 stakingToken;
    IERC20 bootstrapToken;

    struct Balance {
        uint48 bootstrapRewards;
        uint48 fees;
        uint48 stakingRewards;
    }
    mapping(address => Balance) balances;

    uint32 maxDelegatorsStakingRewardsPercentMille;

    constructor(IERC20 _feesToken, IERC20 _stakingToken, IERC20 _bootstrapToken, uint32 _maxDelegatorsStakingRewardsPercentMille) public {
        require(_maxDelegatorsStakingRewardsPercentMille <= 100000, "_maxDelegatorsStakingRewardsPercentMille must not be larger than 100000");
        require(_feesToken != IERC20(0), "feesToken must not be 0");
        require(_stakingToken != IERC20(0), "stakingToken must not be 0");
        require(_bootstrapToken != IERC20(0), "bootstrapToken must not be 0");

        maxDelegatorsStakingRewardsPercentMille = _maxDelegatorsStakingRewardsPercentMille;
        feesToken = _feesToken;
        stakingToken = _stakingToken;
        bootstrapToken = _bootstrapToken;
    }

    function assignRewardsToGuardians(address[] calldata guardians, uint256[] calldata stakingRewards, uint256[] calldata fees, uint256[] calldata bootstrapRewards) external {
        uint totalBootstrapRewards;
        uint totalFees;
        uint totalStakingRewards;
        Balance memory balance;

        for (uint i = 0; i < guardians.length; i++) {
            balance = balances[guardians[i]];

            balance.bootstrapRewards += toUint48Granularity(bootstrapRewards[i]);
            totalBootstrapRewards = totalBootstrapRewards.add(bootstrapRewards[i]);

            balance.fees += toUint48Granularity(fees[i]);
            totalFees = totalFees.add(fees[i]);

            balance.stakingRewards += toUint48Granularity(stakingRewards[i]);
            totalStakingRewards = totalStakingRewards.add(stakingRewards[i]);

            balances[guardians[i]] = balance;
        }

        feesToken.transferFrom(msg.sender, address(this), totalFees);
        bootstrapToken.transferFrom(msg.sender, address(this), totalBootstrapRewards);
        stakingToken.transferFrom(msg.sender,  address(this), totalStakingRewards);

        emit RewardsAssigned(guardians, stakingRewards, fees, bootstrapRewards);
    }

    function setMaxDelegatorsStakingRewards(uint32 _maxDelegatorsStakingRewardsPercentMille) external onlyFunctionalOwner {
        require(_maxDelegatorsStakingRewardsPercentMille <= 100000, "_maxDelegatorsStakingRewardsPercentMille must not be larger than 100000");
        maxDelegatorsStakingRewardsPercentMille = _maxDelegatorsStakingRewardsPercentMille;
        emit MaxDelegatorsStakingRewardsChanged(_maxDelegatorsStakingRewardsPercentMille);
    }

    function getBootstrapBalance(address addr) external view returns (uint256) {
        return toUint256Granularity(balances[addr].bootstrapRewards);
    }

    function withdrawBootstrapFunds() external {
        address guardianAddress = getGuardiansRegistrationContract().resolveGuardianAddress(msg.sender);

        uint48 amount = balances[guardianAddress].bootstrapRewards;

        balances[guardianAddress].bootstrapRewards = 0;

        emit BootstrapRewardsWithdrawn(guardianAddress, toUint256Granularity(amount));
        require(transfer(bootstrapToken, guardianAddress, amount), "GuardiansWallet::withdrawBootstrapFunds - insufficient funds");
    }

    function getStakingRewardBalance(address addr) external view returns (uint256) {
        return toUint256Granularity(balances[addr].stakingRewards);
    }

    struct DistributorBatchState {
        uint256 fromBlock;
        uint256 toBlock;
        uint256 nextTxIndex;
        uint split;
    }
    mapping (address => DistributorBatchState) distributorBatchState;

    function isDelegatorRewardsBelowThreshold(uint256 delegatorRewards, uint256 totalRewards) private view returns (bool) {
        return delegatorRewards.mul(100000) <= uint(maxDelegatorsStakingRewardsPercentMille).mul(totalRewards.add(toUint256Granularity(1))); // +1 is added to account for rounding errors
    }

    struct DistributeOrbsTokenStakingRewardsVars {
        bool firstTxBySender;
        address guardianAddr;
        uint256 delegatorsAmount;
    }
    function distributeStakingRewards(uint256 totalAmount, uint256 fromBlock, uint256 toBlock, uint split, uint txIndex, address[] calldata to, uint256[] calldata amounts) external {
        require(to.length > 0, "list must contain at least one recipient");
        require(to.length == amounts.length, "expected to and amounts to be of same length");
        uint48 totalAmount_uint48 = toUint48Granularity(totalAmount);
        require(totalAmount == toUint256Granularity(totalAmount_uint48), "totalAmount must divide by 1e15");

        DistributeOrbsTokenStakingRewardsVars memory vars;

        vars.guardianAddr = getGuardiansRegistrationContract().resolveGuardianAddress(msg.sender);

        for (uint i = 0; i < to.length; i++) {
            if (to[i] != vars.guardianAddr) {
                vars.delegatorsAmount = vars.delegatorsAmount.add(amounts[i]);
            }
        }
        require(isDelegatorRewardsBelowThreshold(vars.delegatorsAmount, totalAmount), "Total delegators reward (to[1:n]) must be less then maxDelegatorsStakingRewardsPercentMille of total amount");

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

        balances[vars.guardianAddr].stakingRewards = uint48(balances[vars.guardianAddr].stakingRewards.sub(totalAmount_uint48));

        IStakingContract stakingContract = getStakingContract();

        approve(stakingToken, address(stakingContract), totalAmount_uint48);
        stakingContract.distributeRewards(totalAmount, to, amounts); // TODO should we rely on staking contract to verify total amount?

        getDelegationsContract().refreshStakeNotification(vars.guardianAddr);

        emit StakingRewardsDistributed(vars.guardianAddr, fromBlock, toBlock, split, txIndex, to, amounts);
    }

    // fees

    function withdrawFees() external {
        address guardianAddress = getGuardiansRegistrationContract().resolveGuardianAddress(msg.sender);
        uint48 amount = balances[guardianAddress].fees;
        balances[guardianAddress].fees = 0;
        emit FeesWithdrawn(guardianAddress, toUint256Granularity(amount));
        require(transfer(feesToken, guardianAddress, amount), "Rewards::claimExternalTokenRewards - insufficient funds");
    }

    function getFeeBalance(address addr) external view returns (uint256) {
        return toUint256Granularity(balances[addr].fees);
    }

    function emergencyWithdraw() external onlyMigrationOwner {
        emit EmergencyWithdrawal(msg.sender);
        require(feesToken.transfer(msg.sender, feesToken.balanceOf(address(this))), "GuardianWallet::emergencyWithdraw - transfer failed (fee token)");
        require(stakingToken.transfer(msg.sender, stakingToken.balanceOf(address(this))), "GuardianWallet::emergencyWithdraw - transfer failed (staking token)");
        require(bootstrapToken.transfer(msg.sender, bootstrapToken.balanceOf(address(this))), "GuardianWallet::emergencyWithdraw - transfer failed (bootstrap token)");
    }

}
