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

    struct GuardianStakingRewards {
        uint96 delegatorRewardsPerToken;
        uint48 balance;
        uint96 lastStakingRewardsPerWeight;
    }

    mapping(address => GuardianStakingRewards) public guardiansStakingRewards;

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
        }
    }

    function updateStakingRewardsState(uint256 totalCommitteeWeight, Settings memory _settings) private returns (StakingRewardsState memory _stakingRewardsState) {
        uint allocatedRewards;
        (_stakingRewardsState, allocatedRewards) = getStakingRewardsState(totalCommitteeWeight, _settings);
        stakingRewardsState = _stakingRewardsState;
        emit StakingRewardAllocated(allocatedRewards, _stakingRewardsState.stakingRewardsPerWeight);
    }

    function _getGuardianStakingRewards(address guardian, bool inCommittee, uint256 guardianWeight, uint256 guardianDelegatedStake, StakingRewardsState memory _stakingRewardsState, Settings memory _settings) private view returns (GuardianStakingRewards memory guardianStakingRewards, uint256 rewardsAdded) {
        guardianStakingRewards = guardiansStakingRewards[guardian];

        if (inCommittee) {
            uint256 totalRewards = uint256(_stakingRewardsState.stakingRewardsPerWeight)
                .sub(uint256(guardianStakingRewards.lastStakingRewardsPerWeight))
                .mul(guardianWeight);

            uint256 delegatorRewardsPerTokenDelta = guardianDelegatedStake == 0 ? 0 : totalRewards
                .div(guardianDelegatedStake)
                .mul(uint256(_settings.delegatorsStakingRewardsPercentMille))
                .div(PERCENT_MILLIE_BASE);

            uint256 guardianCutPercentMille = PERCENT_MILLIE_BASE.sub(_settings.delegatorsStakingRewardsPercentMille);

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
        StakingRewardsState memory _stakingRewardsState = updateStakingRewardsState(totalCommitteeWeight, _settings);

        (address guardian, uint delegatorStake) = delegationsContract.getDelegationInfo(delegator);
        GuardianStakingRewards memory guardianRewards = updateGuardianStakingRewards(guardian, _stakingRewardsState, _settings);

        _updateDelegatorStakingRewards(delegator, delegatorStake, guardianRewards);
    }

    //
    // Bootstrap and fees
    //

    function getFeesAndBootstrapState(uint generalCommitteeSize, uint certifiedCommitteeSize, uint256 collectedGeneralFees, uint256 collectedCertifiedFees) private view returns (FeesAndBootstrapState memory _feesAndBootstrapState) {
        Settings memory _settings = settings;

        _feesAndBootstrapState = feesAndBootstrapState;

        if (_settings.active) {
            uint48 generalFeesDelta = generalCommitteeSize == 0 ? 0 : toUint48Granularity(collectedGeneralFees.div(generalCommitteeSize));
            uint48 certifiedFeesDelta = generalFeesDelta.add(certifiedCommitteeSize == 0 ? 0 : toUint48Granularity(collectedCertifiedFees.div(certifiedCommitteeSize)));

            _feesAndBootstrapState.generalFeesPerMember = _feesAndBootstrapState.generalFeesPerMember.add(generalFeesDelta);
            _feesAndBootstrapState.certifiedFeesPerMember = _feesAndBootstrapState.certifiedFeesPerMember.add(certifiedFeesDelta);

            uint duration = now.sub(_feesAndBootstrapState.lastAssigned);
            uint48 generalBootstrapDelta = uint48(uint(_settings.generalCommitteeAnnualBootstrap).mul(duration).div(365 days));
            uint48 certifiedBootstrapDelta = uint48(uint(_settings.certifiedCommitteeAnnualBootstrap).mul(duration).div(365 days));

            _feesAndBootstrapState.generalBootstrapPerMember = _feesAndBootstrapState.generalBootstrapPerMember.add(generalBootstrapDelta);
            _feesAndBootstrapState.certifiedBootstrapPerMember = _feesAndBootstrapState.certifiedBootstrapPerMember.add(generalBootstrapDelta).add(certifiedBootstrapDelta);
            _feesAndBootstrapState.lastAssigned = uint32(block.timestamp);
        }
    }

    function updateFeesAndBootstrapState(uint generalCommitteeSize, uint certifiedCommitteeSize) private returns (FeesAndBootstrapState memory _feesAndBootstrapState) {
        uint256 collectedGeneralFees = generalFeesWallet.collectFees();
        uint256 collectedCertifiedFees = certifiedFeesWallet.collectFees();

        _feesAndBootstrapState = getFeesAndBootstrapState(generalCommitteeSize, certifiedCommitteeSize, collectedGeneralFees, collectedCertifiedFees);

        feesAndBootstrapState = _feesAndBootstrapState;
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

        FeesAndBootstrapState memory _feesAndBootstrapState = updateFeesAndBootstrapState(generalCommitteeSize, certifiedCommitteeSize);
        (feesAndBootstrap[guardian], addedBootstrapAmount, addedFeesAmount) = _getGuardianFeesAndBootstrap(guardian, inCommittee, isCertified, _feesAndBootstrapState);

        emit BootstrapRewardsAssigned(guardian, addedBootstrapAmount);
        emit FeesAssigned(guardian, addedFeesAmount);
    }

    function getGuardianFeesAndBootstrap(address guardian) private view returns (FeesAndBootstrap memory guardianFeesAndBootstrap) {
        ICommittee _committeeContract = committeeContract;
        (uint generalCommitteeSize, uint certifiedCommitteeSize, ) = _committeeContract.getCommitteeStats();
        (bool inCommittee, , bool isCertified,) = _committeeContract.getMemberInfo(guardian);
        FeesAndBootstrapState memory _feesAndBootstrapState = getFeesAndBootstrapState(generalCommitteeSize, certifiedCommitteeSize, generalFeesWallet.getOutstandingFees(), certifiedFeesWallet.getOutstandingFees());
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
        StakingRewardsState memory _stakingRewardsState = updateStakingRewardsState(totalCommitteeWeight, _settings);
        _updateGuardianStakingRewards(guardian, inCommittee, weight, delegatedStake, _stakingRewardsState, _settings);
    }

    function delegationWillChange(address guardian, uint256 guardianDelegatedStake, address delegator, uint256 delegatorStake, address nextGuardian, uint256 nextGuardianDelegatedStake) external override onlyDelegationsContract {
        Settings memory _settings = settings;
        (bool inCommittee, uint256 weight, , uint256 totalCommitteeWeight) = committeeContract.getMemberInfo(guardian);

        StakingRewardsState memory _stakingRewardsState = updateStakingRewardsState(totalCommitteeWeight, _settings);
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

    function getDelegatorsStakingRewardsPercentMille() public override view returns (uint32) {
        return settings.delegatorsStakingRewardsPercentMille;
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

        stakingRewardsWallet.withdraw(total);

        require(erc20.approve(address(stakingContract), total), "claimStakingRewards: approve failed");

        address[] memory addrs = new address[](1);
        addrs[0] = addr;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = total;
        stakingContract.distributeRewards(total, addrs, amounts);

        emit StakingRewardsClaimed(addr, total);
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

        emit StakingRewardsMigrationAccepted(msg.sender, msg.sender, addr, delegatorBalance, guardianBalance);
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
        (stakingRewardsState,) = getStakingRewardsState(totalStake, settings);

        updateFeesAndBootstrapState(generalCommitteeSize, certifiedCommitteeSize);

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
