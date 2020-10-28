// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./SafeMath96.sol";
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
    using SafeMath96 for uint96;

    uint256 constant PERCENT_MILLIE_BASE = 100000;
    uint256 constant TOKEN_BASE = 1e18;

    struct Settings {
        uint96 annualCap;
        uint32 annualRateInPercentMille;
        uint32 defaultDelegatorsStakingRewardsPercentMille;
        uint32 maxDelegatorsStakingRewardsPercentMille;
        bool rewardAllocationActive;
    }
    Settings settings;

    IERC20 public token;

    struct StakingRewardsState {
        uint96 stakingRewardsPerWeight;
        uint96 unclaimedStakingRewards;
        uint32 lastAssigned;
    }
    StakingRewardsState public stakingRewardsState;

    uint256 public stakingRewardsContractBalance;

    struct GuardianStakingRewards {
        uint96 delegatorRewardsPerToken;
        uint96 lastStakingRewardsPerWeight;
        uint96 balance;
        uint96 claimed;
    }
    mapping(address => GuardianStakingRewards) public guardiansStakingRewards;

    struct GuardianRewardSettings {
        uint32 delegatorsStakingRewardsPercentMille;
        bool overrideDefault;
    }
    mapping(address => GuardianRewardSettings) public guardiansRewardSettings;

    struct DelegatorStakingRewards {
        uint96 balance;
        uint96 lastDelegatorRewardsPerToken;
        uint96 claimed;
    }
    mapping(address => DelegatorStakingRewards) public delegatorsStakingRewards;

    constructor(
        IContractRegistry _contractRegistry,
        address _registryAdmin,
        IERC20 _token,
        uint32 annualRateInPercentMille,
        uint96 annualCap,
        uint32 defaultDelegatorsStakingRewardsPercentMille,
        uint32 maxDelegatorsStakingRewardsPercentMille,
        IStakingRewards previousRewardsContract,
        address[] memory guardiansToMigrate
    ) ManagedContract(_contractRegistry, _registryAdmin) public {
        require(address(_token) != address(0), "token must not be 0");

        _setAnnualStakingRewardsRate(annualRateInPercentMille, annualCap);
        setMaxDelegatorsStakingRewardsPercentMille(maxDelegatorsStakingRewardsPercentMille);
        setDefaultDelegatorsStakingRewardsPercentMille(defaultDelegatorsStakingRewardsPercentMille);

        token = _token;

        if (address(previousRewardsContract) != address(0)) {
            migrateGuardiansSettings(previousRewardsContract, guardiansToMigrate);
        }
    }

    modifier onlyCommitteeContract() {
        require(msg.sender == address(committeeContract), "caller is not the elections contract");

        _;
    }

    modifier onlyDelegationsContract() {
        require(msg.sender == address(delegationsContract), "caller is not the delegations contract");

        _;
    }

    /*
    * External functions
    */

    function committeeMembershipWillChange(address guardian, uint256 weight, uint256 totalCommitteeWeight, bool inCommittee, bool inCommitteeAfter) external override onlyWhenActive onlyCommitteeContract {
        uint256 delegatedStake = delegationsContract.getDelegatedStake(guardian);

        Settings memory _settings = settings;
        StakingRewardsState memory _stakingRewardsState = _updateStakingRewardsState(totalCommitteeWeight, _settings);
        _updateGuardianStakingRewards(guardian, inCommittee, inCommitteeAfter, weight, delegatedStake, _stakingRewardsState, _settings);
    }

    function delegationWillChange(address guardian, uint256 guardianDelegatedStake, address delegator, uint256 delegatorStake, address nextGuardian, uint256 nextGuardianDelegatedStake) external override onlyWhenActive onlyDelegationsContract {
        Settings memory _settings = settings;
        (bool inCommittee, uint256 weight, , uint256 totalCommitteeWeight) = committeeContract.getMemberInfo(guardian);

        StakingRewardsState memory _stakingRewardsState = _updateStakingRewardsState(totalCommitteeWeight, _settings);
        GuardianStakingRewards memory guardianStakingRewards = _updateGuardianStakingRewards(guardian, inCommittee, inCommittee, weight, guardianDelegatedStake, _stakingRewardsState, _settings);
        _updateDelegatorStakingRewards(delegator, delegatorStake, guardian, guardianStakingRewards);

        if (nextGuardian != guardian) {
            (inCommittee, weight, , totalCommitteeWeight) = committeeContract.getMemberInfo(nextGuardian);
            GuardianStakingRewards memory nextGuardianStakingRewards = _updateGuardianStakingRewards(nextGuardian, inCommittee, inCommittee, weight, nextGuardianDelegatedStake, _stakingRewardsState, _settings);
            delegatorsStakingRewards[delegator].lastDelegatorRewardsPerToken = nextGuardianStakingRewards.delegatorRewardsPerToken;
        }
    }

    function getStakingRewardsBalance(address addr) external override view returns (uint256 delegatorStakingRewardsBalance, uint256 guardianStakingRewardsBalance) {
        (DelegatorStakingRewards memory delegatorStakingRewards,,) = getDelegatorStakingRewards(addr, block.timestamp);
        (GuardianStakingRewards memory guardianStakingRewards,,) = getGuardianStakingRewards(addr, block.timestamp); // TODO consider removing, data in state must be up to date at this point
        return (delegatorStakingRewards.balance, guardianStakingRewards.balance);
    }

    function claimStakingRewards(address addr) external override onlyWhenActive {
        (uint256 guardianRewards, uint256 delegatorRewards) = claimStakingRewardsLocally(addr);
        uint256 total = delegatorRewards.add(guardianRewards);
        if (total == 0) {
            return;
        }

        uint96 claimedGuardianRewards = guardiansStakingRewards[addr].claimed.add(guardianRewards);
        guardiansStakingRewards[addr].claimed = claimedGuardianRewards;
        uint96 claimedDelegatorRewards = delegatorsStakingRewards[addr].claimed.add(delegatorRewards);
        delegatorsStakingRewards[addr].claimed = claimedDelegatorRewards;

        require(token.approve(address(stakingContract), total), "claimStakingRewards: approve failed");

        address[] memory addrs = new address[](1);
        addrs[0] = addr;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = total;
        stakingContract.distributeRewards(total, addrs, amounts);

        emit StakingRewardsClaimed(addr, delegatorRewards, guardianRewards, claimedDelegatorRewards, claimedGuardianRewards);
    }

    function getGuardianStakingRewardsData(address guardian) external override view returns (
        uint256 balance,
        uint256 claimed,
        uint256 delegatorRewardsPerToken,
        uint256 delegatorRewardsPerTokenDelta,
        uint256 lastStakingRewardsPerWeight,
        uint256 stakingRewardsPerWeightDelta
    ) {
        (GuardianStakingRewards memory rewards, uint256 _stakingRewardsPerWeightDelta, uint256 _delegatorRewardsPerTokenDelta) = getGuardianStakingRewards(guardian, block.timestamp);
        return (rewards.balance, rewards.claimed, rewards.delegatorRewardsPerToken, _delegatorRewardsPerTokenDelta, rewards.lastStakingRewardsPerWeight, _stakingRewardsPerWeightDelta);
    }

    function getDelegatorStakingRewardsData(address delegator) external override view returns (
        uint256 balance,
        uint256 claimed,
        address guardian,
        uint256 lastDelegatorRewardsPerToken,
        uint256 delegatorRewardsPerTokenDelta
    ) {
        (DelegatorStakingRewards memory rewards, address _guardian, uint256 _delegatorRewardsPerTokenDelta) = getDelegatorStakingRewards(delegator, block.timestamp);
        return (rewards.balance, rewards.claimed, _guardian, rewards.lastDelegatorRewardsPerToken, _delegatorRewardsPerTokenDelta);
    }

    function estimateFutureRewards(address addr, uint256 duration) external override view returns (uint256 estimatedDelegatorStakingRewards, uint256 estimatedGuardianStakingRewards) {
        (GuardianStakingRewards memory guardianRewardsNow,,) = getGuardianStakingRewards(addr, block.timestamp);
        (DelegatorStakingRewards memory delegatorRewardsNow,,) = getDelegatorStakingRewards(addr, block.timestamp);
        (GuardianStakingRewards memory guardianRewardsFuture,,) = getGuardianStakingRewards(addr, block.timestamp.add(duration));
        (DelegatorStakingRewards memory delegatorRewardsFuture,,) = getDelegatorStakingRewards(addr, block.timestamp.add(duration));

        estimatedDelegatorStakingRewards = delegatorRewardsFuture.balance.sub(delegatorRewardsNow.balance);
        estimatedGuardianStakingRewards = guardianRewardsFuture.balance.sub(guardianRewardsNow.balance);
    }

    function getStakingRewardsState() public override view returns (
        uint96 stakingRewardsPerWeight,
        uint96 unclaimedStakingRewards
    ) {
        (, , uint totalCommitteeWeight) = committeeContract.getCommitteeStats();
        (StakingRewardsState memory _stakingRewardsState,) = _getStakingRewardsState(totalCommitteeWeight, block.timestamp, settings);
        stakingRewardsPerWeight = _stakingRewardsState.stakingRewardsPerWeight;
        unclaimedStakingRewards = _stakingRewardsState.unclaimedStakingRewards;
    }

    function getCurrentStakingRewardsRatePercentMille() external override view returns (uint256 annualRate) {
        (, , uint totalCommitteeWeight) = committeeContract.getCommitteeStats();
        annualRate = _getAnnualRewardPerWeight(totalCommitteeWeight, settings).mul(PERCENT_MILLIE_BASE).div(TOKEN_BASE);
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
        return uint256(unclaimedStakingRewards).sub(stakingRewardsContractBalance);
    }

    /*
    * Governance functions
    */

    function migrateRewardsBalance(address addr) external override {
        require(!settings.rewardAllocationActive, "Reward distribution must be deactivated for migration");

        IStakingRewards currentRewardsContract = IStakingRewards(getStakingRewardsContract());
        require(address(currentRewardsContract) != address(this), "New rewards contract is not set");

        (uint256 guardianRewards, uint256 delegatorRewards) = claimStakingRewardsLocally(addr);

        require(token.approve(address(currentRewardsContract), guardianRewards.add(delegatorRewards)), "migrateRewardsBalance: approve failed");
        currentRewardsContract.acceptRewardsBalanceMigration(addr, guardianRewards, delegatorRewards);

        emit StakingRewardsBalanceMigrated(addr, guardianRewards, delegatorRewards, address(currentRewardsContract));
    }

    function acceptRewardsBalanceMigration(address addr, uint256 guardianStakingRewards, uint256 delegatorStakingRewards) external override {
        guardiansStakingRewards[addr].balance = guardiansStakingRewards[addr].balance.add(guardianStakingRewards);
        delegatorsStakingRewards[addr].balance = delegatorsStakingRewards[addr].balance.add(delegatorStakingRewards);

        uint orbsTransferAmount = guardianStakingRewards.add(delegatorStakingRewards);
        if (orbsTransferAmount > 0) {
            require(token.transferFrom(msg.sender, address(this), orbsTransferAmount), "acceptRewardBalanceMigration: transfer failed");
        }

        emit StakingRewardsBalanceMigrationAccepted(msg.sender, addr, guardianStakingRewards, delegatorStakingRewards);
    }

    function emergencyWithdraw(address erc20) external override onlyMigrationManager {
        IERC20 _token = IERC20(erc20);
        emit EmergencyWithdrawal(msg.sender, address(_token));
        require(_token.transfer(msg.sender, _token.balanceOf(address(this))), "StakingRewards::emergencyWithdraw - transfer failed");
    }

    function activateRewardDistribution(uint startTime) external override onlyMigrationManager {
        require(!settings.rewardAllocationActive, "reward distribution is already activated");

        stakingRewardsState.lastAssigned = uint32(startTime);
        settings.rewardAllocationActive = true;

        emit RewardDistributionActivated(startTime);
    }

    function deactivateRewardDistribution() external override onlyMigrationManager {
        require(settings.rewardAllocationActive, "reward distribution is already deactivated");

        StakingRewardsState memory _stakingRewardsState = updateStakingRewardsState();

        settings.rewardAllocationActive = false;

        withdrawRewardsWalletAllocatedTokens(_stakingRewardsState);

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

    function setAnnualStakingRewardsRate(uint32 annualRateInPercentMille, uint96 annualCap) external override onlyFunctionalManager {
        updateStakingRewardsState();
        return _setAnnualStakingRewardsRate(annualRateInPercentMille, annualCap);
    }

    function getAnnualStakingRewardsRatePercentMille() external override view returns (uint32) {
        return settings.annualRateInPercentMille;
    }

    function getAnnualStakingRewardsCap() external override view returns (uint256) {
        return settings.annualCap;
    }

    function isRewardAllocationActive() external override view returns (bool) {
        return settings.rewardAllocationActive;
    }

    function getSettings() external override view returns (
        uint annualStakingRewardsCap,
        uint32 annualStakingRewardsRatePercentMille,
        uint32 defaultDelegatorsStakingRewardsPercentMille,
        uint32 maxDelegatorsStakingRewardsPercentMille,
        bool rewardAllocationActive
    ) {
        Settings memory _settings = settings;
        annualStakingRewardsCap = _settings.annualCap;
        annualStakingRewardsRatePercentMille = _settings.annualRateInPercentMille;
        defaultDelegatorsStakingRewardsPercentMille = _settings.defaultDelegatorsStakingRewardsPercentMille;
        maxDelegatorsStakingRewardsPercentMille = _settings.maxDelegatorsStakingRewardsPercentMille;
        rewardAllocationActive = _settings.rewardAllocationActive;
    }

    /*
    * Private functions
    */

    // Global state

    function _getAnnualRewardPerWeight(uint256 totalCommitteeWeight, Settings memory _settings) private pure returns (uint256) {
        return totalCommitteeWeight == 0 ? 0 : Math.min(uint256(_settings.annualRateInPercentMille).mul(TOKEN_BASE).div(PERCENT_MILLIE_BASE), uint256(_settings.annualCap).mul(TOKEN_BASE).div(totalCommitteeWeight));
    }

    function calcStakingRewardPerWeightDelta(uint256 totalCommitteeWeight, uint duration, Settings memory _settings) private pure returns (uint256 stakingRewardsPerWeightDelta) {
        stakingRewardsPerWeightDelta = 0;

        if (totalCommitteeWeight > 0) {
            uint annualRewardPerWeight = _getAnnualRewardPerWeight(totalCommitteeWeight, _settings);
            stakingRewardsPerWeightDelta = annualRewardPerWeight.mul(duration).div(365 days);
        }
    }

    function _getStakingRewardsState(uint256 totalCommitteeWeight, uint256 currentTime, Settings memory _settings) private view returns (StakingRewardsState memory _stakingRewardsState, uint256 allocatedRewards) {
        _stakingRewardsState = stakingRewardsState;
        if (_settings.rewardAllocationActive) {
            uint delta = calcStakingRewardPerWeightDelta(totalCommitteeWeight, currentTime.sub(stakingRewardsState.lastAssigned), _settings);
            _stakingRewardsState.stakingRewardsPerWeight = stakingRewardsState.stakingRewardsPerWeight.add(delta);
            _stakingRewardsState.lastAssigned = uint32(currentTime);
            allocatedRewards = delta.mul(totalCommitteeWeight).div(TOKEN_BASE);
            _stakingRewardsState.unclaimedStakingRewards = _stakingRewardsState.unclaimedStakingRewards.add(allocatedRewards);
        }
    }

    function _updateStakingRewardsState(uint256 totalCommitteeWeight, Settings memory _settings) private returns (StakingRewardsState memory _stakingRewardsState) {
        if (!_settings.rewardAllocationActive) {
            return stakingRewardsState;
        }

        uint allocatedRewards;
        (_stakingRewardsState, allocatedRewards) = _getStakingRewardsState(totalCommitteeWeight, block.timestamp, _settings);
        stakingRewardsState = _stakingRewardsState;
        emit StakingRewardsAllocated(allocatedRewards, _stakingRewardsState.stakingRewardsPerWeight);
    }

    function updateStakingRewardsState() private returns (StakingRewardsState memory _stakingRewardsState) {
        (, , uint totalCommitteeWeight) = committeeContract.getCommitteeStats();
        return _updateStakingRewardsState(totalCommitteeWeight, settings);
    }

    // Guardian state

    function _getGuardianStakingRewards(address guardian, bool inCommittee, bool inCommitteeAfter, uint256 guardianWeight, uint256 guardianDelegatedStake, StakingRewardsState memory _stakingRewardsState, Settings memory _settings) private view returns (GuardianStakingRewards memory guardianStakingRewards, uint256 rewardsAdded, uint256 stakingRewardsPerWeightDelta, uint256 delegatorRewardsPerTokenDelta) {
        guardianStakingRewards = guardiansStakingRewards[guardian];

        if (inCommittee) {
            stakingRewardsPerWeightDelta = uint256(_stakingRewardsState.stakingRewardsPerWeight).sub(guardianStakingRewards.lastStakingRewardsPerWeight);
            uint256 totalRewards = stakingRewardsPerWeightDelta.mul(guardianWeight);

            uint256 delegatorRewardsRatioPercentMille = _getGuardianDelegatorsStakingRewardsPercentMille(guardian, _settings);

            delegatorRewardsPerTokenDelta = guardianDelegatedStake == 0 ? 0 : totalRewards
                .div(guardianDelegatedStake)
                .mul(delegatorRewardsRatioPercentMille)
                .div(PERCENT_MILLIE_BASE);

            uint256 guardianCutPercentMille = PERCENT_MILLIE_BASE.sub(delegatorRewardsRatioPercentMille);

            rewardsAdded = totalRewards
                    .mul(guardianCutPercentMille)
                    .div(PERCENT_MILLIE_BASE)
                    .div(TOKEN_BASE);

            guardianStakingRewards.delegatorRewardsPerToken = guardianStakingRewards.delegatorRewardsPerToken.add(delegatorRewardsPerTokenDelta);
            guardianStakingRewards.balance = guardianStakingRewards.balance.add(rewardsAdded);
        }

        guardianStakingRewards.lastStakingRewardsPerWeight = inCommitteeAfter ? _stakingRewardsState.stakingRewardsPerWeight : 0;
    }

    function getGuardianStakingRewards(address guardian, uint256 currentTime) private view returns (GuardianStakingRewards memory guardianStakingRewards, uint256 stakingRewardsPerWeightDelta, uint256 delegatorRewardsPerTokenDelta) {
        Settings memory _settings = settings;

        (bool inCommittee, uint256 guardianWeight, ,uint256 totalCommitteeWeight) = committeeContract.getMemberInfo(guardian);
        uint256 guardianDelegatedStake = delegationsContract.getDelegatedStake(guardian);

        (StakingRewardsState memory _stakingRewardsState,) = _getStakingRewardsState(totalCommitteeWeight, currentTime, _settings);
        (guardianStakingRewards,,stakingRewardsPerWeightDelta,delegatorRewardsPerTokenDelta) = _getGuardianStakingRewards(guardian, inCommittee, inCommittee, guardianWeight, guardianDelegatedStake, _stakingRewardsState, _settings);
    }

    function _updateGuardianStakingRewards(address guardian, bool inCommittee, bool inCommitteeAfter, uint256 guardianWeight, uint256 guardianDelegatedStake, StakingRewardsState memory _stakingRewardsState, Settings memory _settings) private returns (GuardianStakingRewards memory guardianStakingRewards) {
        uint256 guardianStakingRewardsAdded;
        uint256 stakingRewardsPerWeightDelta;
        uint256 delegatorRewardsPerTokenDelta;
        (guardianStakingRewards, guardianStakingRewardsAdded, stakingRewardsPerWeightDelta, delegatorRewardsPerTokenDelta) = _getGuardianStakingRewards(guardian, inCommittee, inCommitteeAfter, guardianWeight, guardianDelegatedStake, _stakingRewardsState, _settings);
        guardiansStakingRewards[guardian] = guardianStakingRewards;
        emit GuardianStakingRewardsAssigned(guardian, guardianStakingRewardsAdded, guardianStakingRewards.claimed.add(guardianStakingRewards.balance), guardianStakingRewards.delegatorRewardsPerToken, delegatorRewardsPerTokenDelta, _stakingRewardsState.stakingRewardsPerWeight, stakingRewardsPerWeightDelta);
    }

    function updateGuardianStakingRewards(address guardian, StakingRewardsState memory _stakingRewardsState, Settings memory _settings) private returns (GuardianStakingRewards memory guardianStakingRewards) {
        (bool inCommittee, uint256 guardianWeight,,) = committeeContract.getMemberInfo(guardian);
        return _updateGuardianStakingRewards(guardian, inCommittee, inCommittee, guardianWeight, delegationsContract.getDelegatedStake(guardian), _stakingRewardsState, _settings);
    }

    // Delegator state

    function _getDelegatorStakingRewards(address delegator, uint256 delegatorStake, GuardianStakingRewards memory guardianStakingRewards) private view returns (DelegatorStakingRewards memory delegatorStakingRewards, uint256 delegatorRewardsAdded, uint256 delegatorRewardsPerTokenDelta) {
        delegatorStakingRewards = delegatorsStakingRewards[delegator];

        delegatorRewardsPerTokenDelta = uint256(guardianStakingRewards.delegatorRewardsPerToken)
            .sub(delegatorStakingRewards.lastDelegatorRewardsPerToken);
        delegatorRewardsAdded = delegatorRewardsPerTokenDelta
            .mul(delegatorStake)
            .div(TOKEN_BASE);

        delegatorStakingRewards.balance = delegatorStakingRewards.balance.add(delegatorRewardsAdded);
        delegatorStakingRewards.lastDelegatorRewardsPerToken = guardianStakingRewards.delegatorRewardsPerToken;
    }

    function getDelegatorStakingRewards(address delegator, uint256 currentTime) private view returns (DelegatorStakingRewards memory delegatorStakingRewards, address guardian, uint256 delegatorStakingRewardsPerTokenDelta) {
        uint256 delegatorStake;
        (guardian, delegatorStake) = delegationsContract.getDelegationInfo(delegator);
        (GuardianStakingRewards memory guardianStakingRewards,,) = getGuardianStakingRewards(guardian, currentTime);

        (delegatorStakingRewards,,delegatorStakingRewardsPerTokenDelta) = _getDelegatorStakingRewards(delegator, delegatorStake, guardianStakingRewards);
    }

    function _updateDelegatorStakingRewards(address delegator, uint256 delegatorStake, address guardian, GuardianStakingRewards memory guardianStakingRewards) private {
        uint256 delegatorStakingRewardsAdded;
        uint256 delegatorRewardsPerTokenDelta;
        DelegatorStakingRewards memory delegatorStakingRewards;
        (delegatorStakingRewards, delegatorStakingRewardsAdded, delegatorRewardsPerTokenDelta) = _getDelegatorStakingRewards(delegator, delegatorStake, guardianStakingRewards);
        delegatorsStakingRewards[delegator] = delegatorStakingRewards;

        emit DelegatorStakingRewardsAssigned(delegator, delegatorStakingRewardsAdded, delegatorStakingRewards.claimed.add(delegatorStakingRewards.balance), guardian, guardianStakingRewards.delegatorRewardsPerToken, delegatorRewardsPerTokenDelta);
    }

    function updateDelegatorStakingRewards(address delegator) private {
        Settings memory _settings = settings;

        (, , uint totalCommitteeWeight) = committeeContract.getCommitteeStats();
        StakingRewardsState memory _stakingRewardsState = _updateStakingRewardsState(totalCommitteeWeight, _settings);

        (address guardian, uint delegatorStake) = delegationsContract.getDelegationInfo(delegator);
        GuardianStakingRewards memory guardianRewards = updateGuardianStakingRewards(guardian, _stakingRewardsState, _settings);

        _updateDelegatorStakingRewards(delegator, delegatorStake, guardian, guardianRewards);
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

    function _setAnnualStakingRewardsRate(uint32 annualRateInPercentMille, uint96 annualCap) private {
        Settings memory _settings = settings;
        _settings.annualRateInPercentMille = annualRateInPercentMille;
        _settings.annualCap = annualCap;
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

        guardianRewards = guardiansStakingRewards[addr].balance;
        guardiansStakingRewards[addr].balance = 0;

        delegatorRewards = delegatorsStakingRewards[addr].balance;
        delegatorsStakingRewards[addr].balance = 0;

        uint256 total = delegatorRewards.add(guardianRewards);

        StakingRewardsState memory _stakingRewardsState = stakingRewardsState;

        uint256 _stakingRewardsContractBalance = stakingRewardsContractBalance;
        if (total > _stakingRewardsContractBalance) {
            _stakingRewardsContractBalance = withdrawRewardsWalletAllocatedTokens(_stakingRewardsState);
        }

        stakingRewardsContractBalance = _stakingRewardsContractBalance.sub(total);
        stakingRewardsState.unclaimedStakingRewards = _stakingRewardsState.unclaimedStakingRewards.sub(total);
    }

    function withdrawRewardsWalletAllocatedTokens(StakingRewardsState memory _stakingRewardsState) private returns (uint256 _stakingRewardsContractBalance){
        _stakingRewardsContractBalance = stakingRewardsContractBalance;
        uint256 allocated = _stakingRewardsState.unclaimedStakingRewards.sub(_stakingRewardsContractBalance);
        stakingRewardsWallet.withdraw(allocated);
        _stakingRewardsContractBalance = _stakingRewardsContractBalance.add(allocated);
        stakingRewardsContractBalance = _stakingRewardsContractBalance;
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
