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
        uint32 defaultDelegatorsStakingRewardsPercentMille;
        bool active;
    }
    Settings settings;

    IERC20 bootstrapToken;
    IERC20 erc20;

    struct StakingRewardsState {
        uint96 stakingRewardsPerWeight;
        uint96 stakingWalletAllocatedRewards;
        uint32 lastAssigned;
    }
    StakingRewardsState stakingRewardsState;

    uint96 unclaimedStakingRewards;

    struct FeesAndBootstrapState {
        uint48 certifiedFeesPerMember;
        uint48 generalFeesPerMember;
        uint48 certifiedBootstrapPerMember;
        uint48 generalBootstrapPerMember;
        uint32 lastAssigned;
    }
    FeesAndBootstrapState feesAndBootstrapState;

    struct GuardianStakingRewards {
        uint96 delegatorRewardsPerToken;
        uint96 lastStakingRewardsPerWeight;
        uint48 balance;
    }
    mapping(address => GuardianStakingRewards) public guardiansStakingRewards;

    struct GuardianRewardSettings {
        uint32 delegatorsStakingRewardsPercentMille;
        bool overrideDefault;
    }
    mapping(address => GuardianRewardSettings) public guardiansRewardSettings;

    struct DelegatorStakingRewards {
        uint48 balance;
        uint96 lastDelegatorRewardsPerToken;
    }

    mapping(address => DelegatorStakingRewards) public delegatorsStakingRewards;

    // TODO fit one state entry?
    struct FeesAndBootstrap {
        uint48 feeBalance;
        uint48 lastGeneralFeesPerMember;
        uint48 lastCertifiedFeesPerMember;
        uint48 bootstrapBalance;
        uint48 lastGeneralBootstrapPerMember;
        uint48 lastCertifiedBootstrapPerMember;
    }
    mapping(address => FeesAndBootstrap) public feesAndBootstrap;

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

    function getStakingRewardsState(uint256 totalCommitteeWeight, Settings memory _settings) private view returns (StakingRewardsState memory _stakingRewardsState, uint256 allocatedRewards) {
        _stakingRewardsState = stakingRewardsState;
        if (_settings.active) {
            uint delta = calcStakingRewardPerWeightDelta(totalCommitteeWeight, block.timestamp - stakingRewardsState.lastAssigned, _settings);
            _stakingRewardsState.stakingRewardsPerWeight = uint96(uint256(stakingRewardsState.stakingRewardsPerWeight).add(delta));
            _stakingRewardsState.lastAssigned = uint32(block.timestamp);
            allocatedRewards = delta.mul(totalCommitteeWeight).div(TOKEN_BASE);
            _stakingRewardsState.stakingWalletAllocatedRewards = uint96(_stakingRewardsState.stakingWalletAllocatedRewards.add(allocatedRewards));
        }
    }

    function _updateStakingRewardsState(uint256 totalCommitteeWeight, Settings memory _settings) private returns (StakingRewardsState memory _stakingRewardsState) {
        if (!_settings.active) {
            return stakingRewardsState;
        }

        uint allocatedRewards;
        (_stakingRewardsState, allocatedRewards) = getStakingRewardsState(totalCommitteeWeight, _settings);
        stakingRewardsState = _stakingRewardsState;
        emit StakingRewardAllocated(allocatedRewards, _stakingRewardsState.stakingRewardsPerWeight);
    }

    function updateStakingRewardsState() private returns (StakingRewardsState memory _stakingRewardsState) {
        (, , uint totalCommitteeWeight) = committeeContract.getCommitteeStats();
        return _updateStakingRewardsState(totalCommitteeWeight, settings);
    }

    function _getGuardianStakingRewards(address guardian, bool inCommittee, uint256 guardianWeight, uint256 guardianDelegatedStake, StakingRewardsState memory _stakingRewardsState, Settings memory _settings) private view returns (GuardianStakingRewards memory guardianStakingRewards, uint256 rewardsAdded) {
        guardianStakingRewards = guardiansStakingRewards[guardian];

        if (inCommittee) {
            uint256 totalRewards = uint256(_stakingRewardsState.stakingRewardsPerWeight)
                .sub(uint256(guardianStakingRewards.lastStakingRewardsPerWeight))
                .mul(guardianWeight);

            uint256 delegatorRewardsRatioPercentMille = getGuardianDelegatorStakingRewardsPercentMille(guardian, _settings);

            uint256 delegatorRewardsPerTokenDelta = guardianDelegatedStake == 0 ? 0 : totalRewards
                .div(guardianDelegatedStake)
                .mul(delegatorRewardsRatioPercentMille)
                .div(PERCENT_MILLIE_BASE);

            uint256 guardianCutPercentMille = PERCENT_MILLIE_BASE.sub(delegatorRewardsRatioPercentMille);

            uint256 guardianRewards = totalRewards
                .mul(guardianCutPercentMille)
                .div(PERCENT_MILLIE_BASE)
                .div(TOKEN_BASE);

            guardianStakingRewards.delegatorRewardsPerToken = uint96(guardianStakingRewards.delegatorRewardsPerToken.add(delegatorRewardsPerTokenDelta));
            guardianStakingRewards.balance = guardianStakingRewards.balance.add(toUint48Granularity(guardianRewards));

            rewardsAdded = guardianRewards;
        }

        guardianStakingRewards.lastStakingRewardsPerWeight = _stakingRewardsState.stakingRewardsPerWeight;
    }

    function getGuardianStakingRewards(address guardian) private view returns (GuardianStakingRewards memory guardianStakingRewards) {
        Settings memory _settings = settings;

        (bool inCommittee, uint256 guardianWeight, ,uint256 totalCommitteeWeight) = committeeContract.getMemberInfo(guardian);
        uint256 guardianDelegatedStake = delegationsContract.getDelegatedStake(guardian);

        (StakingRewardsState memory _stakingRewardsState,) = getStakingRewardsState(totalCommitteeWeight, _settings);
        (guardianStakingRewards,) = _getGuardianStakingRewards(guardian, inCommittee, guardianWeight, guardianDelegatedStake, _stakingRewardsState, _settings);
    }

    function _getDelegatorStakingRewards(address delegator, uint256 delegatorStake, GuardianStakingRewards memory guardianStakingRewards) private view returns (DelegatorStakingRewards memory delegatorStakingRewards, uint256 delegatorRewardsAdded) {
        delegatorStakingRewards = delegatorsStakingRewards[delegator];

        uint256 amount = uint256(guardianStakingRewards.delegatorRewardsPerToken)
            .sub(uint256(delegatorStakingRewards.lastDelegatorRewardsPerToken))
            .mul(delegatorStake)
            .div(TOKEN_BASE);

        delegatorStakingRewards.balance = delegatorStakingRewards.balance.add(toUint48Granularity(amount));
        delegatorStakingRewards.lastDelegatorRewardsPerToken = guardianStakingRewards.delegatorRewardsPerToken;

        delegatorRewardsAdded = amount;
    }

    function getDelegatorStakingRewards(address delegator) private view returns (DelegatorStakingRewards memory delegatorStakingRewards) {
        (address guardian, uint256 delegatorStake) = delegationsContract.getDelegationInfo(delegator);
        GuardianStakingRewards memory guardianStakingRewards = getGuardianStakingRewards(guardian);

        (delegatorStakingRewards,) = _getDelegatorStakingRewards(delegator, delegatorStake, guardianStakingRewards);
    }

    function _updateGuardianStakingRewards(address guardian, bool inCommittee, uint256 guardianWeight, uint256 guardianDelegatedStake, StakingRewardsState memory _stakingRewardsState, Settings memory _settings) private returns (GuardianStakingRewards memory guardianStakingRewards) {
        uint256 guardianStakingRewardsAdded;
        (guardianStakingRewards, guardianStakingRewardsAdded) = _getGuardianStakingRewards(guardian, inCommittee, guardianWeight, guardianDelegatedStake, _stakingRewardsState, _settings);
        guardiansStakingRewards[guardian] = guardianStakingRewards;
        emit GuardianStakingRewardsAssigned(guardian, guardianStakingRewardsAdded, guardianStakingRewards.delegatorRewardsPerToken);
    }

    function _updateDelegatorStakingRewards(address delegator, uint256 delegatorStake, GuardianStakingRewards memory guardianStakingRewards) private {
        uint256 delegatorStakingRewardsAdded;
        (delegatorsStakingRewards[delegator], delegatorStakingRewardsAdded) = _getDelegatorStakingRewards(delegator, delegatorStake, guardianStakingRewards);

        emit StakingRewardsAssigned(delegator, delegatorStakingRewardsAdded);
    }

    function updateGuardianStakingRewards(address guardian, StakingRewardsState memory _stakingRewardsState, Settings memory _settings) private returns (GuardianStakingRewards memory guardianStakingRewards){
        (bool inCommittee, uint256 guardianWeight,,) = committeeContract.getMemberInfo(guardian);
        return _updateGuardianStakingRewards(guardian, inCommittee, guardianWeight, delegationsContract.getDelegatedStake(guardian), _stakingRewardsState, _settings);
    }

    function updateDelegatorStakingRewards(address delegator) private {
        Settings memory _settings = settings;

        (, , uint totalCommitteeWeight) = committeeContract.getCommitteeStats();
        StakingRewardsState memory _stakingRewardsState = _updateStakingRewardsState(totalCommitteeWeight, _settings);

        (address guardian, uint delegatorStake) = delegationsContract.getDelegationInfo(delegator);
        GuardianStakingRewards memory guardianRewards = updateGuardianStakingRewards(guardian, _stakingRewardsState, _settings);

        _updateDelegatorStakingRewards(delegator, delegatorStake, guardianRewards);
    }

    function getGuardianDelegatorStakingRewardsPercentMille(address guardian, Settings memory _settings) private view returns (uint256 delegatorRewardsRatioPercentMille) {
        GuardianRewardSettings memory guardianSettings = guardiansRewardSettings[guardian];
        return guardianSettings.overrideDefault ? guardianSettings.delegatorsStakingRewardsPercentMille : _settings.defaultDelegatorsStakingRewardsPercentMille;
    }

    //
    // Bootstrap and fees
    //

    function getFeesAndBootstrapState(uint generalCommitteeSize, uint certifiedCommitteeSize, uint256 collectedGeneralFees, uint256 collectedCertifiedFees, Settings memory _settings) private view returns (FeesAndBootstrapState memory _feesAndBootstrapState, uint256 allocatedBootstrap) {
        _feesAndBootstrapState = feesAndBootstrapState;

        if (_settings.active) {
            uint48 generalFeesDelta = generalCommitteeSize == 0 ? 0 : toUint48Granularity(collectedGeneralFees.div(generalCommitteeSize));
            uint48 certifiedFeesDelta = generalFeesDelta.add(certifiedCommitteeSize == 0 ? 0 : toUint48Granularity(collectedCertifiedFees.div(certifiedCommitteeSize)));

            _feesAndBootstrapState.generalFeesPerMember = _feesAndBootstrapState.generalFeesPerMember.add(generalFeesDelta);
            _feesAndBootstrapState.certifiedFeesPerMember = _feesAndBootstrapState.certifiedFeesPerMember.add(certifiedFeesDelta);

            uint duration = now.sub(_feesAndBootstrapState.lastAssigned);
            uint48 generalBootstrapDelta = uint48(uint(_settings.generalCommitteeAnnualBootstrap).mul(duration).div(365 days));
            uint48 certifiedBootstrapDelta = generalBootstrapDelta.add(uint48(uint(_settings.certifiedCommitteeAnnualBootstrap).mul(duration).div(365 days)));

            _feesAndBootstrapState.generalBootstrapPerMember = _feesAndBootstrapState.generalBootstrapPerMember.add(generalBootstrapDelta);
            _feesAndBootstrapState.certifiedBootstrapPerMember = _feesAndBootstrapState.certifiedBootstrapPerMember.add(certifiedBootstrapDelta);
            _feesAndBootstrapState.lastAssigned = uint32(block.timestamp);

            allocatedBootstrap = toUint256Granularity(generalBootstrapDelta).mul(generalCommitteeSize).add(toUint256Granularity(certifiedBootstrapDelta).mul(certifiedCommitteeSize));
        }
    }

    function _updateFeesAndBootstrapState(uint generalCommitteeSize, uint certifiedCommitteeSize) private returns (FeesAndBootstrapState memory _feesAndBootstrapState) {
        Settings memory _settings = settings;
        if (!_settings.active) {
            return feesAndBootstrapState;
        }

        uint256 collectedGeneralFees = generalFeesWallet.collectFees();
        uint256 collectedCertifiedFees = certifiedFeesWallet.collectFees();
        uint256 allocatedBootstrap;

        (_feesAndBootstrapState, allocatedBootstrap) = getFeesAndBootstrapState(generalCommitteeSize, certifiedCommitteeSize, collectedGeneralFees, collectedCertifiedFees, _settings);
        bootstrapRewardsWallet.withdraw(allocatedBootstrap);

        feesAndBootstrapState = _feesAndBootstrapState;
    }

    function updateFeesAndBootstrapState() private returns (FeesAndBootstrapState memory _feesAndBootstrapState) {
        (uint generalCommitteeSize, uint certifiedCommitteeSize, ) = committeeContract.getCommitteeStats();
        return _updateFeesAndBootstrapState(generalCommitteeSize, certifiedCommitteeSize);
    }

    function _getGuardianFeesAndBootstrap(address guardian, bool inCommittee, bool isCertified, FeesAndBootstrapState memory _feesAndBootstrapState) private view returns (FeesAndBootstrap memory guardianFeesAndBootstrap, uint256 addedBootstrapAmount, uint256 addedFeesAmount) {
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

    function _updateGuardianFeesAndBootstrap(address guardian, bool inCommittee, bool isCertified, uint generalCommitteeSize, uint certifiedCommitteeSize) private {
        uint256 addedBootstrapAmount;
        uint256 addedFeesAmount;

        FeesAndBootstrapState memory _feesAndBootstrapState = _updateFeesAndBootstrapState(generalCommitteeSize, certifiedCommitteeSize);
        (feesAndBootstrap[guardian], addedBootstrapAmount, addedFeesAmount) = _getGuardianFeesAndBootstrap(guardian, inCommittee, isCertified, _feesAndBootstrapState);

        emit BootstrapRewardsAssigned(guardian, addedBootstrapAmount);
        emit FeesAssigned(guardian, addedFeesAmount);
    }

    function getGuardianFeesAndBootstrap(address guardian) private view returns (FeesAndBootstrap memory guardianFeesAndBootstrap) {
        ICommittee _committeeContract = committeeContract;
        (uint generalCommitteeSize, uint certifiedCommitteeSize, ) = _committeeContract.getCommitteeStats();
        (bool inCommittee, , bool isCertified,) = _committeeContract.getMemberInfo(guardian);
        (FeesAndBootstrapState memory _feesAndBootstrapState,) = getFeesAndBootstrapState(generalCommitteeSize, certifiedCommitteeSize, generalFeesWallet.getOutstandingFees(), certifiedFeesWallet.getOutstandingFees(), settings);
        (guardianFeesAndBootstrap, ,) = _getGuardianFeesAndBootstrap(guardian, inCommittee, isCertified, _feesAndBootstrapState);
    }

    function updateGuardianFeesAndBootstrap(address guardian) private {
        ICommittee _committeeContract = committeeContract;
        (uint generalCommitteeSize, uint certifiedCommitteeSize, ) = _committeeContract.getCommitteeStats();
        (bool inCommittee, , bool isCertified,) = _committeeContract.getMemberInfo(guardian);
        _updateGuardianFeesAndBootstrap(guardian, inCommittee, isCertified, generalCommitteeSize, certifiedCommitteeSize);
    }

    //
    // External push notifications
    //

    function committeeMembershipWillChange(address guardian, uint256 weight, uint256 delegatedStake, uint256 totalCommitteeWeight, bool inCommittee, bool isCertified, uint generalCommitteeSize, uint certifiedCommitteeSize) external override onlyElectionsContract {
        _updateGuardianFeesAndBootstrap(guardian, inCommittee, isCertified, generalCommitteeSize, certifiedCommitteeSize);
        Settings memory _settings = settings;
        StakingRewardsState memory _stakingRewardsState = _updateStakingRewardsState(totalCommitteeWeight, _settings);
        _updateGuardianStakingRewards(guardian, inCommittee, weight, delegatedStake, _stakingRewardsState, _settings);
    }

    function delegationWillChange(address guardian, uint256 guardianDelegatedStake, address delegator, uint256 delegatorStake, address nextGuardian, uint256 nextGuardianDelegatedStake) external override onlyDelegationsContract {
        Settings memory _settings = settings;
        (bool inCommittee, uint256 weight, , uint256 totalCommitteeWeight) = committeeContract.getMemberInfo(guardian);

        StakingRewardsState memory _stakingRewardsState = _updateStakingRewardsState(totalCommitteeWeight, _settings);
        GuardianStakingRewards memory guardianStakingRewards = _updateGuardianStakingRewards(guardian, inCommittee, weight, guardianDelegatedStake, _stakingRewardsState, _settings);
        _updateDelegatorStakingRewards(delegator, delegatorStake, guardianStakingRewards);

        if (nextGuardian != guardian) {
            (inCommittee, weight, , totalCommitteeWeight) = committeeContract.getMemberInfo(nextGuardian);
            GuardianStakingRewards memory nextGuardianStakingRewards = _updateGuardianStakingRewards(nextGuardian, inCommittee, weight, nextGuardianDelegatedStake, _stakingRewardsState, _settings);
            delegatorsStakingRewards[delegator].lastDelegatorRewardsPerToken = nextGuardianStakingRewards.delegatorRewardsPerToken;
        }
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
        uint32 defaultDelegatorsStakingRewardsPercentMille
    ) ManagedContract(_contractRegistry, _registryAdmin) public {
        require(address(_bootstrapToken) != address(0), "bootstrapToken must not be 0");
        require(address(_erc20) != address(0), "erc20 must not be 0");

        _setGeneralCommitteeAnnualBootstrap(generalCommitteeAnnualBootstrap);
        _setCertifiedCommitteeAnnualBootstrap(certifiedCommitteeAnnualBootstrap);
        _setAnnualStakingRewardsRate(annualRateInPercentMille, annualCap);
        setDefaultDelegatorsStakingRewardsPercentMille(defaultDelegatorsStakingRewardsPercentMille);

        erc20 = _erc20;
        bootstrapToken = _bootstrapToken;
    }

    // bootstrap rewards

    function _setGeneralCommitteeAnnualBootstrap(uint256 annualAmount) private {
        settings.generalCommitteeAnnualBootstrap = toUint48Granularity(annualAmount);
        emit GeneralCommitteeAnnualBootstrapChanged(annualAmount);
    }

    function setGeneralCommitteeAnnualBootstrap(uint256 annualAmount) external override onlyFunctionalManager onlyWhenActive {
        updateFeesAndBootstrapState();
        _setGeneralCommitteeAnnualBootstrap(annualAmount);
    }

    function _setCertifiedCommitteeAnnualBootstrap(uint256 annualAmount) private {
        settings.certifiedCommitteeAnnualBootstrap = toUint48Granularity(annualAmount);
        emit CertifiedCommitteeAnnualBootstrapChanged(annualAmount);
    }

    function setCertifiedCommitteeAnnualBootstrap(uint256 annualAmount) external override onlyFunctionalManager onlyWhenActive {
        updateFeesAndBootstrapState();
        _setCertifiedCommitteeAnnualBootstrap(annualAmount);
    }

    function setDefaultDelegatorsStakingRewardsPercentMille(uint32 defaultDelegatorsStakingRewardsPercentMille) public override onlyFunctionalManager onlyWhenActive {
        require(defaultDelegatorsStakingRewardsPercentMille <= PERCENT_MILLIE_BASE, "defaultDelegatorsStakingRewardsPercentMille must not be larger than 100000");
        settings.defaultDelegatorsStakingRewardsPercentMille = defaultDelegatorsStakingRewardsPercentMille;
        emit DefaultDelegatorsStakingRewardsChanged(defaultDelegatorsStakingRewardsPercentMille);
    }

    function getGeneralCommitteeAnnualBootstrap() external override view returns (uint256) {
        return toUint256Granularity(settings.generalCommitteeAnnualBootstrap);
    }

    function getCertifiedCommitteeAnnualBootstrap() external override view returns (uint256) {
        return toUint256Granularity(settings.certifiedCommitteeAnnualBootstrap);
    }

    function getDefaultDelegatorsStakingRewardsPercentMille() public override view returns (uint32) {
        return settings.defaultDelegatorsStakingRewardsPercentMille;
    }

    function getAnnualStakingRewardsRatePercentMille() external override view returns (uint32) {
        return settings.annualRateInPercentMille;
    }

    function getAnnualStakingRewardsCap() external override view returns (uint256) {
        return toUint256Granularity(settings.annualCap);
    }

    function getBootstrapBalance(address addr) external override view returns (uint256) {
        return toUint256Granularity(getGuardianFeesAndBootstrap(addr).bootstrapBalance);
    }

    function withdrawBootstrapFunds(address guardian) external override {
        updateGuardianFeesAndBootstrap(guardian);
        uint48 amount = feesAndBootstrap[guardian].bootstrapBalance;
        feesAndBootstrap[guardian].bootstrapBalance = 0;
        emit BootstrapRewardsWithdrawn(guardian, toUint256Granularity(amount));

        require(transfer(bootstrapToken, guardian, amount), "Rewards::withdrawBootstrapFunds - insufficient funds");
    }

    // staking rewards

    function _setAnnualStakingRewardsRate(uint256 annualRateInPercentMille, uint256 annualCap) private {
        Settings memory _settings = settings;
        _settings.annualRateInPercentMille = uint32(annualRateInPercentMille);
        _settings.annualCap = toUint48Granularity(annualCap);
        settings = _settings;

        emit AnnualStakingRewardsRateChanged(annualRateInPercentMille, annualCap);
    }

    function setAnnualStakingRewardsRate(uint256 annualRateInPercentMille, uint256 annualCap) public override onlyFunctionalManager onlyWhenActive {
        updateStakingRewardsState();
        return _setAnnualStakingRewardsRate(annualRateInPercentMille, annualCap);
    }

    function setGuardianDelegatorsRewardsRatio(uint32 delegatorsRewardRatioPercentMille) external {
        require(delegatorsRewardRatioPercentMille <= 100000, "delegatorsRewardRatioPercentMille must be 100000 at most");

        updateDelegatorStakingRewards(msg.sender);

        guardiansRewardSettings[msg.sender] = GuardianRewardSettings({
            overrideDefault: true,
            delegatorsStakingRewardsPercentMille: delegatorsRewardRatioPercentMille
        });

        // TODO event
    }

    function getStakingRewardsBalance(address addr) external override view returns (uint256) {
        DelegatorStakingRewards memory delegatorStakingRewards = getDelegatorStakingRewards(addr);
        GuardianStakingRewards memory guardianStakingRewards = getGuardianStakingRewards(addr); // TODO consider removing, data in state must be up to date at this point
        return toUint256Granularity(delegatorStakingRewards.balance.add(guardianStakingRewards.balance));
    }

    struct DistributorBatchState {
        uint256 fromBlock;
        uint256 toBlock;
        uint256 nextTxIndex;
        uint split;
    }
    mapping (address => DistributorBatchState) public distributorBatchState;

    function getFeeBalance(address addr) external override view returns (uint256) {
        return toUint256Granularity(getGuardianFeesAndBootstrap(addr).feeBalance);
    }

    function withdrawFees(address guardian) external override {
        updateGuardianFeesAndBootstrap(guardian);

        uint48 amount = feesAndBootstrap[guardian].feeBalance;
        feesAndBootstrap[guardian].feeBalance = 0;
        emit FeesWithdrawn(guardian, toUint256Granularity(amount));
        require(transfer(erc20, guardian, amount), "Rewards::withdrawFees - insufficient funds");
    }

    function claimStakingRewards(address addr) external override {
        updateDelegatorStakingRewards(addr);

        uint256 guardianBalance = toUint256Granularity(guardiansStakingRewards[addr].balance);
        guardiansStakingRewards[addr].balance = 0;

        uint256 delegatorBalance = toUint256Granularity(delegatorsStakingRewards[addr].balance);
        delegatorsStakingRewards[addr].balance = 0;

        uint256 total = delegatorBalance.add(guardianBalance);

        uint96 allocated = stakingRewardsState.stakingWalletAllocatedRewards;
        if (allocated > 0) {
            stakingRewardsWallet.withdraw(allocated);
            stakingRewardsState.stakingWalletAllocatedRewards = 0;
            unclaimedStakingRewards = uint96(unclaimedStakingRewards.add(allocated).sub(total));
        }

        require(erc20.approve(address(stakingContract), total), "claimStakingRewards: approve failed");

        address[] memory addrs = new address[](1);
        addrs[0] = addr;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = total;
        stakingContract.distributeRewards(total, addrs, amounts);

        emit StakingRewardsClaimed(addr, total);
    }

    function migrateRewardsBalance(address addr) external override {
        require(!settings.active, "Reward distribution must be deactivated for migration");

        IRewards currentRewardsContract = IRewards(getRewardsContract());
        require(address(currentRewardsContract) != address(this), "New rewards contract is not set");

        updateDelegatorStakingRewards(addr);

        uint256 guardianStakingRewards = toUint256Granularity(guardiansStakingRewards[addr].balance);
        guardiansStakingRewards[addr].balance = 0;

        uint256 delegatorStakingRewards = toUint256Granularity(delegatorsStakingRewards[addr].balance);
        delegatorsStakingRewards[addr].balance = 0;

        uint96 allocated = stakingRewardsState.stakingWalletAllocatedRewards;
        if (allocated > 0) {
            stakingRewardsWallet.withdraw(allocated);
            stakingRewardsState.stakingWalletAllocatedRewards = 0;
            unclaimedStakingRewards = uint96(unclaimedStakingRewards.add(allocated).sub(guardianStakingRewards).sub(delegatorStakingRewards));
        }

        updateGuardianFeesAndBootstrap(addr);

        FeesAndBootstrap memory guardianFeesAndBootstrap = feesAndBootstrap[addr];
        uint256 fees = toUint256Granularity(guardianFeesAndBootstrap.feeBalance);
        uint256 bootstrap = toUint256Granularity(guardianFeesAndBootstrap.bootstrapBalance);

        guardianFeesAndBootstrap.feeBalance = 0;
        guardianFeesAndBootstrap.bootstrapBalance = 0;
        feesAndBootstrap[addr] = guardianFeesAndBootstrap;

        require(erc20.approve(address(currentRewardsContract), guardianStakingRewards.add(delegatorStakingRewards).add(fees)), "migrateRewardsBalance: approve failed");
        require(bootstrapToken.approve(address(currentRewardsContract), bootstrap), "migrateRewardsBalance: approve failed");
        currentRewardsContract.acceptRewardsBalanceMigration(addr, guardianStakingRewards, delegatorStakingRewards, fees, bootstrap);

        emit RewardsBalanceMigrated(addr, guardianStakingRewards, delegatorStakingRewards, fees, bootstrap, address(currentRewardsContract));
    }

    function acceptRewardsBalanceMigration(address addr, uint256 guardianStakingRewards, uint256 delegatorStakingRewards, uint256 fees, uint256 bootstrap) external override {
        guardiansStakingRewards[addr].balance = guardiansStakingRewards[addr].balance.add(toUint48Granularity(guardianStakingRewards));
        delegatorsStakingRewards[addr].balance = delegatorsStakingRewards[addr].balance.add(toUint48Granularity(delegatorStakingRewards));

        FeesAndBootstrap memory guardianFeesAndBootstrap = feesAndBootstrap[addr];
        guardianFeesAndBootstrap.feeBalance = guardianFeesAndBootstrap.feeBalance.add(toUint48Granularity(fees));
        guardianFeesAndBootstrap.bootstrapBalance = guardianFeesAndBootstrap.bootstrapBalance.add(toUint48Granularity(bootstrap));
        feesAndBootstrap[addr] = guardianFeesAndBootstrap;

        require(erc20.transferFrom(msg.sender, address(this), guardianStakingRewards.add(delegatorStakingRewards).add(fees)), "acceptRewardBalanceMigration: transfer failed");
        require(bootstrapToken.transferFrom(msg.sender, address(this), bootstrap), "acceptRewardBalanceMigration: transfer failed");

        emit RewardsBalanceMigrationAccepted(msg.sender, addr, guardianStakingRewards, delegatorStakingRewards, fees, bootstrap);
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
        updateFeesAndBootstrapState();
        updateStakingRewardsState();

        settings.active = false;

        emit RewardDistributionDeactivated();
    }

    function getSettings() external override view returns (
        uint generalCommitteeAnnualBootstrap,
        uint certifiedCommitteeAnnualBootstrap,
        uint annualStakingRewardsCap,
        uint32 annualStakingRewardsRatePercentMille,
        uint32 defaultDelegatorsStakingRewardsPercentMille,
        bool active
    ) {
        Settings memory _settings = settings;
        generalCommitteeAnnualBootstrap = toUint256Granularity(_settings.generalCommitteeAnnualBootstrap);
        certifiedCommitteeAnnualBootstrap = toUint256Granularity(_settings.certifiedCommitteeAnnualBootstrap);
        annualStakingRewardsCap = toUint256Granularity(_settings.annualCap);
        annualStakingRewardsRatePercentMille = _settings.annualRateInPercentMille;
        defaultDelegatorsStakingRewardsPercentMille = _settings.defaultDelegatorsStakingRewardsPercentMille;
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
    IStakingContract stakingContract;
    function refreshContracts() external override {
        electionsContract = IElections(getElectionsContract());
        committeeContract = ICommittee(getCommitteeContract());
        delegationsContract = IDelegations(getDelegationsContract());
        guardianRegistrationContract = IGuardiansRegistration(getGuardiansRegistrationContract());
        generalFeesWallet = IFeesWallet(getGeneralFeesWallet());
        certifiedFeesWallet = IFeesWallet(getCertifiedFeesWallet());
        stakingRewardsWallet = IProtocolWallet(getStakingRewardsWallet());
        bootstrapRewardsWallet = IProtocolWallet(getBootstrapRewardsWallet());
        stakingContract = IStakingContract(getStakingContract());
    }
}
