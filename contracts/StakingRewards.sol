// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./SafeMath48.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./spec_interfaces/ICommittee.sol";
import "./spec_interfaces/IProtocolWallet.sol";
import "./spec_interfaces/IStakingRewards.sol";
import "./spec_interfaces/IDelegation.sol";
import "./IStakingContract.sol";
import "./ManagedContract.sol";

contract StakingRewards is IStakingRewards, ManagedContract {
    using SafeMath for uint256;
    using SafeMath for uint96;
    using SafeMath48 for uint48;

    uint256 constant PERCENT_MILLIE_BASE = 100000;
    uint256 constant TOKEN_BASE = 1e18;

    uint constant TOKEN_GRANULARITY = 1000000000000000;

    modifier onlyCommitteeContract() {
        require(msg.sender == address(committeeContract), "caller is not the elections contract");

        _;
    }

    modifier onlyDelegationsContract() {
        require(msg.sender == address(delegationsContract), "caller is not the delegations contract");

        _;
    }

    struct Settings {
        uint48 annualCap;
        uint32 annualRateInPercentMille;
        uint32 defaultDelegatorsStakingRewardsPercentMille;
        uint32 maxDelegatorsStakingRewardsPercentMille;
        bool rewardAllocationActive;
    }
    Settings settings;

    IERC20 public erc20;

    struct StakingRewardsState {
        uint96 stakingRewardsPerWeight;
        uint96 unclaimedStakingRewards;
        uint32 lastAssigned;
    }
    StakingRewardsState public stakingRewardsState;

    uint256 public stakingRewardsWithdrawnFromWallet;

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

    constructor(
        IContractRegistry _contractRegistry,
        address _registryAdmin,
        IERC20 _erc20,
        uint annualRateInPercentMille,
        uint annualCap,
        uint32 defaultDelegatorsStakingRewardsPercentMille,
        uint32 maxDelegatorsStakingRewardsPercentMille,
        IStakingRewards previousRewardsContract,
        address[] memory guardiansToMigrate
    ) ManagedContract(_contractRegistry, _registryAdmin) public {
        require(address(_erc20) != address(0), "erc20 must not be 0");

        _setAnnualStakingRewardsRate(annualRateInPercentMille, annualCap);
        setMaxDelegatorsStakingRewardsPercentMille(maxDelegatorsStakingRewardsPercentMille);
        setDefaultDelegatorsStakingRewardsPercentMille(defaultDelegatorsStakingRewardsPercentMille);

        erc20 = _erc20;

        if (address(previousRewardsContract) != address(0)) {
            migrateGuardiansSettings(previousRewardsContract, guardiansToMigrate);
        }
    }

    /*
    * External functions
    */

    function committeeMembershipWillChange(address guardian, uint256 weight, uint256 totalCommitteeWeight, bool inCommittee) external override onlyWhenActive onlyCommitteeContract {
        uint256 delegatedStake = delegationsContract.getDelegatedStake(guardian);

        Settings memory _settings = settings;
        StakingRewardsState memory _stakingRewardsState = _updateStakingRewardsState(totalCommitteeWeight, _settings);
        _updateGuardianStakingRewards(guardian, inCommittee, weight, delegatedStake, _stakingRewardsState, _settings);
    }

    function delegationWillChange(address guardian, uint256 guardianDelegatedStake, address delegator, uint256 delegatorStake, address nextGuardian, uint256 nextGuardianDelegatedStake) external override onlyWhenActive onlyDelegationsContract {
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

    function getStakingRewardsBalance(address addr) external override view returns (uint256) {
        DelegatorStakingRewards memory delegatorStakingRewards = getDelegatorStakingRewards(addr);
        GuardianStakingRewards memory guardianStakingRewards = getGuardianStakingRewards(addr); // TODO consider removing, data in state must be up to date at this point
        return fromMilliOrbs(delegatorStakingRewards.balance.add(guardianStakingRewards.balance));
    }

    function claimStakingRewards(address addr) external override onlyWhenActive {
        (uint256 guardianRewards, uint256 delegatorRewards) = claimStakingRewardsLocally(addr);

        uint256 total = delegatorRewards.add(guardianRewards);

        require(erc20.approve(address(stakingContract), total), "claimStakingRewards: approve failed");

        address[] memory addrs = new address[](1);
        addrs[0] = addr;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = total;
        stakingContract.distributeRewards(total, addrs, amounts);

        emit StakingRewardsClaimed(addr, total);
    }

    function getGuardianStakingRewardsData(address guardian) external override view returns (
        uint256 balance,
        uint256 delegatorRewardsPerToken,
        uint256 lastStakingRewardsPerWeight
    ) {
        GuardianStakingRewards memory rewards = getGuardianStakingRewards(guardian);
        return (fromMilliOrbs(rewards.balance), rewards.delegatorRewardsPerToken, rewards.lastStakingRewardsPerWeight);
    }

    function getDelegatorStakingRewardsData(address delegator) external override view returns (
        uint256 balance,
        uint256 lastDelegatorRewardsPerToken
    ) {
        DelegatorStakingRewards memory rewards = getDelegatorStakingRewards(delegator);
        return (fromMilliOrbs(rewards.balance), rewards.lastDelegatorRewardsPerToken);
    }

    function getStakingRewardsState() public view returns (
        uint96 stakingRewardsPerWeight,
        uint96 unclaimedStakingRewards
    ) {
        (, , uint totalCommitteeWeight) = committeeContract.getCommitteeStats();
        (StakingRewardsState memory _stakingRewardsState,) = _getStakingRewardsState(totalCommitteeWeight, settings);
        stakingRewardsPerWeight = _stakingRewardsState.stakingRewardsPerWeight;
        unclaimedStakingRewards = _stakingRewardsState.unclaimedStakingRewards;
    }

    function getCurrentStakingRewardsRatePercentMille() external override returns (uint256) {
        (, , uint totalCommitteeWeight) = committeeContract.getCommitteeStats();
        return _getAnnualRate(totalCommitteeWeight, settings);
    }

    function setGuardianDelegatorsStakingRewardsPercentMille(uint32 delegatorRewardsPercentMille) external override onlyWhenActive {
        require(delegatorRewardsPercentMille <= PERCENT_MILLIE_BASE, "delegatorRewardsPercentMille must be 100000 at most");
        require(delegatorRewardsPercentMille <= settings.maxDelegatorsStakingRewardsPercentMille, "delegatorRewardsPercentMille must not be larger than maxDelegatorsStakingRewardsPercentMille");
        updateDelegatorStakingRewards(msg.sender);
        _setGuardianDelegatorsStakingRewardsPercentMille(msg.sender, delegatorRewardsPercentMille);
    }

    function getGuardianDelegatorsStakingRewardsPercentMille(address guardian) external override view returns (uint256 delegatorRewardsRatioPercentMille) {
        return _getGuardianDelegatorsStakingRewardsPercentMille(guardian, settings);
    }

    function getStakingRewardsWalletAllocatedTokens() external override view returns (uint256 allocated) {
        (, uint96 unclaimedStakingRewards) = getStakingRewardsState();
        return unclaimedStakingRewards.sub(stakingRewardsWithdrawnFromWallet);
    }

    /*
    * Governance functions
    */

    function migrateRewardsBalance(address addr) external override {
        require(!settings.rewardAllocationActive, "Reward distribution must be deactivated for migration");

        IStakingRewards currentRewardsContract = IStakingRewards(getStakingRewardsContract());
        require(address(currentRewardsContract) != address(this), "New rewards contract is not set");

        (uint256 guardianRewards, uint256 delegatorRewards) = claimStakingRewardsLocally(addr);

        require(erc20.approve(address(currentRewardsContract), guardianRewards.add(delegatorRewards)), "migrateRewardsBalance: approve failed");
        currentRewardsContract.acceptRewardsBalanceMigration(addr, guardianRewards, delegatorRewards);

        emit StakingRewardsBalanceMigrated(addr, guardianRewards, delegatorRewards, address(currentRewardsContract));
    }

    function acceptRewardsBalanceMigration(address addr, uint256 guardianStakingRewards, uint256 delegatorStakingRewards) external override {
        guardiansStakingRewards[addr].balance = guardiansStakingRewards[addr].balance.add(toMilliOrbs(guardianStakingRewards));
        delegatorsStakingRewards[addr].balance = delegatorsStakingRewards[addr].balance.add(toMilliOrbs(delegatorStakingRewards));

        uint orbsTransferAmount = guardianStakingRewards.add(delegatorStakingRewards);
        if (orbsTransferAmount > 0) {
            require(erc20.transferFrom(msg.sender, address(this), orbsTransferAmount), "acceptRewardBalanceMigration: transfer failed");
        }

        emit StakingRewardsBalanceMigrationAccepted(msg.sender, addr, guardianStakingRewards, delegatorStakingRewards);
    }

    function emergencyWithdraw() external override onlyMigrationManager {
        emit EmergencyWithdrawal(msg.sender);
        require(erc20.transfer(msg.sender, erc20.balanceOf(address(this))), "Rewards::emergencyWithdraw - transfer failed (orbs token)");
    }

    function activateRewardDistribution(uint startTime) external override onlyMigrationManager {
        stakingRewardsState.lastAssigned = uint32(startTime);
        settings.rewardAllocationActive = true;

        emit RewardDistributionActivated(startTime);
    }

    function deactivateRewardDistribution() external override onlyMigrationManager {
        require(settings.rewardAllocationActive, "reward distribution is already deactivated");

        updateStakingRewardsState();

        settings.rewardAllocationActive = false;

        emit RewardDistributionDeactivated();
    }

    function setDefaultDelegatorsStakingRewardsPercentMille(uint32 defaultDelegatorsStakingRewardsPercentMille) public override onlyFunctionalManager {
        require(defaultDelegatorsStakingRewardsPercentMille <= PERCENT_MILLIE_BASE, "defaultDelegatorsStakingRewardsPercentMille must not be larger than 100000");
        require(defaultDelegatorsStakingRewardsPercentMille <= settings.maxDelegatorsStakingRewardsPercentMille, "defaultDelegatorsStakingRewardsPercentMille must not be larger than maxDelegatorsStakingRewardsPercentMille");
        settings.defaultDelegatorsStakingRewardsPercentMille = defaultDelegatorsStakingRewardsPercentMille;
        emit DefaultDelegatorsStakingRewardsChanged(defaultDelegatorsStakingRewardsPercentMille);
    }

    function getDefaultDelegatorsStakingRewardsPercentMille() public override view returns (uint32) {
        return settings.defaultDelegatorsStakingRewardsPercentMille;
    }

    function setMaxDelegatorsStakingRewardsPercentMille(uint32 maxDelegatorsStakingRewardsPercentMille) public override onlyFunctionalManager {
        require(maxDelegatorsStakingRewardsPercentMille <= PERCENT_MILLIE_BASE, "maxDelegatorsStakingRewardsPercentMille must not be larger than 100000");
        settings.maxDelegatorsStakingRewardsPercentMille = maxDelegatorsStakingRewardsPercentMille;
        emit MaxDelegatorsStakingRewardsChanged(maxDelegatorsStakingRewardsPercentMille);
    }

    function getMaxDelegatorsStakingRewardsPercentMille() public override view returns (uint32) {
        return settings.maxDelegatorsStakingRewardsPercentMille;
    }

    function setAnnualStakingRewardsRate(uint256 annualRateInPercentMille, uint256 annualCap) external override onlyFunctionalManager {
        updateStakingRewardsState();
        return _setAnnualStakingRewardsRate(annualRateInPercentMille, annualCap);
    }

    function getAnnualStakingRewardsRatePercentMille() external override view returns (uint32) {
        return settings.annualRateInPercentMille;
    }

    function getAnnualStakingRewardsCap() external override view returns (uint256) {
        return fromMilliOrbs(settings.annualCap);
    }

    function getSettings() external override view returns (
        uint annualStakingRewardsCap,
        uint32 annualStakingRewardsRatePercentMille,
        uint32 defaultDelegatorsStakingRewardsPercentMille,
        uint32 maxDelegatorsStakingRewardsPercentMille,
        bool rewardAllocationActive
    ) {
        Settings memory _settings = settings;
        annualStakingRewardsCap = fromMilliOrbs(_settings.annualCap);
        annualStakingRewardsRatePercentMille = _settings.annualRateInPercentMille;
        defaultDelegatorsStakingRewardsPercentMille = _settings.defaultDelegatorsStakingRewardsPercentMille;
        maxDelegatorsStakingRewardsPercentMille = _settings.maxDelegatorsStakingRewardsPercentMille;
        rewardAllocationActive = _settings.rewardAllocationActive;
    }

    /*
    * Private functions
    */

    // Global state

    function _getAnnualRate(uint256 totalCommitteeWeight, Settings memory _settings) private pure returns (uint256) {
        return totalCommitteeWeight == 0 ? 0 : Math.min(uint(_settings.annualRateInPercentMille), fromMilliOrbs(_settings.annualCap).mul(PERCENT_MILLIE_BASE).div(totalCommitteeWeight));
    }

    function calcStakingRewardPerWeightDelta(uint256 totalCommitteeWeight, uint duration, Settings memory _settings) private pure returns (uint256 stakingRewardsPerTokenDelta) {
        stakingRewardsPerTokenDelta = 0;

        if (totalCommitteeWeight > 0) {
            uint annualRateInPercentMille = _getAnnualRate(totalCommitteeWeight, _settings);
            stakingRewardsPerTokenDelta = annualRateInPercentMille.mul(TOKEN_BASE).mul(duration).div(PERCENT_MILLIE_BASE.mul(365 days));
        }
    }

    function _getStakingRewardsState(uint256 totalCommitteeWeight, Settings memory _settings) private view returns (StakingRewardsState memory _stakingRewardsState, uint256 allocatedRewards) {
        _stakingRewardsState = stakingRewardsState;
        if (_settings.rewardAllocationActive) {
            uint delta = calcStakingRewardPerWeightDelta(totalCommitteeWeight, block.timestamp.sub(stakingRewardsState.lastAssigned), _settings);
            _stakingRewardsState.stakingRewardsPerWeight = uint96(stakingRewardsState.stakingRewardsPerWeight.add(delta));
            _stakingRewardsState.lastAssigned = uint32(block.timestamp);
            allocatedRewards = delta.mul(totalCommitteeWeight).div(TOKEN_BASE);
            _stakingRewardsState.unclaimedStakingRewards = uint96(_stakingRewardsState.unclaimedStakingRewards.add(allocatedRewards));
        }
    }

    function _updateStakingRewardsState(uint256 totalCommitteeWeight, Settings memory _settings) private returns (StakingRewardsState memory _stakingRewardsState) {
        if (!_settings.rewardAllocationActive) {
            return stakingRewardsState;
        }

        uint allocatedRewards;
        (_stakingRewardsState, allocatedRewards) = _getStakingRewardsState(totalCommitteeWeight, _settings);
        stakingRewardsState = _stakingRewardsState;
        emit StakingRewardAllocated(allocatedRewards, _stakingRewardsState.stakingRewardsPerWeight);
    }

    function updateStakingRewardsState() private returns (StakingRewardsState memory _stakingRewardsState) {
        (, , uint totalCommitteeWeight) = committeeContract.getCommitteeStats();
        return _updateStakingRewardsState(totalCommitteeWeight, settings);
    }

    // Guardian state

    function _getGuardianStakingRewards(address guardian, bool inCommittee, uint256 guardianWeight, uint256 guardianDelegatedStake, StakingRewardsState memory _stakingRewardsState, Settings memory _settings) private view returns (GuardianStakingRewards memory guardianStakingRewards, uint256 rewardsAdded) {
        guardianStakingRewards = guardiansStakingRewards[guardian];

        if (inCommittee) {
            uint256 totalRewards = _stakingRewardsState.stakingRewardsPerWeight
                .sub(guardianStakingRewards.lastStakingRewardsPerWeight)
                .mul(guardianWeight);

            uint256 delegatorRewardsRatioPercentMille = _getGuardianDelegatorsStakingRewardsPercentMille(guardian, _settings);

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
            guardianStakingRewards.balance = guardianStakingRewards.balance.add(toMilliOrbs(guardianRewards));

            rewardsAdded = guardianRewards;
        }

        guardianStakingRewards.lastStakingRewardsPerWeight = _stakingRewardsState.stakingRewardsPerWeight;
    }

    function getGuardianStakingRewards(address guardian) private view returns (GuardianStakingRewards memory guardianStakingRewards) {
        Settings memory _settings = settings;

        (bool inCommittee, uint256 guardianWeight, ,uint256 totalCommitteeWeight) = committeeContract.getMemberInfo(guardian);
        uint256 guardianDelegatedStake = delegationsContract.getDelegatedStake(guardian);

        (StakingRewardsState memory _stakingRewardsState,) = _getStakingRewardsState(totalCommitteeWeight, _settings);
        (guardianStakingRewards,) = _getGuardianStakingRewards(guardian, inCommittee, guardianWeight, guardianDelegatedStake, _stakingRewardsState, _settings);
    }

    function _updateGuardianStakingRewards(address guardian, bool inCommittee, uint256 guardianWeight, uint256 guardianDelegatedStake, StakingRewardsState memory _stakingRewardsState, Settings memory _settings) private returns (GuardianStakingRewards memory guardianStakingRewards) {
        uint256 guardianStakingRewardsAdded;
        (guardianStakingRewards, guardianStakingRewardsAdded) = _getGuardianStakingRewards(guardian, inCommittee, guardianWeight, guardianDelegatedStake, _stakingRewardsState, _settings);
        guardiansStakingRewards[guardian] = guardianStakingRewards;
        emit GuardianStakingRewardsAssigned(guardian, guardianStakingRewardsAdded, guardianStakingRewards.delegatorRewardsPerToken);
    }

    function updateGuardianStakingRewards(address guardian, StakingRewardsState memory _stakingRewardsState, Settings memory _settings) private returns (GuardianStakingRewards memory guardianStakingRewards) {
        (bool inCommittee, uint256 guardianWeight,,) = committeeContract.getMemberInfo(guardian);
        return _updateGuardianStakingRewards(guardian, inCommittee, guardianWeight, delegationsContract.getDelegatedStake(guardian), _stakingRewardsState, _settings);
    }

    // Delegator state

    function _getDelegatorStakingRewards(address delegator, uint256 delegatorStake, GuardianStakingRewards memory guardianStakingRewards) private view returns (DelegatorStakingRewards memory delegatorStakingRewards, uint256 delegatorRewardsAdded) {
        delegatorStakingRewards = delegatorsStakingRewards[delegator];

        uint256 amount = guardianStakingRewards.delegatorRewardsPerToken
            .sub(delegatorStakingRewards.lastDelegatorRewardsPerToken)
            .mul(delegatorStake)
            .div(TOKEN_BASE);

        delegatorStakingRewards.balance = delegatorStakingRewards.balance.add(toMilliOrbs(amount));
        delegatorStakingRewards.lastDelegatorRewardsPerToken = guardianStakingRewards.delegatorRewardsPerToken;

        delegatorRewardsAdded = amount;
    }

    function getDelegatorStakingRewards(address delegator) private view returns (DelegatorStakingRewards memory delegatorStakingRewards) {
        (address guardian, uint256 delegatorStake) = delegationsContract.getDelegationInfo(delegator);
        GuardianStakingRewards memory guardianStakingRewards = getGuardianStakingRewards(guardian);

        (delegatorStakingRewards,) = _getDelegatorStakingRewards(delegator, delegatorStake, guardianStakingRewards);
    }

    function _updateDelegatorStakingRewards(address delegator, uint256 delegatorStake, GuardianStakingRewards memory guardianStakingRewards) private {
        uint256 delegatorStakingRewardsAdded;
        (delegatorsStakingRewards[delegator], delegatorStakingRewardsAdded) = _getDelegatorStakingRewards(delegator, delegatorStake, guardianStakingRewards);

        emit StakingRewardsAssigned(delegator, delegatorStakingRewardsAdded);
    }

    function updateDelegatorStakingRewards(address delegator) private {
        Settings memory _settings = settings;

        (, , uint totalCommitteeWeight) = committeeContract.getCommitteeStats();
        StakingRewardsState memory _stakingRewardsState = _updateStakingRewardsState(totalCommitteeWeight, _settings);

        (address guardian, uint delegatorStake) = delegationsContract.getDelegationInfo(delegator);
        GuardianStakingRewards memory guardianRewards = updateGuardianStakingRewards(guardian, _stakingRewardsState, _settings);

        _updateDelegatorStakingRewards(delegator, delegatorStake, guardianRewards);
    }

    // Guardian settings

    function _getGuardianDelegatorsStakingRewardsPercentMille(address guardian, Settings memory _settings) private view returns (uint256 delegatorRewardsRatioPercentMille) {
        GuardianRewardSettings memory guardianSettings = guardiansRewardSettings[guardian];
        delegatorRewardsRatioPercentMille =  guardianSettings.overrideDefault ? guardianSettings.delegatorsStakingRewardsPercentMille : _settings.defaultDelegatorsStakingRewardsPercentMille;
        return Math.min(delegatorRewardsRatioPercentMille, _settings.maxDelegatorsStakingRewardsPercentMille);
    }

    function migrateGuardiansSettings(IStakingRewards previousRewardsContract, address[] memory guardiansToMigrate) private {
        for (uint i = 0; i < guardiansToMigrate.length; i++) {
            _setGuardianDelegatorsStakingRewardsPercentMille(guardiansToMigrate[i], uint32(previousRewardsContract.getGuardianDelegatorsStakingRewardsPercentMille(guardiansToMigrate[i])));
        }
    }

    // Governance and misc.

    function _setAnnualStakingRewardsRate(uint256 annualRateInPercentMille, uint256 annualCap) private {
        Settings memory _settings = settings;
        _settings.annualRateInPercentMille = uint32(annualRateInPercentMille);
        _settings.annualCap = toMilliOrbs(annualCap);
        settings = _settings;

        emit AnnualStakingRewardsRateChanged(annualRateInPercentMille, annualCap);
    }

    function _setGuardianDelegatorsStakingRewardsPercentMille(address guardian, uint32 delegatorRewardsPercentMille) private {
        guardiansRewardSettings[guardian] = GuardianRewardSettings({
            overrideDefault: true,
            delegatorsStakingRewardsPercentMille: delegatorRewardsPercentMille
            });

        emit GuardianDelegatorsStakingRewardsPercentMilleUpdated(guardian, delegatorRewardsPercentMille);
    }

    function claimStakingRewardsLocally(address addr) private returns (uint256 guardianRewards, uint256 delegatorRewards) {
        updateDelegatorStakingRewards(addr);

        guardianRewards = fromMilliOrbs(guardiansStakingRewards[addr].balance);
        guardiansStakingRewards[addr].balance = 0;

        delegatorRewards = fromMilliOrbs(delegatorsStakingRewards[addr].balance);
        delegatorsStakingRewards[addr].balance = 0;

        uint256 total = delegatorRewards.add(guardianRewards);

        StakingRewardsState memory _stakingRewardsState = stakingRewardsState;
        uint256 _stakingRewardsWithdrawnFromWallet = stakingRewardsWithdrawnFromWallet;
        uint256 allocated = _stakingRewardsState.unclaimedStakingRewards.sub(_stakingRewardsWithdrawnFromWallet);
        if (allocated > 0) {
            stakingRewardsWallet.withdraw(allocated);
            _stakingRewardsWithdrawnFromWallet = _stakingRewardsWithdrawnFromWallet.add(allocated);
        }

        stakingRewardsWithdrawnFromWallet = _stakingRewardsWithdrawnFromWallet.sub(total);
        stakingRewardsState.unclaimedStakingRewards = _stakingRewardsState.unclaimedStakingRewards.sub(total);
    }

    function toMilliOrbs(uint256 v) private pure returns (uint48) {
        return uint48(v / TOKEN_GRANULARITY);
    }

    function fromMilliOrbs(uint48 v) private pure returns (uint256) {
        return uint256(v) * TOKEN_GRANULARITY;
    }

    /*
     * Contracts topology / registry interface
     */

    ICommittee committeeContract;
    IDelegations delegationsContract;
    IProtocolWallet stakingRewardsWallet;
    IStakingContract stakingContract;
    function refreshContracts() external override {
        committeeContract = ICommittee(getCommitteeContract());
        delegationsContract = IDelegations(getDelegationsContract());
        stakingRewardsWallet = IProtocolWallet(getStakingRewardsWallet());
        stakingContract = IStakingContract(getStakingContract());
    }
}
