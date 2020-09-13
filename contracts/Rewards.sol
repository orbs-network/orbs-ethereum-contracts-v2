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

    struct StakingRewardsState {
        uint96 stakingRewardsPerWeight;
        uint32 lastAssigned;
    }

    StakingRewardsState stakingRewardsState;

    struct FeesAndBootstrapState {
        uint48 certifiedFeesPerMember;
        uint48 generalFeesPerMember;
        uint48 certifiedBootstrapPerMember;
        uint48 generalBootstrapPerMember;
        uint32 lastAssigned;
    }
    FeesAndBootstrapState feesAndBootstrapState;

    struct StakingRewards {
        uint96 delegatorRewardsPerToken;
        uint96 lastDelegatorRewardsPerToken;
        uint96 lastStakingRewardsPerWeight;
        uint48 balance;
    }
    mapping(address => StakingRewards) stakingRewards;

    struct FeesAndBootstrap {
        uint48 feeBalance;
        uint48 lastFeePerMember;
        uint48 bootstrapBalance;
        uint48 lastBootstrapPerMember;
    }
    mapping(address => FeesAndBootstrap) feesAndBootstrap;

	uint256 constant PERCENT_MILLIE_BASE = 100000;

    uint256 lastAssignedAt;

    modifier onlyElectionsContract() {
        require(msg.sender == address(electionsContract), "caller is not the elections contract");

        _;
    }

    uint constant TOKEN_BASE = 1e18;

    //
    // Staking rewards
    //


    function calcStakingRewardPerWeightDelta(uint256 totalCommitteeWeight, uint duration, Settings memory _settings) private pure returns (uint256 stakingRewardsPerTokenDelta) {
        stakingRewardsPerTokenDelta = 0;

        if (totalCommitteeWeight > 0) { // TODO - handle the case of totalStake == 0. consider also an empty committee. consider returning a boolean saying if the amount was successfully distributed or not and handle on caller side.
            uint annualRateInPercentMille = totalCommitteeWeight == 0 ? 0 : Math.min(uint(_settings.annualRateInPercentMille), toUint256Granularity(_settings.annualCap).mul(PERCENT_MILLIE_BASE).div(totalCommitteeWeight));
            stakingRewardsPerTokenDelta = annualRateInPercentMille.mul(TOKEN_BASE).mul(duration).div(PERCENT_MILLIE_BASE.mul(365 days));
        }
    }

    function getStakingRewardsState(uint256 totalCommitteeWeight, Settings memory _settings) private view returns (StakingRewardsState memory _stakingRewardsState) {
        _stakingRewardsState = stakingRewardsState;
        if (_settings.active) {
            uint delta = calcStakingRewardPerWeightDelta(totalCommitteeWeight, block.timestamp - stakingRewardsState.lastAssigned, _settings);
            _stakingRewardsState.stakingRewardsPerWeight = uint96(uint256(stakingRewardsState.stakingRewardsPerWeight).add(delta));
            _stakingRewardsState.lastAssigned = uint32(block.timestamp);
//            stakingRewardsState = _stakingRewardsState;
//
//            emit StakingRewardAllocated(delta.mul(totalCommitteeWeight).div(TOKEN_BASE), _stakingRewardsState.stakingRewardsPerWeight);
        }
    }

    // Internal interface: committee member change (joined, left) [], (changed weight - handled internally by _updateDelegatorStakingRewards)
    function _getGuardianStakingRewards(address guardian, bool inCommittee, uint256 guardianWeight, uint256 guardianDelegatedStake, uint256 totalCommitteeWeight) private view returns (StakingRewards memory guardianStakingRewards, StakingRewardsState memory _stakingRewardsState) {
        Settings memory _settings = settings; //TODO find the right place to read
        _stakingRewardsState = getStakingRewardsState(totalCommitteeWeight, _settings);
        guardianStakingRewards = stakingRewards[guardian];

        if (inCommittee) {
            uint256 guardianTotalReward = uint256(_stakingRewardsState.stakingRewardsPerWeight)
                .sub(uint256(guardianStakingRewards.lastStakingRewardsPerWeight))
                .mul(guardianWeight);

            uint256 delegatorRewardsPerTokenDelta = guardianDelegatedStake == 0 ? 0 : guardianTotalReward
                .div(guardianDelegatedStake)
                .mul(uint256(_settings.delegatorsStakingRewardsPercentMille))
                .div(PERCENT_MILLIE_BASE);

            uint256 guardianCutPercentMille = PERCENT_MILLIE_BASE.sub(_settings.delegatorsStakingRewardsPercentMille);

            uint256 amount = guardianTotalReward
                .mul(guardianCutPercentMille)
                .div(PERCENT_MILLIE_BASE)
                .div(TOKEN_BASE);

            guardianStakingRewards.delegatorRewardsPerToken = uint96(guardianStakingRewards.delegatorRewardsPerToken.add(delegatorRewardsPerTokenDelta));
            guardianStakingRewards.balance = guardianStakingRewards.balance.add(toUint48Granularity(amount));

//            emit GuardianStakingRewardsAssigned(guardian, amount, guardianStakingRewards.delegatorRewardsPerToken);
        }

        guardianStakingRewards.lastStakingRewardsPerWeight = _stakingRewardsState.stakingRewardsPerWeight;
//        stakingRewards[guardian] = guardianStakingRewards;
    }

    // Internal interface: delegator actions (staking, delegation) [Called by Elections on delegations notification]
    function _getDelegatorStakingRewards(address delegator, uint256 delegatorStake, address guardian, bool inCommittee, uint256 guardianWeight, uint256 guardianDelegatedStake, uint256 totalCommitteeWeight) private view returns (StakingRewards memory delegatorStakingRewards, StakingRewards memory guardianStakingRewards, StakingRewardsState memory _stakingRewardsState){
        (guardianStakingRewards, _stakingRewardsState) = _getGuardianStakingRewards(guardian, inCommittee, guardianWeight, guardianDelegatedStake, totalCommitteeWeight);
        delegatorStakingRewards = delegator == guardian ? guardianStakingRewards : stakingRewards[delegator];

        uint256 amount = uint256(guardianStakingRewards.delegatorRewardsPerToken)
            .sub(uint256(delegatorStakingRewards.lastDelegatorRewardsPerToken))
            .mul(delegatorStake)
            .div(TOKEN_BASE);

        delegatorStakingRewards.balance = delegatorStakingRewards.balance.add(toUint48Granularity(amount));
        delegatorStakingRewards.lastDelegatorRewardsPerToken = guardianStakingRewards.delegatorRewardsPerToken;

//        stakingRewards[delegator] = delegatorRewards;

//        emit StakingRewardsAssigned(delegator, amount);
    }

    function    getDelegatorStakingRewards(address delegator) private view returns (StakingRewards memory delegatorStakingRewards, address guardian, StakingRewards memory guardianStakingRewards, StakingRewardsState memory _stakingRewardsState) {
        ICommittee _committeeContract = committeeContract;
        IDelegations _delegationsContract = delegationsContract;
        uint256 delegatorStake = stakingContract.getStakeBalanceOf(delegator);
        guardian = _delegationsContract.getDelegation(delegator);
        uint256 delegatedStake = _delegationsContract.getDelegatedStakes(guardian);

        (, , uint totalCommitteeStake) = _committeeContract.getCommitteeStats();
        (bool inCommittee, uint guardianWeight,) = _committeeContract.getMemberInfo(guardian);
        (delegatorStakingRewards, guardianStakingRewards, _stakingRewardsState) = _getDelegatorStakingRewards(delegator, delegatorStake, guardian, inCommittee, guardianWeight, delegatedStake, totalCommitteeStake);
    }

    function updateDelegatorStakingRewards(address delegator) private {
        address guardian;
        StakingRewards memory guardianRewards;
        (stakingRewards[delegator], guardian, guardianRewards, stakingRewardsState) = getDelegatorStakingRewards(delegator);
        if (guardian != delegator) stakingRewards[guardian] = guardianRewards;
    }

    //
    // Bootstrap and fees
    //

    function getFeesAndBootstrapState(uint generalCommitteeSize, uint certifiedCommitteeSize) private view returns (FeesAndBootstrapState memory _feesAndBootstrapState) {
        Settings memory _settings = settings;

        _feesAndBootstrapState = feesAndBootstrapState;

        if (_settings.active) {
            _feesAndBootstrapState.generalFeesPerMember = _feesAndBootstrapState.generalFeesPerMember.add(generalCommitteeSize == 0 ? 0 : toUint48Granularity(generalFeesWallet.getOutstandingFees().div(generalCommitteeSize)));
            _feesAndBootstrapState.certifiedFeesPerMember = _feesAndBootstrapState.certifiedFeesPerMember.add(certifiedCommitteeSize == 0 ? 0 : toUint48Granularity(certifiedFeesWallet.getOutstandingFees().div(certifiedCommitteeSize)));

            uint duration = now.sub(lastAssignedAt);

            uint48 generalDelta = uint48(uint(_settings.generalCommitteeAnnualBootstrap).mul(duration).div(365 days));
            uint48 certifiedDelta = uint48(uint(_settings.certifiedCommitteeAnnualBootstrap).mul(duration).div(365 days));
            _feesAndBootstrapState.generalBootstrapPerMember = _feesAndBootstrapState.generalBootstrapPerMember.add(generalDelta);
            _feesAndBootstrapState.certifiedBootstrapPerMember = _feesAndBootstrapState.certifiedBootstrapPerMember.add(generalDelta).add(certifiedDelta);
            _feesAndBootstrapState.lastAssigned = uint32(block.timestamp);

//            feesAndBootstrapState = _feesAndBootstrapState;
        }
    }

    // Internal interface: committee membership changed (joined, left)
    function _getGuardianFeesAndBootstrap(address guardian, bool inCommittee, bool isCertified, uint generalCommitteeSize, uint certifiedCommitteeSize) private view returns (FeesAndBootstrap memory guardianFeesAndBootstrap, FeesAndBootstrapState memory _feesAndBootstrapState){
        _feesAndBootstrapState = getFeesAndBootstrapState(generalCommitteeSize, certifiedCommitteeSize);
        guardianFeesAndBootstrap = feesAndBootstrap[guardian];

        if (inCommittee) {
            uint256 totalBootstrap = isCertified ? _feesAndBootstrapState.certifiedBootstrapPerMember : _feesAndBootstrapState.generalBootstrapPerMember;
            uint256 bootstrapAmount = totalBootstrap.sub(guardianFeesAndBootstrap.lastBootstrapPerMember);
            guardianFeesAndBootstrap.bootstrapBalance = guardianFeesAndBootstrap.bootstrapBalance.add(toUint48Granularity(bootstrapAmount));
//            emit BootstrapRewardsAssigned(guardian, bootstrapAmount);
            
            uint256 totalFees = isCertified ? _feesAndBootstrapState.certifiedFeesPerMember : _feesAndBootstrapState.generalFeesPerMember;
            uint256 feesAmount = totalFees.sub(guardianFeesAndBootstrap.lastFeePerMember);
            guardianFeesAndBootstrap.feeBalance = guardianFeesAndBootstrap.bootstrapBalance.add(toUint48Granularity(feesAmount));
//            emit FeesAssigned(guardian, feesAmount);
        }
        
        guardianFeesAndBootstrap.lastBootstrapPerMember = isCertified ? _feesAndBootstrapState.certifiedBootstrapPerMember : _feesAndBootstrapState.generalBootstrapPerMember;
        guardianFeesAndBootstrap.lastFeePerMember = isCertified ? _feesAndBootstrapState.certifiedFeesPerMember : _feesAndBootstrapState.generalFeesPerMember;
    }

    function getGuardianFeesAndBootstrap(address guardian) private view returns (FeesAndBootstrap memory guardianFeesAndBootstrap, FeesAndBootstrapState memory _feesAndBootstrapState) {
        ICommittee _committeeContract = committeeContract;
        (uint generalCommitteeSize, uint certifiedCommitteeSize, ) = _committeeContract.getCommitteeStats();
        (bool inCommittee, , bool certified) = _committeeContract.getMemberInfo(guardian);
        (guardianFeesAndBootstrap, _feesAndBootstrapState) = _getGuardianFeesAndBootstrap(guardian, inCommittee, certified, generalCommitteeSize, certifiedCommitteeSize);
    }

    function updateGuardianFeesAndBootstrap(address guardian) private {
        (feesAndBootstrap[guardian], feesAndBootstrapState) = getGuardianFeesAndBootstrap(guardian);
        generalFeesWallet.collectFees();
        certifiedFeesWallet.collectFees();
    }

    //
    // External push notifications
    //

    function committeeMembershipWillChange(address guardian, uint256 weight, uint256 delegatedStake, uint256 totalCommitteeWeight, bool inCommittee, bool isCertified, uint generalCommitteeSize, uint certifiedCommitteeSize) external override onlyElectionsContract {
        (feesAndBootstrap[guardian], feesAndBootstrapState) = _getGuardianFeesAndBootstrap(guardian, inCommittee, isCertified, generalCommitteeSize, certifiedCommitteeSize);
        (stakingRewards[guardian], stakingRewardsState) = _getGuardianStakingRewards(guardian, inCommittee, weight, delegatedStake, totalCommitteeWeight);
    }

    function delegatorWillChange(address guardian, uint256 weight, uint256 delegatedStake, bool inCommittee, uint256 totalCommitteeWeight, address delegator, uint256 delegatorStake) external override onlyElectionsContract {
        (stakingRewards[delegator], stakingRewards[guardian], stakingRewardsState) = _getDelegatorStakingRewards(delegator, delegatorStake, guardian, inCommittee, weight, delegatedStake, totalCommitteeWeight);
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
        uint32 delegatorsStakingRewardsPercentMille
    ) ManagedContract(_contractRegistry, _registryAdmin) public {
        require(address(_bootstrapToken) != address(0), "bootstrapToken must not be 0");
        require(address(_erc20) != address(0), "erc20 must not be 0");

        setGeneralCommitteeAnnualBootstrap(generalCommitteeAnnualBootstrap);
        setCertifiedCommitteeAnnualBootstrap(certifiedCommitteeAnnualBootstrap);
        setAnnualStakingRewardsRate(annualRateInPercentMille, annualCap);
        setDelegatorsStakingRewardsPercentMille(delegatorsStakingRewardsPercentMille);

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

    function setDelegatorsStakingRewardsPercentMille(uint32 delegatorsStakingRewardsPercentMille) public override onlyFunctionalManager onlyWhenActive {
        require(delegatorsStakingRewardsPercentMille <= PERCENT_MILLIE_BASE, "delegatorsStakingRewardsPercentMille must not be larger than 100000");
        settings.delegatorsStakingRewardsPercentMille = delegatorsStakingRewardsPercentMille;
        emit MaxDelegatorsStakingRewardsChanged(delegatorsStakingRewardsPercentMille);
    }

    function getGeneralCommitteeAnnualBootstrap() external override view returns (uint256) {
        return toUint256Granularity(settings.generalCommitteeAnnualBootstrap);
    }

    function getCertifiedCommitteeAnnualBootstrap() external override view returns (uint256) {
        return toUint256Granularity(settings.certifiedCommitteeAnnualBootstrap);
    }

    function getMaxDelegatorsStakingRewardsPercentMille() public override view returns (uint32) {
        return settings.delegatorsStakingRewardsPercentMille;
    }

    function getAnnualStakingRewardsRatePercentMille() external override view returns (uint32) {
        return settings.annualRateInPercentMille;
    }

    function getAnnualStakingRewardsCap() external override view returns (uint256) {
        return toUint256Granularity(settings.annualCap);
    }

    function getBootstrapBalance(address addr) external override view returns (uint256) {
        (FeesAndBootstrap memory guardianFeesAndBootstrap,) = getGuardianFeesAndBootstrap(addr);
        return toUint256Granularity(guardianFeesAndBootstrap.bootstrapBalance);
    }

    function withdrawBootstrapFunds(address guardian) external override {
        updateGuardianFeesAndBootstrap(guardian);
        uint48 amount = feesAndBootstrap[guardian].bootstrapBalance;
        feesAndBootstrap[guardian].bootstrapBalance = 0;
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

    function getStakingRewardsBalance(address addr) external override view returns (uint256) {
        (StakingRewards memory delegatorStakingRewards,,,) = getDelegatorStakingRewards(addr);
        return toUint256Granularity(delegatorStakingRewards.balance);
    }

    struct DistributorBatchState {
        uint256 fromBlock;
        uint256 toBlock;
        uint256 nextTxIndex;
        uint split;
    }
    mapping (address => DistributorBatchState) public distributorBatchState;

    function isDelegatorRewardsBelowThreshold(uint256 delegatorRewards, uint256 totalRewards) private view returns (bool) {
        return delegatorRewards.mul(PERCENT_MILLIE_BASE) <= uint(settings.delegatorsStakingRewardsPercentMille).mul(totalRewards.add(toUint256Granularity(1))); // +1 is added to account for rounding errors
    }

    function getFeeBalance(address addr) external override view returns (uint256) {
        (FeesAndBootstrap memory guardianFeesAndBootstrap,) = getGuardianFeesAndBootstrap(addr);
        return toUint256Granularity(guardianFeesAndBootstrap.feeBalance);
    }

    function withdrawFees(address guardian) external override {
        ICommittee _committeeContract = committeeContract;
        (uint generalCommitteeSize, uint certifiedCommitteeSize, ) = _committeeContract.getCommitteeStats();
        (bool inCommittee, , bool certified) = _committeeContract.getMemberInfo(guardian);
        _getGuardianFeesAndBootstrap(guardian, inCommittee, certified, generalCommitteeSize, certifiedCommitteeSize);

        uint48 amount = feesAndBootstrap[guardian].feeBalance;
        feesAndBootstrap[guardian].feeBalance = 0;
        emit FeesWithdrawn(guardian, toUint256Granularity(amount));
        require(transfer(erc20, guardian, amount), "Rewards::claimExternalTokenRewards - insufficient funds");
    }

    function migrateStakingRewardsBalance(address guardian) external override {
        require(!settings.active, "Reward distribution must be deactivated for migration");

        IRewards currentRewardsContract = IRewards(getRewardsContract());
        require(address(currentRewardsContract) != address(this), "New rewards contract is not set");

        updateDelegatorStakingRewards(guardian);

        uint48 balance = stakingRewards[guardian].balance;
        stakingRewards[guardian].balance = 0;

        require(approve(erc20, address(currentRewardsContract), balance), "migrateStakingBalance: approve failed");
        currentRewardsContract.acceptStakingRewardsMigration(guardian, toUint256Granularity(balance));

        emit StakingRewardsBalanceMigrated(guardian, toUint256Granularity(balance), address(currentRewardsContract));
    }

    function acceptStakingRewardsMigration(address guardian, uint256 amount) external override {
        uint48 amount48 = toUint48Granularity(amount);
        require(transferFrom(erc20, msg.sender, address(this), amount48), "acceptStakingMigration: transfer failed");

        uint48 balance = stakingRewards[guardian].balance.add(amount48);
        stakingRewards[guardian].balance = balance;

        emit StakingRewardsMigrationAccepted(msg.sender, guardian, amount);
    }

    function emergencyWithdraw() external override onlyMigrationManager {
        emit EmergencyWithdrawal(msg.sender);
        require(erc20.transfer(msg.sender, erc20.balanceOf(address(this))), "Rewards::emergencyWithdraw - transfer failed (fee token)");
        require(bootstrapToken.transfer(msg.sender, bootstrapToken.balanceOf(address(this))), "Rewards::emergencyWithdraw - transfer failed (bootstrap token)");
    }

    function activate(uint startTime) external override onlyMigrationManager {
        feesAndBootstrapState.lastAssigned = uint32(startTime);
        stakingRewardsState.lastAssigned = uint32(startTime);
        settings.active = true;

        emit RewardDistributionActivated(startTime);
    }

    function deactivate() external override onlyMigrationManager {
        (uint generalCommitteeSize, uint certifiedCommitteeSize, uint totalStake) = committeeContract.getCommitteeStats();
        stakingRewardsState = getStakingRewardsState(totalStake, settings);
        feesAndBootstrapState = getFeesAndBootstrapState(generalCommitteeSize, certifiedCommitteeSize);

        settings.active = false;

        emit RewardDistributionDeactivated();
    }

    function getSettings() external override view returns (
        uint generalCommitteeAnnualBootstrap,
        uint certifiedCommitteeAnnualBootstrap,
        uint annualStakingRewardsCap,
        uint32 annualStakingRewardsRatePercentMille,
        uint32 delegatorsStakingRewardsPercentMille,
        bool active
    ) {
        Settings memory _settings = settings;
        generalCommitteeAnnualBootstrap = toUint256Granularity(_settings.generalCommitteeAnnualBootstrap);
        certifiedCommitteeAnnualBootstrap = toUint256Granularity(_settings.certifiedCommitteeAnnualBootstrap);
        annualStakingRewardsCap = toUint256Granularity(_settings.annualCap);
        annualStakingRewardsRatePercentMille = _settings.annualRateInPercentMille;
        delegatorsStakingRewardsPercentMille = _settings.delegatorsStakingRewardsPercentMille;
        active = _settings.active;
    }

    /*
     * Contracts topology / registry interface
     */

    IElections electionsContract;
    ICommittee committeeContract;
    IDelegations delegationsContract;
    IGuardiansRegistration guardianRegistrationContract;
    IStakingContract stakingContract;
    IFeesWallet generalFeesWallet;
    IFeesWallet certifiedFeesWallet;
    IProtocolWallet stakingRewardsWallet;
    IProtocolWallet bootstrapRewardsWallet;
    function refreshContracts() external override {
        electionsContract = IElections(getElectionsContract());
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
