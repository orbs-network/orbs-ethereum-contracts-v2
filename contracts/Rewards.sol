pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./spec_interfaces/IContractRegistry.sol";
import "./spec_interfaces/ICommittee.sol";
import "./spec_interfaces/IProtocolWallet.sol";
import "./ContractRegistryAccessor.sol";
import "./Erc20AccessorWithTokenGranularity.sol";
import "./spec_interfaces/IFeesWallet.sol";
import "./Lockable.sol";

contract Rewards is IRewards, ERC20AccessorWithTokenGranularity, Lockable {
    using SafeMath for uint256;
    using SafeMath for uint48;

    struct Settings {
        uint48 generalCommitteeAnnualBootstrap;
        uint48 certificationCommitteeAnnualBootstrap;
        uint48 annualRateInPercentMille;
        uint48 annualCap;
        uint32 maxDelegatorsStakingRewardsPercentMille;
    }
    Settings settings;

    IERC20 bootstrapToken;
    IERC20 erc20;

    struct Balance {
        uint48 bootstrapRewards;
        uint48 fees;
        uint48 stakingRewards;
    }
    mapping(address => Balance) balances;

    uint256 lastAssignedAt;

    modifier onlyCommitteeContract() {
        require(msg.sender == address(committeeContract), "caller is not the committee contract");

        _;
    }

    constructor(IContractRegistry _contractRegistry, address _registryManager, IERC20 _erc20, IERC20 _bootstrapToken) Lockable(_contractRegistry, _registryManager) public {
        require(address(_bootstrapToken) != address(0), "bootstrapToken must not be 0");
        require(address(_erc20) != address(0), "erc20 must not be 0");

        erc20 = _erc20;
        bootstrapToken = _bootstrapToken;

        // TODO - The initial lastPayedAt should be set in the first assignRewards.
        lastAssignedAt = now;
    }

    // bootstrap rewards

    function setGeneralCommitteeAnnualBootstrap(uint256 annual_amount) external onlyFunctionalManager onlyWhenActive {
        settings.generalCommitteeAnnualBootstrap = toUint48Granularity(annual_amount);
    }

    function setCertificationCommitteeAnnualBootstrap(uint256 annual_amount) external onlyFunctionalManager onlyWhenActive {
        settings.certificationCommitteeAnnualBootstrap = toUint48Granularity(annual_amount);
    }

    function setMaxDelegatorsStakingRewards(uint32 maxDelegatorsStakingRewardsPercentMille) external onlyFunctionalManager onlyWhenActive {
        require(maxDelegatorsStakingRewardsPercentMille <= 100000, "maxDelegatorsStakingRewardsPercentMille must not be larger than 100000");
        settings.maxDelegatorsStakingRewardsPercentMille = maxDelegatorsStakingRewardsPercentMille;
        emit MaxDelegatorsStakingRewardsChanged(maxDelegatorsStakingRewardsPercentMille);
    }

    function getBootstrapBalance(address addr) external view returns (uint256) {
        return toUint256Granularity(balances[addr].bootstrapRewards);
    }

    function assignRewards() public onlyWhenActive {
        (address[] memory committee, uint256[] memory weights, bool[] memory certification) = committeeContract.getCommittee();
        _assignRewardsToCommittee(committee, weights, certification);
    }

    function assignRewardsToCommittee(address[] calldata committee, uint256[] calldata committeeWeights, bool[] calldata certification) external onlyCommitteeContract onlyWhenActive {
        _assignRewardsToCommittee(committee, committeeWeights, certification);
    }

    struct Totals {
        uint48 bootstrapRewardsTotalBalance;
        uint48 feesTotalBalance;
        uint48 stakingRewardsTotalBalance;
    }

    function _assignRewardsToCommittee(address[] memory committee, uint256[] memory committeeWeights, bool[] memory certification) private {
        Settings memory _settings = settings;

        (uint256 generalGuardianBootstrap, uint256 certifiedGuardianBootstrap) = collectBootstrapRewards(_settings);
        (uint256 generalGuardianFee, uint256 certifiedGuardianFee) = collectFees(committee, certification);
        (uint256[] memory stakingRewards) = collectStakingRewards(committee, committeeWeights, _settings);

        Totals memory totals;

        Balance memory balance;
        for (uint i = 0; i < committee.length; i++) {
            balance = balances[committee[i]];

            balance.bootstrapRewards += toUint48Granularity(certification[i] ? certifiedGuardianBootstrap : generalGuardianBootstrap);
            balance.fees += toUint48Granularity(certification[i] ? certifiedGuardianFee : generalGuardianFee);
            balance.stakingRewards += toUint48Granularity(stakingRewards[i]);

            totals.bootstrapRewardsTotalBalance += toUint48Granularity(certification[i] ? certifiedGuardianBootstrap : generalGuardianBootstrap);
            totals.feesTotalBalance += toUint48Granularity(certification[i] ? certifiedGuardianFee : generalGuardianFee);
            totals.stakingRewardsTotalBalance += toUint48Granularity(stakingRewards[i]);

            balances[committee[i]] = balance;
        }

        stakingRewardsWallet.withdraw(toUint256Granularity(totals.stakingRewardsTotalBalance));
        bootstrapRewardsWallet.withdraw(toUint256Granularity(totals.bootstrapRewardsTotalBalance));

        lastAssignedAt = now;

        emit StakingRewardsAssigned(committee, stakingRewards);
        emit BootstrapRewardsAssigned(generalGuardianBootstrap, certifiedGuardianBootstrap);
        emit FeesAssigned(generalGuardianFee, certifiedGuardianFee);
    }

    function collectBootstrapRewards(Settings memory _settings) private view returns (uint256 generalGuardianBootstrap, uint256 certifiedGuardianBootstrap){
        uint256 duration = now.sub(lastAssignedAt);
        generalGuardianBootstrap = toUint256Granularity(uint48(_settings.generalCommitteeAnnualBootstrap.mul(duration).div(365 days)));
        certifiedGuardianBootstrap = generalGuardianBootstrap + toUint256Granularity(uint48(_settings.certificationCommitteeAnnualBootstrap.mul(duration).div(365 days)));
    }

    function withdrawBootstrapFunds(address guardian) external {
        uint48 amount = balances[guardian].bootstrapRewards;
        balances[guardian].bootstrapRewards = 0;
        emit BootstrapRewardsWithdrawn(guardian, toUint256Granularity(amount));
        require(transfer(bootstrapToken, guardian, amount), "Rewards::withdrawBootstrapFunds - insufficient funds");
    }

    // staking rewards

    function setAnnualStakingRewardsRate(uint256 annual_rate_in_percent_mille, uint256 annual_cap) external onlyFunctionalManager onlyWhenActive {
        Settings memory _settings = settings;
        _settings.annualRateInPercentMille = uint48(annual_rate_in_percent_mille);
        _settings.annualCap = toUint48Granularity(annual_cap);
        settings = _settings;
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

            uint annualRateInPercentMille = Math.min(uint(_settings.annualRateInPercentMille), toUint256Granularity(_settings.annualCap).mul(100000).div(totalWeight));
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
        return delegatorRewards.mul(100000) <= uint(settings.maxDelegatorsStakingRewardsPercentMille).mul(totalRewards.add(toUint256Granularity(1))); // +1 is added to account for rounding errors
    }

    struct distributeStakingRewardsVars {
        bool firstTxBySender;
        address guardianAddr;
        uint256 delegatorsAmount;
    }
    function distributeStakingRewards(uint256 totalAmount, uint256 fromBlock, uint256 toBlock, uint split, uint txIndex, address[] calldata to, uint256[] calldata amounts) external onlyWhenActive {
        require(to.length > 0, "list must contain at least one recipient");
        require(to.length == amounts.length, "expected to and amounts to be of same length");
        uint48 totalAmount_uint48 = toUint48Granularity(totalAmount);
        require(totalAmount == toUint256Granularity(totalAmount_uint48), "totalAmount must divide by 1e15");

        distributeStakingRewardsVars memory vars;

        vars.guardianAddr = guardianRegistrationContract.resolveGuardianAddress(msg.sender);

        for (uint i = 0; i < to.length; i++) {
            if (to[i] != vars.guardianAddr) {
                vars.delegatorsAmount = vars.delegatorsAmount.add(amounts[i]);
            }
        }
        require(isDelegatorRewardsBelowThreshold(vars.delegatorsAmount, totalAmount), "Total delegators reward must be less then maxDelegatorsStakingRewardsPercentMille of total amount");

        DistributorBatchState memory ds = distributorBatchState[vars.guardianAddr];
        vars.firstTxBySender = ds.nextTxIndex == 0;

        if (vars.firstTxBySender || fromBlock == ds.toBlock + 1) { // New distribution batch
            require(vars.firstTxBySender || txIndex == 0, "txIndex must be 0 for the first transaction of a new (non-initial) distribution batch");
            require(toBlock < block.number, "toBlock must be in the past");
            require(toBlock >= fromBlock, "toBlock must be at least fromBlock");
            ds.fromBlock = fromBlock;
            ds.toBlock = toBlock;
            ds.split = split;
            ds.nextTxIndex = txIndex + 1;
            distributorBatchState[vars.guardianAddr] = ds;
        } else {
            require(fromBlock == ds.fromBlock, "fromBlock mismatch");
            require(toBlock == ds.toBlock, "toBlock mismatch");
            require(txIndex == ds.nextTxIndex, "txIndex mismatch");
            require(split == ds.split, "split mismatch");
            distributorBatchState[vars.guardianAddr].nextTxIndex = txIndex + 1;
        }

        require(totalAmount_uint48 <= balances[vars.guardianAddr].stakingRewards, "not enough member balance for this distribution");

        balances[vars.guardianAddr].stakingRewards = uint48(balances[vars.guardianAddr].stakingRewards.sub(totalAmount_uint48));

        IStakingContract _stakingContract = stakingContract;

        approve(erc20, address(_stakingContract), totalAmount_uint48);
        _stakingContract.distributeRewards(totalAmount, to, amounts); // TODO should we rely on staking contract to verify total amount?

        delegationsContract.refreshStakeNotification(vars.guardianAddr);

        emit StakingRewardsDistributed(vars.guardianAddr, fromBlock, toBlock, split, txIndex, to, amounts);
    }

    function collectFees(address[] memory committee, bool[] memory certification) private returns (uint256 generalGuardianFee, uint256 certifiedGuardianFee) {
        uint generalFeePoolAmount = generalFeesWallet.collectFees();
        uint certificationFeePoolAmount = certifiedFeesWallet.collectFees();

        generalGuardianFee = divideFees(committee, certification, generalFeePoolAmount, false);
        certifiedGuardianFee = generalGuardianFee + divideFees(committee, certification, certificationFeePoolAmount, true);
    }

    function getFeeBalance(address addr) external view returns (uint256) {
        return toUint256Granularity(balances[addr].fees);
    }

    function divideFees(address[] memory committee, bool[] memory certification, uint256 amount, bool isCertified) private pure returns (uint256 guardianFee) {
        uint n = committee.length;
        if (isCertified)  {
            n = 0;
            for (uint i = 0; i < committee.length; i++) {
                if (certification[i]) n++;
            }
        }
        if (n > 0) {
            guardianFee = toUint256Granularity(toUint48Granularity(amount.div(n)));
        }
    }

    function withdrawFees(address guardian) external {
        uint48 amount = balances[guardian].fees;
        balances[guardian].fees = 0;
        emit FeesWithdrawn(guardian, toUint256Granularity(amount));
        require(transfer(erc20, guardian, amount), "Rewards::claimExternalTokenRewards - insufficient funds");
    }

    function migrateStakingRewardsBalance(address guardian) external {
        IRewards currentRewardsContract = IRewards(getRewardsContract());
        if (currentRewardsContract == this) {
            return;
        }

        uint48 balance = balances[guardian].stakingRewards;
        balances[guardian].stakingRewards = 0;

        require(approve(erc20, address(currentRewardsContract), balance), "migrateStakingBalance: approve failed");
        currentRewardsContract.acceptStakingRewardsMigration(guardian, toUint256Granularity(balance));

        emit StakingRewardsBalanceMigrated(guardian, toUint256Granularity(balance), address(currentRewardsContract));
    }

    function acceptStakingRewardsMigration(address guardian, uint256 amount) external {
        uint48 amount48 = toUint48Granularity(amount);
        require(transferFrom(erc20, msg.sender, address(this), amount48), "acceptStakingMigration: transfer failed");

        uint48 balance = balances[guardian].stakingRewards + amount48;
        balances[guardian].stakingRewards = balance;

        emit StakingRewardsMigrationAccepted(msg.sender, guardian, amount);
    }

    function emergencyWithdraw() external onlyMigrationManager {
        emit EmergencyWithdrawal(msg.sender);
        require(erc20.transfer(msg.sender, erc20.balanceOf(address(this))), "Rewards::emergencyWithdraw - transfer failed (fee token)");
        require(bootstrapToken.transfer(msg.sender, bootstrapToken.balanceOf(address(this))), "Rewards::emergencyWithdraw - transfer failed (bootstrap token)");
    }

    ICommittee committeeContract;
    IDelegations delegationsContract;
    IGuardiansRegistration guardianRegistrationContract;
    IStakingContract stakingContract;
    IFeesWallet generalFeesWallet;
    IFeesWallet certifiedFeesWallet;
    IProtocolWallet stakingRewardsWallet;
    IProtocolWallet bootstrapRewardsWallet;
    function refreshContracts() external {
        committeeContract = ICommittee(getCommitteeContract());
        delegationsContract = IDelegations(getDelegationsContract());
        guardianRegistrationContract = IGuardiansRegistration(getGuardiansRegistrationContract());
        stakingContract = IStakingContract(getStakingContract());
        generalFeesWallet = IFeesWallet(getGeneralFeesWallet());
        certifiedFeesWallet = IFeesWallet(getCertifiedFeesWallet());
        stakingRewardsWallet = IProtocolWallet(getStakingRewardsWallet());
        bootstrapRewardsWallet = IProtocolWallet(getBootstrapRewardsWallet());
    }

}
