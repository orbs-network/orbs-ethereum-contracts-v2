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
    using SafeMath for uint96;
    using SafeMath48 for uint48;

    struct Settings {
        uint48 generalCommitteeAnnualBootstrap;
        uint48 certifiedCommitteeAnnualBootstrap;
        uint48 annualCap;
        uint32 annualRateInPercentMille;
        uint32 delegatorsStakingRewardsPercentMille;
        bool active;
    }
    Settings settings;

    IERC20 bootstrapToken;
    IERC20 erc20;

    event stakingRewardAllocated(uint256 amount, uint256 stakingRewardsPerWeight);
    event guardianStakingRewardAssigned(address indexed guardian, uint256 amount, uint256 delegatorRewardsPerToken);
    event delegatorStakingRewardAssigned(address indexed delegator, uint256 amount);

    struct GlobalStakingRewards {
        uint96 stakingRewardsPerWeight;
        uint32 lastAssigned;
    }

    GlobalStakingRewards globalStakingRewards;

    struct GuardianStakingRewards {
        uint96 delegatorRewardsPerToken;
        uint48 balance;
        uint96 lastStakingRewardsPerWeight;
    }

    mapping(address => GuardianStakingRewards) guardianStakingRewards;

    struct DelegatorStakingRewards {
        uint48 balance;
        uint96 lastDelegatorRewardsPerToken;
    }

    mapping(address => DelegatorStakingRewards) delegatorStakingRewards;

    struct CommitteeTotalsPerMember {
        uint48 certifiedFees;
        uint48 generalFees;
        uint48 certifiedBootstrap;
        uint48 generalBootstrap;
        uint32 lastAssigned;
    }
    CommitteeTotalsPerMember committeeTotalsPerMember;

    struct CommitteeBalance {
        uint48 feeBalance;
        uint48 lastFeePerMember;
        uint48 bootstrapBalance;
        uint48 lastBootstrapPerMember;
    }
    mapping(address => CommitteeBalance) committeeBalances;

	uint32 constant PERCENT_MILLIE_BASE = 100000;
    uint256 constant TOKEN_BASE = 1e18;

    uint256 lastAssignedAt;

    modifier onlyCommitteeContract() {
        require(msg.sender == address(committeeContract), "caller is not the committee contract");

        _;
    }

    function _calcStakingRewardPerWeightDelta(uint256 totalCommitteeWeight, uint duration, Settings memory _settings) private pure returns (uint256 stakingRewardsPerWeightDelta) {
        stakingRewardsPerWeightDelta = 0;

        if (totalCommitteeWeight > 0) { // TODO - handle the case of totalStake == 0. consider also an empty committee. consider returning a boolean saying if the amount was successfully distributed or not and handle on caller side.
            uint annualRateInPercentMille = Math.min(uint(_settings.annualRateInPercentMille), toUint256Granularity(_settings.annualCap).mul(PERCENT_MILLIE_BASE).div(totalCommitteeWeight));
            stakingRewardsPerWeightDelta = annualRateInPercentMille.mul(TOKEN_BASE).mul(duration).div(uint(PERCENT_MILLIE_BASE).mul(365 days));
        }
    }

    function _updateGlobalStakingRewards(uint256 totalCommitteeWeight, Settings memory _settings) private returns (GlobalStakingRewards memory globalReward){
        globalReward = globalStakingRewards;
        if (settings.active) {
            uint256 stakingRewardsPerWeightDelta = _calcStakingRewardPerWeightDelta(totalCommitteeWeight, block.timestamp - globalReward.lastAssigned, _settings);
            globalReward.stakingRewardsPerWeight = uint96(uint256(globalReward.stakingRewardsPerWeight).add(stakingRewardsPerWeightDelta));
            globalReward.lastAssigned = uint32(block.timestamp);
            globalStakingRewards = globalReward;
            uint256 amount = stakingRewardsPerWeightDelta.mul(totalCommitteeWeight);
            emit stakingRewardAllocated(amount, stakingRewardsPerWeightDelta);
        }
    }

    function _updateGuardianStakingRewards(address guardian, bool inCommittee, uint256 guardianWeight, uint256 guardianDelegatedStake, uint256 totalCommitteeWeight) private returns (GuardianStakingRewards memory guardianReward) {
        Settings memory _settings = settings; //TODO find the right place to read
        GlobalStakingRewards memory globalReward = _updateGlobalStakingRewards(totalCommitteeWeight, _settings);
        guardianReward = guardianStakingRewards[guardian];

        if (inCommittee) {
            uint256 guardianTotalReward = uint256(globalReward.stakingRewardsPerWeight)
                .sub(uint256(guardianReward.lastStakingRewardsPerWeight))
                .mul(guardianWeight);
        
            uint256 delegatorRewardsPerTokenDelta = guardianTotalReward
                .div(guardianDelegatedStake)
                .mul(uint256(_settings.delegatorsStakingRewardsPercentMille))
                .div(uint256(PERCENT_MILLIE_BASE));

            uint256 guardianCutPercentMille = uint256(PERCENT_MILLIE_BASE
                .sub(_settings.delegatorsStakingRewardsPercentMille));

            uint256 amount = guardianTotalReward
                .mul(guardianCutPercentMille)
                .div(uint256(PERCENT_MILLIE_BASE))
                .div(TOKEN_BASE);

            guardianReward.delegatorRewardsPerToken = guardianReward.delegatorRewardsPerToken
                .add(uint96(delegatorRewardsPerTokenDelta));

            guardianReward.balance = guardianReward.balance.add(toUint48Granularity(amount));
            
            emit guardianStakingRewardAssigned(guardian, amount, guardianReward.delegatorRewardsPerToken);
        }
        
        guardianReward.lastStakingRewardsPerWeight = globalReward.stakingRewardsPerWeight;
        guardianStakingRewards[guardian] = guardianReward;
    }

    function _updateDelegatorStakingRewards(address delegator, uint256 delegatorStake, address guardian, bool inCommittee, uint256 guardianWeight, uint256 guardianDelegatedStake, uint256 totalCommitteeWeight) private returns (DelegatorStakingRewards memory delegatorReward) {
        GuardianStakingRewards memory guardianReward = _updateGuardianStakingRewards(guardian, inCommittee, guardianWeight, guardianDelegatedStake, totalCommitteeWeight);
        delegatorReward = delegatorStakingRewards[delegator];

        uint256 amount = guardianReward.delegatorRewardsPerToken
            .sub(delegatorReward.lastDelegatorRewardsPerToken)
            .mul(delegatorStake)
            .div(TOKEN_BASE);
        
        delegatorReward.balance = delegatorReward.balance.add(toUint48Granularity(amount));
        delegatorReward.lastDelegatorRewardsPerToken = guardianReward.delegatorRewardsPerToken;
        
        if (amount > 0) {
            emit delegatorStakingRewardAssigned(delegator, amount);
        }
    }

    /* 
     * External
     */

    function delegatorStakeWillChange(address delegator, uint256 delegatorStake, address guardian, bool inCommittee, uint256 guardianWeight, uint256 guardianDelegatedStake, uint256 totalCommitteeWeight) external onlyCommitteeContract {
        _updateDelegatorStakingRewards(delegator, delegatorStake, guardian, inCommittee, guardianWeight, guardianDelegatedStake, totalCommitteeWeight);
    }

    function updateDelegatorStakingRewards(address delegator) private { //TODO public
        ICommittee _committee = committeeContract;
        uint256 delegatorStake = stakingContract.getStakeBalanceOf(delegator);
        (address guardian, uint256 guardianDelegatedStake, ) = delegationsContract.getDelegationInfo(delegator);
        (, , uint256 totalCommitteeWeight) = _committee.getCommitteeStats();
        (bool inCommittee, uint guardianWeight,) = _committee.getMemberInfo(guardian); //TODO unify
        _updateDelegatorStakingRewards(delegator, delegatorStake, guardian, inCommittee, guardianWeight, guardianDelegatedStake, totalCommitteeWeight);
    }

    function updateGuardianStakingRewards(address guardian) private { //TODO public
        ICommittee _committee = committeeContract;
        uint256 guardianDelegatedStake = delegationsContract.getDelegatedStakes(guardian);
        (, , uint256 totalCommitteeWeight) = _committee.getCommitteeStats();
        (bool inCommittee, uint guardianWeight,) = _committee.getMemberInfo(guardian); //TODO unify
        _updateGuardianStakingRewards(guardian, inCommittee, guardianWeight, guardianDelegatedStake, totalCommitteeWeight);
    }

    function updateGlobalStakingRewards() private { //TODO public
        (, , uint256 totalCommitteeWeight) = committeeContract.getCommitteeStats();
         _updateGlobalStakingRewards(totalCommitteeWeight, settings);
    }

    /*
    ******************************************************************************
    */


    function updateCommitteeTotalsPerMember(uint generalCommitteeSize, uint certifiedCommitteeSize) private returns (CommitteeTotalsPerMember memory totals) {
        Settings memory _settings = settings;

        totals = committeeTotalsPerMember;

        if (_settings.active) {
            totals.generalFees = totals.generalFees.add(toUint48Granularity(generalFeesWallet.collectFees().div(generalCommitteeSize)));
            totals.certifiedFees = totals.certifiedFees.add(toUint48Granularity(certifiedFeesWallet.collectFees().div(certifiedCommitteeSize)));

            uint duration = now.sub(lastAssignedAt);

            uint48 generalDelta = uint48(uint(_settings.generalCommitteeAnnualBootstrap).mul(duration).div(365 days));
            uint48 certifiedDelta = uint48(uint(_settings.certifiedCommitteeAnnualBootstrap).mul(duration).div(365 days));
            totals.generalBootstrap = totals.generalBootstrap.add(generalDelta);
            totals.certifiedBootstrap = totals.certifiedBootstrap.add(generalDelta).add(certifiedDelta);
            totals.lastAssigned = uint32(block.timestamp);

            committeeTotalsPerMember = totals;
        }
    }

    function _updateGuardianFeesAndBootstrap(address addr, bool inCommittee, bool isCertified, uint generalCommitteeSize, uint certifiedCommitteeSize) private {
        CommitteeTotalsPerMember memory totals = updateCommitteeTotalsPerMember(generalCommitteeSize, certifiedCommitteeSize);
        CommitteeBalance memory balance = committeeBalances[addr];

        if (inCommittee) {
            uint256 totalBootstrap = isCertified ? totals.certifiedBootstrap : totals.generalBootstrap;
            uint256 bootstrapAmount = totalBootstrap.sub(balance.lastBootstrapPerMember);
            balance.bootstrapBalance = balance.bootstrapBalance.add(toUint48Granularity(bootstrapAmount));
            emit BootstrapRewardsAssigned(addr, bootstrapAmount);
            
            uint256 totalFees = isCertified ? totals.certifiedFees : totals.generalFees;
            uint256 feesAmount = totalFees.sub(balance.lastFeePerMember);
            balance.feeBalance = balance.bootstrapBalance.add(toUint48Granularity(feesAmount));
            emit FeesAssigned(addr, feesAmount);
        }
        
        balance.lastBootstrapPerMember = isCertified ? totals.certifiedBootstrap : totals.generalBootstrap;
        balance.lastFeePerMember = isCertified ? totals.certifiedFees : totals.generalFees;
    }

    function updateMemberFeesAndBootstrap(address guardian) private {
        ICommittee _committee = committeeContract;
        (uint generalCommitteeSize, uint certifiedCommitteeSize, ) = _committee.getCommitteeStats();
        (bool inCommittee, , bool certified) = _committee.getMemberInfo(guardian);
        _updateGuardianFeesAndBootstrap(guardian, inCommittee, certified, generalCommitteeSize, certifiedCommitteeSize);
    }

    // TODO - is it needed
    // function committeeMembershipWillChange(address guardian, uint256 stake, uint256 uncappedStake, uint256 totalCommitteeWeight, bool inCommittee, bool isCertified, uint generalCommitteeSize, uint certifiedCommitteeSize) external override onlyCommitteeContract {
    //     _updateGuardianFeesAndBootstrap(guardian, inCommittee, isCertified, generalCommitteeSize, certifiedCommitteeSize);
    //     stakingRewardsBalances[guardian] = _updateDelegatorStakingRewardsPerToken(guardian, inCommittee, stake, uncappedStake, totalCommitteeWeight);
    // }

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
        return toUint256Granularity(committeeBalances[addr].bootstrapBalance);
    }

    function withdrawBootstrapFunds(address guardian) external override {
        updateMemberFeesAndBootstrap(guardian);
        uint48 amount = committeeBalances[guardian].bootstrapBalance;
        committeeBalances[guardian].bootstrapBalance = 0;
        emit BootstrapRewardsWithdrawn(guardian, toUint256Granularity(amount));

        bootstrapRewardsWallet.withdraw(amount);
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
        return toUint256Granularity(delegatorStakingRewards[addr].balance);
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

    function getFeeBalance(address addr) external override view returns (uint256) {
        return toUint256Granularity(committeeBalances[addr].feeBalance);
    }

    function withdrawFees(address guardian) external override {
        ICommittee _committee = committeeContract;
        (uint generalCommitteeSize, uint certifiedCommitteeSize, ) = _committee.getCommitteeStats();
        (bool inCommittee, , bool certified) = _committee.getMemberInfo(guardian);
        _updateGuardianFeesAndBootstrap(guardian, inCommittee, certified, generalCommitteeSize, certifiedCommitteeSize);

        uint48 amount = committeeBalances[guardian].feeBalance;
        committeeBalances[guardian].feeBalance = 0;
        emit FeesWithdrawn(guardian, toUint256Granularity(amount));
        require(transfer(erc20, guardian, amount), "Rewards::claimExternalTokenRewards - insufficient funds");
    }

    function migrateStakingRewardsBalance(address guardian) external override {
        require(!settings.active, "Reward distribution must be deactivated for migration");

        IRewards currentRewardsContract = IRewards(getRewardsContract());
        require(address(currentRewardsContract) != address(this), "New rewards contract is not set");

        updateDelegatorStakingRewards(guardian);

        uint48 balance = stakingRewardsBalances[guardian].balance;
        stakingRewardsBalances[guardian].balance = 0;

        require(approve(erc20, address(currentRewardsContract), balance), "migrateStakingBalance: approve failed");
        currentRewardsContract.acceptStakingRewardsMigration(guardian, toUint256Granularity(balance));

        emit StakingRewardsBalanceMigrated(guardian, toUint256Granularity(balance), address(currentRewardsContract));
    }

    function acceptStakingRewardsMigration(address guardian, uint256 amount) external override {
        uint48 amount48 = toUint48Granularity(amount);
        require(transferFrom(erc20, msg.sender, address(this), amount48), "acceptStakingMigration: transfer failed");

        uint48 balance = stakingRewardsBalances[guardian].balance.add(amount48);
        stakingRewardsBalances[guardian].balance = balance;

        emit StakingRewardsMigrationAccepted(msg.sender, guardian, amount);
    }

    function emergencyWithdraw() external override onlyMigrationManager {
        emit EmergencyWithdrawal(msg.sender);
        require(erc20.transfer(msg.sender, erc20.balanceOf(address(this))), "Rewards::emergencyWithdraw - transfer failed (fee token)");
        require(bootstrapToken.transfer(msg.sender, bootstrapToken.balanceOf(address(this))), "Rewards::emergencyWithdraw - transfer failed (bootstrap token)");
    }

    function activate(uint startTime) external override onlyMigrationManager {
        committeeTotalsPerMember.lastAssigned = uint32(startTime);
        stakingRewardsTotals.lastAssigned = uint32(startTime);
        settings.active = true;

        emit RewardDistributionActivated(startTime);
    }

    function deactivate() external override onlyMigrationManager {
        (uint generalCommitteeSize, uint certifiedCommitteeSize, uint totalStake) = committeeContract.getCommitteeStats();
        updateStakingRewardsTotals(totalStake);
        updateCommitteeTotalsPerMember(generalCommitteeSize, certifiedCommitteeSize);

        settings.active = false;

        emit RewardDistributionDeactivated();
    }

    function getSettings() external override view returns (
        uint generalCommitteeAnnualBootstrap,
        uint certifiedCommitteeAnnualBootstrap,
        uint annualStakingRewardsCap,
        uint32 annualStakingRewardsRatePercentMille,
        uint32 maxDelegatorsStakingRewardsPercentMille,
        bool active
    ) {
        Settings memory _settings = settings;
        generalCommitteeAnnualBootstrap = toUint256Granularity(_settings.generalCommitteeAnnualBootstrap);
        certifiedCommitteeAnnualBootstrap = toUint256Granularity(_settings.certifiedCommitteeAnnualBootstrap);
        annualStakingRewardsCap = toUint256Granularity(_settings.annualCap);
        annualStakingRewardsRatePercentMille = _settings.annualRateInPercentMille;
        maxDelegatorsStakingRewardsPercentMille = _settings.maxDelegatorsStakingRewardsPercentMille;
        active = _settings.active;
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
