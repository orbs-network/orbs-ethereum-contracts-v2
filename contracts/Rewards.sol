// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;

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
import "./ManagedContract.sol";
import "./SafeMath48.sol";

contract Rewards is IRewards, ERC20AccessorWithTokenGranularity, ManagedContract {
    using SafeMath for uint256;
    using SafeMath48 for uint48;

    struct Settings {
        uint48 generalCommitteeAnnualBootstrap;
        uint48 certifiedCommitteeAnnualBootstrap;
        uint48 annualCap;
        uint32 annualRateInPercentMille;
        uint32 maxDelegatorsStakingRewardsPercentMille;
    }
    Settings settings;

    IERC20 bootstrapToken;
    IERC20 erc20;

    struct StakingRewardsTotals {
        uint96 stakingRewardsPerToken;
        uint32 lastAssigned;
    }

    StakingRewardsTotals stakingRewardsTotals;

    struct CommitteeTotalsPerMember {
        uint48 certifiedFees;
        uint48 generalFees;
        uint48 certifiedBootstrap;
        uint48 generalBootstrap;
        uint32 lastAssigned;
    }
    CommitteeTotalsPerMember committeeTotalsPerMember;

    struct StakingRewardsBalance {
        uint48 balance;
        uint48 lastRewardsPerToken;
    }
    mapping(address => StakingRewardsBalance) stakingRewardsBalances;

    struct CommitteeBalance {
        uint48 feeBalance;
        uint48 lastFeePerMember;
        uint48 bootstrapBalance;
        uint48 lastBootstrapPerMember;
    }
    mapping(address => CommitteeBalance) committeeBalances;

	uint32 constant PERCENT_MILLIE_BASE = 100000;

    uint256 lastAssignedAt;

    modifier onlyCommitteeContract() {
        require(msg.sender == address(committeeContract), "caller is not the committee contract");

        _;
    }

    uint constant TOKEN_BASE = 1e18;

    function calcStakingRewardPerTokenDelta(uint256 totalCommitteeStake, uint duration, Settings memory _settings) private view returns (uint256 stakingRewardsPerTokenDelta) {
        uint256 delta = 0;

        if (totalCommitteeStake > 0) { // TODO - handle the case of totalStake == 0. consider also an empty committee. consider returning a boolean saying if the amount was successfully distributed or not and handle on caller side.
            uint annualRateInPercentMille = Math.min(uint(_settings.annualRateInPercentMille), toUint256Granularity(_settings.annualCap).mul(PERCENT_MILLIE_BASE).div(totalCommitteeStake));
            delta = annualRateInPercentMille.mul(TOKEN_BASE).mul(duration).div(uint(PERCENT_MILLIE_BASE).mul(365 days));
        }

        totals.stakingRewardsPerToken;
    }

    function updateStakingRewardsTotals(uint256 totalCommitteeStake) private returns (StakingRewardsTotals memory totals){
        totals = stakingRewardsTotals;
        totals.stakingRewardsPerToken = totals.stakingRewardsPerToken.add(calcStakingRewardPerTokenDelta(totalCommitteeStake, block.timestamp - totals.lastAssigned, settings));
        totals.lastAssigned = block.timestamp;
        totals.totalCommitteeStake = totalCommitteeStake;

        stakingRewardsTotals = totals;
    }

    function updateMemberStakingRewards(address addr, bool inCommittee, uint256 stake, uint256 totalCommitteeStake) public onlyCommitteeContract {
        StakingRewardsTotals memory totals = updateStakingRewardsTotals(totalCommitteeStake);
        StakingRewardsBalance memory balance = stakingRewardsBalances[addr];

        if (inCommittee) {
            balance.balance = balance.balance.add(
                toUint48Granularity(
                    totals.stakingRewardsPerToken
                    .sub(balance.lastRewardsPerToken)
                    .mul(stake)
                    .div(TOKEN_BASE)
                )
            );
        }
        
        balance.lastRewardsPerToken = totals.stakingRewardsPerToken;
    }

    function updateCommitteeTotalsPerMember(uint generalCommitteeSize, uint certifiedCommitteeSize) private returns (CommitteeTotalsPerMember memory totals) {
        totals = committeeTotalsPerMember;

        totals.generalFees = totals.generalFees.add(generalFeesWallet.collectFees().div(generalCommitteeSize));
        totals.certifiedFees = totals.certifiedFees.add(certifiedFeesWallet.collectFees().div(certifiedCommitteeSize));

        uint duration = now.sub(lastAssignedAt);

        uint48 generalDelta = uint48(uint(_settings.generalCommitteeAnnualBootstrap).mul(duration).div(365 days));
        uint48 certifiedDelta = uint48(uint(_settings.certifiedCommitteeAnnualBootstrap).mul(duration).div(365 days));
        totals.generalBootstrap = totals.generalBootstrap.add(generalDelta);
        totals.certifiedBootstrap = totals.certifiedBootstrap.add(generalDelta).add(certifiedDelta);

        totals.lastAssigned = block.timestamp;
    }

    function updateMemberFeesAndBootstrap(address addr, bool inCommittee, bool isCertified, uint generalCommitteeSize, uint certifiedCommitteeSize) private {
        CommitteeTotalsPerMember memory totals = updateCommitteeTotalsPerMember(generalCommitteeSize, certifiedCommitteeSize);
        CommitteeBalance memory balance = committeeBalances[addr];

        if (balance.inCommittee) {
            uint96 totalBootstrap = balance.certified ? totals.certifiedBootstrap : totals.generalBootstrap;
            balance.bootstrapBalance = balance.bootstrapBalance.add(totalBootstrap.sub(balance.lastBootstrapPerMember));
            balance.lastBootstrapPerMember = isCertified ? totals.certifiedBootstrap : totals.generalBootstrap;

            uint96 totalFees = balance.certified ? totals.certifiedFees : totals.generalFees;
            balance.feeBalance = balance.bootstrapBalance.add(totalFees.sub(balance.lastFeesPerMember));
            balance.lastFeesPerMember = isCertified ? totals.certifiedFees : totals.generalFees;
        }

        balance.inCommittee = inCommittee;
        balance.certified = certified;
    }

    function updateMemberRewards(address addr, uint256 stake, uint256 totalCommitteeStake, bool inCommittee, bool isCertified, uint generalCommitteeSize, uint certifiedCommitteeSize) external onlyCommitteeContract {
        updateMemberFeesAndBootstrap(addr, inCommittee, isCertified, generalCommitteeSize, certifiedCommitteeSize);
        updateMemberStakingRewards(addr, inCommittee, stake, totalCommitteeStake);
    }

    constructor(
        IContractRegistry _contractRegistry,
        address _registryAdmin,
        IERC20 _erc20,
        IERC20 _bootstrapToken,
        uint generalCommitteeAnnualBootstrap,
        uint certifiedCommitteeAnnualBootstrap,
        uint annualRateInPercentMille,
        uint annualCap,
        uint32 maxDelegatorsStakingRewardsPercentMille
    ) ManagedContract(_contractRegistry, _registryAdmin) public {
        require(address(_bootstrapToken) != address(0), "bootstrapToken must not be 0");
        require(address(_erc20) != address(0), "erc20 must not be 0");

        setGeneralCommitteeAnnualBootstrap(generalCommitteeAnnualBootstrap);
        setCertifiedCommitteeAnnualBootstrap(certifiedCommitteeAnnualBootstrap);
        setAnnualStakingRewardsRate(annualRateInPercentMille, annualCap);
        setMaxDelegatorsStakingRewardsPercentMille(maxDelegatorsStakingRewardsPercentMille);

        erc20 = _erc20;
        bootstrapToken = _bootstrapToken;

        // TODO - The initial lastPayedAt should be set in the first assignRewards.
        lastAssignedAt = now;
    }

    // bootstrap rewards

    function setGeneralCommitteeAnnualBootstrap(uint256 annualAmount) public override onlyFunctionalManager onlyWhenActive {
        settings.generalCommitteeAnnualBootstrap = toUint48Granularity(annualAmount);
        emit GeneralCommitteeAnnualBootstrapChanged(annualAmount);
    }

    function setCertifiedCommitteeAnnualBootstrap(uint256 annualAmount) public override onlyFunctionalManager onlyWhenActive {
        settings.certifiedCommitteeAnnualBootstrap = toUint48Granularity(annualAmount);
        emit CertifiedCommitteeAnnualBootstrapChanged(annualAmount);
    }

    function setMaxDelegatorsStakingRewardsPercentMille(uint32 maxDelegatorsStakingRewardsPercentMille) public override onlyFunctionalManager onlyWhenActive {
        require(maxDelegatorsStakingRewardsPercentMille <= PERCENT_MILLIE_BASE, "maxDelegatorsStakingRewardsPercentMille must not be larger than 100000");
        settings.maxDelegatorsStakingRewardsPercentMille = maxDelegatorsStakingRewardsPercentMille;
        emit MaxDelegatorsStakingRewardsChanged(maxDelegatorsStakingRewardsPercentMille);
    }

    function getGeneralCommitteeAnnualBootstrap() external override view returns (uint256) {
        return toUint256Granularity(settings.generalCommitteeAnnualBootstrap);
    }

    function getCertifiedCommitteeAnnualBootstrap() external override view returns (uint256) {
        return toUint256Granularity(settings.certifiedCommitteeAnnualBootstrap);
    }

    function getMaxDelegatorsStakingRewardsPercentMille() public override view returns (uint32) {
        return settings.maxDelegatorsStakingRewardsPercentMille;
    }

    function getAnnualStakingRewardsRatePercentMille() external override view returns (uint32) {
        return settings.annualRateInPercentMille;
    }

    function getAnnualStakingRewardsCap() external override view returns (uint256) {
        return toUint256Granularity(settings.annualCap);
    }

    function getBootstrapBalance(address addr) external override view returns (uint256) {
        return toUint256Granularity(balances[addr].bootstrapRewards);
    }

    function assignRewards() public override onlyWhenActive {
        (address[] memory committee, uint256[] memory weights, bool[] memory certification) = committeeContract.getCommittee();
        _assignRewardsToCommittee(committee, weights, certification);
    }

    function assignRewardsToCommittee(address[] calldata committee, uint256[] calldata committeeWeights, bool[] calldata certification) external override onlyCommitteeContract onlyWhenActive {
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

            balance.bootstrapRewards = balance.bootstrapRewards.add(toUint48Granularity(certification[i] ? certifiedGuardianBootstrap : generalGuardianBootstrap));
            balance.fees = balance.fees.add(toUint48Granularity(certification[i] ? certifiedGuardianFee : generalGuardianFee));
            balance.stakingRewards = balance.stakingRewards.add(toUint48Granularity(stakingRewards[i]));

            totals.bootstrapRewardsTotalBalance = totals.bootstrapRewardsTotalBalance.add(toUint48Granularity(certification[i] ? certifiedGuardianBootstrap : generalGuardianBootstrap));
            totals.feesTotalBalance = totals.feesTotalBalance.add(toUint48Granularity(certification[i] ? certifiedGuardianFee : generalGuardianFee));
            totals.stakingRewardsTotalBalance = totals.stakingRewardsTotalBalance.add(toUint48Granularity(stakingRewards[i]));

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
        uint duration = now.sub(lastAssignedAt);
        generalGuardianBootstrap = toUint256Granularity(uint48(uint(_settings.generalCommitteeAnnualBootstrap).mul(duration).div(365 days)));
        certifiedGuardianBootstrap = generalGuardianBootstrap.add(toUint256Granularity(uint48(uint(_settings.certifiedCommitteeAnnualBootstrap).mul(duration).div(365 days))));
    }

    function withdrawBootstrapFunds(address guardian) external override {
        ICommittee _committee = committeeContract;
        (uint generalCommitteeSize, uint certifiedCommitteeSize, ) = _committee.getCommiteeStats();
        (bool inCommittee, , bool certified) = _committee.getMemberInfo(guardian);
        updateMemberFeesAndBootstrap(guardian, inCommittee, certified, generalCommitteeSize, certifiedCommitteeSize);

        uint48 amount = committeeBalances[guardian].    bootstrapBalance;
        committeeBalances[guardian].bootstrapBalance = 0;
        emit BootstrapRewardsWithdrawn(guardian, toUint256Granularity(amount));

        bootstrapRewardsWallet.withdrawMax(); // TODO use a better approach
        require(transfer(bootstrapToken, guardian, amount), "Rewards::withdrawBootstrapFunds - insufficient funds");
    }

    // staking rewards

    function setAnnualStakingRewardsRate(uint256 annualRateInPercentMille, uint256 annualCap) public override onlyFunctionalManager onlyWhenActive {
        Settings memory _settings = settings;
        _settings.annualRateInPercentMille = uint32(annualRateInPercentMille);
        _settings.annualCap = toUint48Granularity(annualCap);
        settings = _settings;

        emit AnnualStakingRewardsRateChanged(annualRateInPercentMille, annualCap);
    }

    function getStakingRewardBalance(address addr) external override view returns (uint256) {
        return toUint256Granularity(balances[addr].stakingRewards);
    }

    function getLastRewardAssignmentTime() external override view returns (uint256) {
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

            uint annualRateInPercentMille = Math.min(uint(_settings.annualRateInPercentMille), toUint256Granularity(_settings.annualCap).mul(PERCENT_MILLIE_BASE).div(totalWeight));
            uint48 curAmount;
            for (uint i = 0; i < committee.length; i++) {
                curAmount = toUint48Granularity(weights[i].mul(annualRateInPercentMille).mul(duration).div(uint(PERCENT_MILLIE_BASE).mul(365 days)));
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
    mapping (address => DistributorBatchState) public distributorBatchState;

    function isDelegatorRewardsBelowThreshold(uint256 delegatorRewards, uint256 totalRewards) private view returns (bool) {
        return delegatorRewards.mul(PERCENT_MILLIE_BASE) <= uint(settings.maxDelegatorsStakingRewardsPercentMille).mul(totalRewards.add(toUint256Granularity(1))); // +1 is added to account for rounding errors
    }

    struct distributeStakingRewardsVars {
        bool firstTxBySender;
        address guardianAddr;
        uint256 delegatorsAmount;
    }
    function distributeStakingRewards(uint256 totalAmount, uint256 fromBlock, uint256 toBlock, uint split, uint txIndex, address[] calldata to, uint256[] calldata amounts) external override onlyWhenActive {
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

        require(totalAmount_uint48 <= stakingRewardsBalances[vars.guardianAddr].balance, "not enough member balance for this distribution");

        stakingRewardsBalances[vars.guardianAddr].balance = uint48(stakingRewardsBalances[vars.guardianAddr].balance.sub(totalAmount_uint48));

        IStakingContract _stakingContract = stakingContract;

        stakingRewardsWallet.withdrawMax(); // TODO better approach

        approve(erc20, address(_stakingContract), totalAmount_uint48);
        _stakingContract.distributeRewards(totalAmount, to, amounts); // TODO should we rely on staking contract to verify total amount?

        delegationsContract.refreshStakeNotification(vars.guardianAddr);

        emit StakingRewardsDistributed(vars.guardianAddr, fromBlock, toBlock, split, txIndex, to, amounts);
    }

    function collectFees(address[] memory committee, bool[] memory certification) private returns (uint256 generalGuardianFee, uint256 certifiedGuardianFee) {
        uint generalFeePoolAmount = generalFeesWallet.collectFees();
        uint certificationFeePoolAmount = certifiedFeesWallet.collectFees();

        generalGuardianFee = divideFees(committee, certification, generalFeePoolAmount, false);
        certifiedGuardianFee = generalGuardianFee.add(divideFees(committee, certification, certificationFeePoolAmount, true));
    }

    function getFeeBalance(address addr) external override view returns (uint256) {
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

    function withdrawFees(address guardian) external override {
        ICommittee _committee = committeeContract;
        (uint generalCommitteeSize, uint certifiedCommitteeSize, ) = _committee.getCommiteeStats();
        (bool inCommittee, , bool certified) = _committee.getMemberInfo(guardian);
        updateMemberFeesAndBootstrap(guardian, inCommittee, certified, generalCommitteeSize, certifiedCommitteeSize);

        uint48 amount = committeeBalances[guardian].feeBalance;
        committeeBalances[guardian].feeBalance = 0;
        emit FeesWithdrawn(guardian, toUint256Granularity(amount));
        require(transfer(erc20, guardian, amount), "Rewards::claimExternalTokenRewards - insufficient funds");
    }

    function migrateStakingRewardsBalance(address guardian) external override {
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

    function acceptStakingRewardsMigration(address guardian, uint256 amount) external override {
        uint48 amount48 = toUint48Granularity(amount);
        require(transferFrom(erc20, msg.sender, address(this), amount48), "acceptStakingMigration: transfer failed");

        uint48 balance = balances[guardian].stakingRewards.add(amount48);
        balances[guardian].stakingRewards = balance;

        emit StakingRewardsMigrationAccepted(msg.sender, guardian, amount);
    }

    function emergencyWithdraw() external override onlyMigrationManager {
        emit EmergencyWithdrawal(msg.sender);
        require(erc20.transfer(msg.sender, erc20.balanceOf(address(this))), "Rewards::emergencyWithdraw - transfer failed (fee token)");
        require(bootstrapToken.transfer(msg.sender, bootstrapToken.balanceOf(address(this))), "Rewards::emergencyWithdraw - transfer failed (bootstrap token)");
    }

    function getSettings() external override view returns (
        uint generalCommitteeAnnualBootstrap,
        uint certifiedCommitteeAnnualBootstrap,
        uint annualStakingRewardsCap,
        uint32 annualStakingRewardsRatePercentMille,
        uint32 maxDelegatorsStakingRewardsPercentMille
    ) {
        Settings memory _settings = settings;
        generalCommitteeAnnualBootstrap = toUint256Granularity(_settings.generalCommitteeAnnualBootstrap);
        certifiedCommitteeAnnualBootstrap = toUint256Granularity(_settings.certifiedCommitteeAnnualBootstrap);
        annualStakingRewardsCap = toUint256Granularity(_settings.annualCap);
        annualStakingRewardsRatePercentMille = _settings.annualRateInPercentMille;
        maxDelegatorsStakingRewardsPercentMille = _settings.maxDelegatorsStakingRewardsPercentMille;
    }

    /*
     * Contracts topology / registry interface
     */

    ICommittee committeeContract;
    IDelegations delegationsContract;
    IGuardiansRegistration guardianRegistrationContract;
    IStakingContract stakingContract;
    IFeesWallet generalFeesWallet;
    IFeesWallet certifiedFeesWallet;
    IProtocolWallet stakingRewardsWallet;
    IProtocolWallet bootstrapRewardsWallet;
    function refreshContracts() external override {
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
