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

//    struct StakingRewards {
//        uint96 delegatorRewardsPerToken;
//        uint96 lastDelegatorRewardsPerToken;
//        uint96 lastStakingRewardsPerWeight;
//        uint48 balance;
//    }
//    mapping(address => StakingRewards) stakingRewards;

    struct GuardianStakingRewards {
        uint96 delegatorRewardsPerToken;
        uint48 balance;
        uint96 lastStakingRewardsPerWeight;
    }

    mapping(address => GuardianStakingRewards) guardiansStakingRewards;

    struct DelegatorStakingRewards {
        uint48 balance;
        uint96 lastDelegatorRewardsPerToken;
    }

    mapping(address => DelegatorStakingRewards) delegatorsStakingRewards;

    // TODO fit one state entry?
    struct FeesAndBootstrap {
        uint48 feeBalance;
        uint48 lastGeneralFeesPerMember;
        uint48 lastCertifiedFeesPerMember;
        uint48 bootstrapBalance;
        uint48 lastGeneralBootstrapPerMember;
        uint48 lastCertifiedBootstrapPerMember;
    }
    mapping(address => FeesAndBootstrap) feesAndBootstrap;

	uint256 constant PERCENT_MILLIE_BASE = 100000;

    modifier onlyElectionsContract() {
        require(msg.sender == address(electionsContract), "caller is not the elections contract");

        _;
    }

    modifier onlyDelegationsContract() {
        require(msg.sender == address(delegationsContract), "caller is not the delegations contract");

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
    function _getGuardianStakingRewards(address guardian, bool inCommittee, uint256 guardianWeight, uint256 guardianDelegatedStake, uint256 totalCommitteeWeight) private view returns (GuardianStakingRewards memory guardianStakingRewards, StakingRewardsState memory _stakingRewardsState, uint256 rewardsAdded) {
        Settings memory _settings = settings; //TODO find the right place to read
        _stakingRewardsState = getStakingRewardsState(totalCommitteeWeight, _settings);
        guardianStakingRewards = guardiansStakingRewards[guardian];

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

            rewardsAdded = amount;
        }

        guardianStakingRewards.lastStakingRewardsPerWeight = _stakingRewardsState.stakingRewardsPerWeight;
    }

    function getGuardianStakingRewards(address guardian) private view returns (GuardianStakingRewards memory guardianStakingRewards, StakingRewardsState memory _stakingRewardsState, uint256 rewardsAdded) {
        (bool inCommittee, uint256 guardianWeight, ,uint256 totalCommitteeWeight) = committeeContract.getMemberInfo(guardian);
        uint256 guardianDelegatedStake = delegationsContract.getDelegatedStake(guardian);
        return _getGuardianStakingRewards(guardian, inCommittee, guardianWeight, guardianDelegatedStake, totalCommitteeWeight);
    }

    // Internal interface: delegator actions (staking, delegation) [Called by Elections on delegations notification]
    function _getDelegatorStakingRewards(address delegator, uint256 delegatorStake, address guardian, bool inCommittee, uint256 guardianWeight, uint256 guardianDelegatedStake, uint256 totalCommitteeWeight) private view returns (DelegatorStakingRewards memory delegatorStakingRewards, GuardianStakingRewards memory guardianStakingRewards, StakingRewardsState memory _stakingRewardsState, uint256 guardianRewardsAdded, uint256 delegatorRewardsAdded){
        (guardianStakingRewards, _stakingRewardsState, guardianRewardsAdded) = _getGuardianStakingRewards(guardian, inCommittee, guardianWeight, guardianDelegatedStake, totalCommitteeWeight);
        delegatorStakingRewards = delegatorsStakingRewards[delegator];

        uint256 amount = uint256(guardianStakingRewards.delegatorRewardsPerToken)
            .sub(uint256(delegatorStakingRewards.lastDelegatorRewardsPerToken))
            .mul(delegatorStake)
            .div(TOKEN_BASE);

        delegatorStakingRewards.balance = delegatorStakingRewards.balance.add(toUint48Granularity(amount));
        delegatorStakingRewards.lastDelegatorRewardsPerToken = guardianStakingRewards.delegatorRewardsPerToken;

        delegatorRewardsAdded = amount;
    }

    struct GetDelegatorsStakingRewardsVars {
        IDelegations delegationsContract;
        uint256 totalCommitteeWeight;
        bool inCommittee;
        uint256 guardianWeight;
    }

    function getDelegatorStakingRewards(address delegator) private view returns (DelegatorStakingRewards memory delegatorStakingRewards, address guardian, GuardianStakingRewards memory guardianStakingRewards, StakingRewardsState memory _stakingRewardsState, uint256 guardianRewardsAdded, uint256 delegatorRewardsAdded) {
        GetDelegatorsStakingRewardsVars memory vars;
        committeeContract;
        vars.delegationsContract = delegationsContract;

        uint256 delegatorStake;
        (guardian, delegatorStake) = vars.delegationsContract.getDelegationInfo(delegator);
        (vars.inCommittee, vars.guardianWeight,,vars.totalCommitteeWeight) = committeeContract.getMemberInfo(guardian);
        (delegatorStakingRewards, guardianStakingRewards, _stakingRewardsState, guardianRewardsAdded, delegatorRewardsAdded) = _getDelegatorStakingRewards(
            delegator,
            delegatorStake,
            guardian,
            vars.inCommittee,
            vars.guardianWeight,
            vars.delegationsContract.getDelegatedStake(guardian),
            vars.totalCommitteeWeight
        );
    }

    function updateDelegatorStakingRewards(address delegator) private {
        address guardian;
        GuardianStakingRewards memory guardianRewards;
        uint256 guardianStakingRewardsAdded;
        uint256 delegatorStakingRewardsAdded;
        (delegatorsStakingRewards[delegator], guardian, guardianRewards, stakingRewardsState, guardianStakingRewardsAdded, delegatorStakingRewardsAdded) = getDelegatorStakingRewards(delegator);
        guardiansStakingRewards[guardian] = guardianRewards;

        emit GuardianStakingRewardsAssigned(guardian, guardianStakingRewardsAdded, guardianRewards.delegatorRewardsPerToken);
        emit StakingRewardsAssigned(delegator, delegatorStakingRewardsAdded);
    }

    //
    // Bootstrap and fees
    //

    function getFeesAndBootstrapState(uint generalCommitteeSize, uint certifiedCommitteeSize) private view returns (FeesAndBootstrapState memory _feesAndBootstrapState) {
        Settings memory _settings = settings;

        _feesAndBootstrapState = feesAndBootstrapState;

        if (_settings.active) {
            uint48 generalFeesDelta = generalCommitteeSize == 0 ? 0 : toUint48Granularity(generalFeesWallet.getOutstandingFees().div(generalCommitteeSize));
            uint48 certifiedFeesDelta = generalFeesDelta.add(certifiedCommitteeSize == 0 ? 0 : toUint48Granularity(certifiedFeesWallet.getOutstandingFees().div(certifiedCommitteeSize)));

            _feesAndBootstrapState.generalFeesPerMember = _feesAndBootstrapState.generalFeesPerMember.add(generalFeesDelta);
            _feesAndBootstrapState.certifiedFeesPerMember = _feesAndBootstrapState.certifiedFeesPerMember.add(certifiedFeesDelta);

            uint duration = now.sub(_feesAndBootstrapState.lastAssigned);
            uint48 generalBootstrapDelta = uint48(uint(_settings.generalCommitteeAnnualBootstrap).mul(duration).div(365 days));
            uint48 certifiedBootstrapDelta = uint48(uint(_settings.certifiedCommitteeAnnualBootstrap).mul(duration).div(365 days));

            _feesAndBootstrapState.generalBootstrapPerMember = _feesAndBootstrapState.generalBootstrapPerMember.add(generalBootstrapDelta);
            _feesAndBootstrapState.certifiedBootstrapPerMember = _feesAndBootstrapState.certifiedBootstrapPerMember.add(generalBootstrapDelta).add(certifiedBootstrapDelta);
            _feesAndBootstrapState.lastAssigned = uint32(block.timestamp);

//            feesAndBootstrapState = _feesAndBootstrapState;
        }
    }

    // Internal interface: committee membership changed (joined, left)
    function _getGuardianFeesAndBootstrap(address guardian, bool inCommittee, bool isCertified, uint generalCommitteeSize, uint certifiedCommitteeSize) private view returns (FeesAndBootstrap memory guardianFeesAndBootstrap, FeesAndBootstrapState memory _feesAndBootstrapState, uint256 addedBootstrapAmount, uint256 addedFeesAmount){
        _feesAndBootstrapState = getFeesAndBootstrapState(generalCommitteeSize, certifiedCommitteeSize);
        guardianFeesAndBootstrap = feesAndBootstrap[guardian];

        if (inCommittee) {
            uint48 bootstrapAmount = isCertified ? _feesAndBootstrapState.certifiedBootstrapPerMember.sub(guardianFeesAndBootstrap.lastCertifiedBootstrapPerMember) : _feesAndBootstrapState.generalBootstrapPerMember.sub(guardianFeesAndBootstrap.lastGeneralBootstrapPerMember);
            guardianFeesAndBootstrap.bootstrapBalance = guardianFeesAndBootstrap.bootstrapBalance.add(bootstrapAmount);
            addedBootstrapAmount = toUint256Granularity(bootstrapAmount);

            uint48 feesAmount = isCertified ? _feesAndBootstrapState.certifiedFeesPerMember.sub(guardianFeesAndBootstrap.lastCertifiedFeesPerMember) : _feesAndBootstrapState.generalFeesPerMember.sub(guardianFeesAndBootstrap.lastGeneralFeesPerMember);
            guardianFeesAndBootstrap.feeBalance = guardianFeesAndBootstrap.feeBalance.add(feesAmount);
            addedFeesAmount = toUint256Granularity(feesAmount);
        }
        
        guardianFeesAndBootstrap.lastGeneralBootstrapPerMember = _feesAndBootstrapState.generalBootstrapPerMember;
        guardianFeesAndBootstrap.lastCertifiedBootstrapPerMember = _feesAndBootstrapState.certifiedBootstrapPerMember;
        guardianFeesAndBootstrap.lastGeneralFeesPerMember = _feesAndBootstrapState.generalFeesPerMember;
        guardianFeesAndBootstrap.lastCertifiedFeesPerMember = _feesAndBootstrapState.certifiedFeesPerMember;
    }

    function getGuardianFeesAndBootstrap(address guardian) private view returns (FeesAndBootstrap memory guardianFeesAndBootstrap, FeesAndBootstrapState memory _feesAndBootstrapState, uint256 addedBootstrapAmount, uint256 addedFeesAmount) {
        ICommittee _committeeContract = committeeContract;
        (uint generalCommitteeSize, uint certifiedCommitteeSize, ) = _committeeContract.getCommitteeStats();
        (bool inCommittee, , bool certified,) = _committeeContract.getMemberInfo(guardian);
        (guardianFeesAndBootstrap, _feesAndBootstrapState, addedBootstrapAmount, addedFeesAmount) = _getGuardianFeesAndBootstrap(guardian, inCommittee, certified, generalCommitteeSize, certifiedCommitteeSize);
    }

    function updateGuardianFeesAndBootstrap(address guardian) private {
        uint256 addedBootstrapAmount;
        uint256 addedFeesAmount;
        (feesAndBootstrap[guardian], feesAndBootstrapState, addedBootstrapAmount, addedFeesAmount) = getGuardianFeesAndBootstrap(guardian);
        generalFeesWallet.collectFees();
        certifiedFeesWallet.collectFees();

        emit BootstrapRewardsAssigned(guardian, addedBootstrapAmount);
        emit FeesAssigned(guardian, addedFeesAmount);
    }

    //
    // External push notifications
    //

    function committeeMembershipWillChange(address guardian, uint256 weight, uint256 delegatedStake, uint256 totalCommitteeWeight, bool inCommittee, bool isCertified, uint generalCommitteeSize, uint certifiedCommitteeSize) external override onlyElectionsContract {
        uint256 addedBootstrapAmount;
        uint256 addedFeesAmount;
        (feesAndBootstrap[guardian], feesAndBootstrapState, addedBootstrapAmount, addedFeesAmount) = _getGuardianFeesAndBootstrap(guardian, inCommittee, isCertified, generalCommitteeSize, certifiedCommitteeSize);
        generalFeesWallet.collectFees(); // TODO consider a different flow: collect, get
        certifiedFeesWallet.collectFees();

        emit BootstrapRewardsAssigned(guardian, addedBootstrapAmount);
        emit FeesAssigned(guardian, addedFeesAmount);

        uint256 guardianStakingRewardsAdded;
        GuardianStakingRewards memory guardianStakingRewards;
        (guardianStakingRewards, stakingRewardsState, guardianStakingRewardsAdded) = _getGuardianStakingRewards(guardian, inCommittee, weight, delegatedStake, totalCommitteeWeight);
        guardiansStakingRewards[guardian] = guardianStakingRewards;

        emit GuardianStakingRewardsAssigned(guardian, guardianStakingRewardsAdded, guardianStakingRewards.delegatorRewardsPerToken);
    }

    struct DelegationWillChangeVars {
        bool inCommittee;
        uint256 weight;
        uint256 totalCommitteeWeight;
        uint256 guardianRewardsAdded;
        uint256 delegatorRewardsAdded;
    }

    function delegationWillChange(address guardian, uint256 delegatedStake, address delegator, uint256 delegatorStake, address nextGuardian) external override onlyDelegationsContract {
        DelegationWillChangeVars memory vars;
        (vars.inCommittee, vars.weight, , vars.totalCommitteeWeight) = committeeContract.getMemberInfo(guardian);

        GuardianStakingRewards memory guardianStakingRewards;
        DelegatorStakingRewards memory delegatorStakingRewards;
        (delegatorStakingRewards, guardianStakingRewards, stakingRewardsState, vars.guardianRewardsAdded, vars.delegatorRewardsAdded) = _getDelegatorStakingRewards(delegator, delegatorStake, guardian, vars.inCommittee, vars.weight, delegatedStake, vars.totalCommitteeWeight);
        if (nextGuardian != guardian) {
            delegatorStakingRewards.lastDelegatorRewardsPerToken = guardiansStakingRewards[nextGuardian].delegatorRewardsPerToken;
        }

        guardiansStakingRewards[guardian] = guardianStakingRewards;
        delegatorsStakingRewards[delegator] = delegatorStakingRewards;
        emit GuardianStakingRewardsAssigned(guardian, vars.guardianRewardsAdded, guardianStakingRewards.delegatorRewardsPerToken);
        emit StakingRewardsAssigned(guardian, vars.delegatorRewardsAdded);
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
        (FeesAndBootstrap memory guardianFeesAndBootstrap,,,) = getGuardianFeesAndBootstrap(addr);
        return toUint256Granularity(guardianFeesAndBootstrap.bootstrapBalance);
    }

    function withdrawBootstrapFunds(address guardian) external override {
        updateGuardianFeesAndBootstrap(guardian);
        uint48 amount = feesAndBootstrap[guardian].bootstrapBalance;
        feesAndBootstrap[guardian].bootstrapBalance = 0;
        emit BootstrapRewardsWithdrawn(guardian, toUint256Granularity(amount));

        bootstrapRewardsWallet.withdraw(toUint256Granularity(amount));
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
        (DelegatorStakingRewards memory delegatorStakingRewards,,,,,) = getDelegatorStakingRewards(addr);
        (GuardianStakingRewards memory guardianStakingRewards,,) = getGuardianStakingRewards(addr); // TODO consider removing, data in state must be up to date at this point
        return toUint256Granularity(delegatorStakingRewards.balance.add(guardianStakingRewards.balance));
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
        (FeesAndBootstrap memory guardianFeesAndBootstrap,,,) = getGuardianFeesAndBootstrap(addr);
        return toUint256Granularity(guardianFeesAndBootstrap.feeBalance);
    }

    function withdrawFees(address guardian) external override {
        updateGuardianFeesAndBootstrap(guardian);

        uint48 amount = feesAndBootstrap[guardian].feeBalance;
        feesAndBootstrap[guardian].feeBalance = 0;
        emit FeesWithdrawn(guardian, toUint256Granularity(amount));
        require(transfer(erc20, guardian, amount), "Rewards::claimExternalTokenRewards - insufficient funds");
    }

    function migrateStakingRewardsBalance(address addr) external override {
        require(!settings.active, "Reward distribution must be deactivated for migration");

        IRewards currentRewardsContract = IRewards(getRewardsContract());
        require(address(currentRewardsContract) != address(this), "New rewards contract is not set");

        updateDelegatorStakingRewards(addr);

        uint48 guardianBalance = guardiansStakingRewards[addr].balance;
        guardiansStakingRewards[addr].balance = 0;

        uint48 delegatorBalance = delegatorsStakingRewards[addr].balance;
        delegatorsStakingRewards[addr].balance = 0;

        require(approve(erc20, address(currentRewardsContract), delegatorBalance.add(guardianBalance)), "migrateStakingBalance: approve failed");
        currentRewardsContract.acceptStakingRewardsMigration(addr, toUint256Granularity(delegatorBalance), toUint256Granularity(guardianBalance));

        emit StakingRewardsBalanceMigrated(addr, toUint256Granularity(delegatorBalance), toUint256Granularity(guardianBalance), address(currentRewardsContract));
    }

    function acceptStakingRewardsMigration(address addr, uint256 delegatorBalance, uint256 guardianBalance) external override {
        uint48 delegatorBalance48 = toUint48Granularity(delegatorBalance);
        uint48 guardianBalance48 = toUint48Granularity(guardianBalance);
        require(transferFrom(erc20, msg.sender, address(this), delegatorBalance48.add(guardianBalance48)), "acceptStakingMigration: transfer failed");

        guardiansStakingRewards[addr].balance = guardiansStakingRewards[addr].balance.add(guardianBalance48);
        delegatorsStakingRewards[addr].balance = delegatorsStakingRewards[addr].balance.add(delegatorBalance48);

        emit StakingRewardsMigrationAccepted(msg.sender, addr, delegatorBalance, guardianBalance);
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
        generalFeesWallet.collectFees();
        certifiedFeesWallet.collectFees();

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
    IFeesWallet generalFeesWallet;
    IFeesWallet certifiedFeesWallet;
    IProtocolWallet stakingRewardsWallet;
    IProtocolWallet bootstrapRewardsWallet;
    function refreshContracts() external override {
        electionsContract = IElections(getElectionsContract());
        committeeContract = ICommittee(getCommitteeContract());
        delegationsContract = IDelegations(getDelegationsContract());
        guardianRegistrationContract = IGuardiansRegistration(getGuardiansRegistrationContract());
        generalFeesWallet = IFeesWallet(getGeneralFeesWallet());
        certifiedFeesWallet = IFeesWallet(getCertifiedFeesWallet());
        stakingRewardsWallet = IProtocolWallet(getStakingRewardsWallet());
        bootstrapRewardsWallet = IProtocolWallet(getBootstrapRewardsWallet());
    }
}
