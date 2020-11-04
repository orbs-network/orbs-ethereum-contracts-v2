// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./SafeMath96.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./spec_interfaces/ICommittee.sol";
import "./spec_interfaces/IProtocolWallet.sol";
import "./spec_interfaces/IStakingRewards.sol";
import "./spec_interfaces/IDelegations.sol";
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

    /// Constructor
    /// @dev the constructor does not migrate reward balances from the previous rewards contract
    /// @param _contractRegistry is the contract registry address
    /// @param _registryAdmin is the registry admin address
    /// @param _token is the token used for staking rewards
    /// @param annualRateInPercentMille is the annual rate in percent-mille
    /// @param annualCap is the annual staking rewards cap
    /// @param defaultDelegatorsStakingRewardsPercentMille is the default delegators portion in percent-mille(0 - maxDelegatorsStakingRewardsPercentMille)
    /// @param maxDelegatorsStakingRewardsPercentMille is the maximum delegators portion in percent-mille(0 - 100,000)
    /// @param previousRewardsContract is the previous rewards contract address used for migration of guardians settings. address(0) indicates no guardian settings to migrate
    /// @param guardiansToMigrate is a list of guardian addresses to migrate their rewards settings
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

    /// Returns the current reward balance of the given address.
    /// @dev calculates the up to date balances (differ from the state)
    /// @param addr is the address to query
    /// @return delegatorStakingRewardsBalance the rewards awarded to the guardian role
    /// @return guardianStakingRewardsBalance the rewards awarded to the guardian role
    function getStakingRewardsBalance(address addr) external override view returns (uint256 delegatorStakingRewardsBalance, uint256 guardianStakingRewardsBalance) {
        (DelegatorStakingRewards memory delegatorStakingRewards,,) = getDelegatorStakingRewards(addr, block.timestamp);
        (GuardianStakingRewards memory guardianStakingRewards,,) = getGuardianStakingRewards(addr, block.timestamp);
        return (delegatorStakingRewards.balance, guardianStakingRewards.balance);
    }

    /// Claims the staking rewards balance of an addr, staking the rewards
    /// @dev Claimed rewards are staked in the staking contract using the distributeRewards interface
    /// @dev includes the rewards for both the delegator and guardian roles
    /// @dev calculates the up to date rewards prior to distribute them to the staking contract
    /// @param addr is the address to claim rewards for
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

    /// Returns the current global staking rewards state
    /// @dev calculated to the latest block, may differ from the state read
    /// @return stakingRewardsPerWeight is the potential reward per 1E18 (TOKEN_BASE) committee weight assigned to a guardian was in the committee from day zero
    /// @return unclaimedStakingRewards is the of tokens that were assigned to participants and not claimed yet
    function getStakingRewardsState() public override view returns (
        uint96 stakingRewardsPerWeight,
        uint96 unclaimedStakingRewards
    ) {
        (, , uint totalCommitteeWeight) = committeeContract.getCommitteeStats();
        (StakingRewardsState memory _stakingRewardsState,) = _getStakingRewardsState(totalCommitteeWeight, block.timestamp, settings);
        stakingRewardsPerWeight = _stakingRewardsState.stakingRewardsPerWeight;
        unclaimedStakingRewards = _stakingRewardsState.unclaimedStakingRewards;
    }

    /// Returns the current guardian staking rewards state
    /// @dev calculated to the latest block, may differ from the state read
    /// @dev notice that the guardian rewards are the rewards for the guardian role as guardian and do not include delegation rewards
    /// @dev use getDelegatorStakingRewardsData to get the guardian's rewards as delegator
    /// @param guardian is the guardian to query
    /// @return balance is the staking rewards balance for the guardian role
    /// @return claimed is the staking rewards for the guardian role that were claimed
    /// @return delegatorRewardsPerToken is the potential reward per token (1E18 units) assigned to a guardian's delegator that delegated from day zero
    /// @return delegatorRewardsPerTokenDelta is the increment in delegatorRewardsPerToken since the last guardian update
    /// @return lastStakingRewardsPerWeight is the up to date stakingRewardsPerWeight used for the guardian state calculation
    /// @return stakingRewardsPerWeightDelta is the increment in stakingRewardsPerWeight since the last guardian update
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

    /// Returns the current delegator staking rewards state
    /// @dev calculated to the latest block, may differ from the state read
    /// @param delegator is the delegator to query
    /// @return balance is the staking rewards balance for the delegator role
    /// @return claimed is the staking rewards for the delegator role that were claimed
    /// @return guardian is the guardian the delegator delegated to receiving a portion of the guardian staking rewards
    /// @return lastDelegatorRewardsPerToken is the up to date delegatorRewardsPerToken used for the delegator state calculation
    /// @return delegatorRewardsPerTokenDelta is the increment in delegatorRewardsPerToken since the last delegator update
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

    /// Returns an estimation for the delegator and guardian staking rewards for a given duration
    /// @dev the returned value is an estimation, assuming no change in the PoS state
    /// @dev the period calculated for start from the current block time until the current time + duration.
    /// @param addr is the address to estimate rewards for
    /// @param duration is the duration to calculate for in seconds
    /// @return estimatedDelegatorStakingRewards is the estimated reward for the delegator role
    /// @return estimatedGuardianStakingRewards is the estimated reward for the guardian role
    function estimateFutureRewards(address addr, uint256 duration) external override view returns (uint256 estimatedDelegatorStakingRewards, uint256 estimatedGuardianStakingRewards) {
        (GuardianStakingRewards memory guardianRewardsNow,,) = getGuardianStakingRewards(addr, block.timestamp);
        (DelegatorStakingRewards memory delegatorRewardsNow,,) = getDelegatorStakingRewards(addr, block.timestamp);
        (GuardianStakingRewards memory guardianRewardsFuture,,) = getGuardianStakingRewards(addr, block.timestamp.add(duration));
        (DelegatorStakingRewards memory delegatorRewardsFuture,,) = getDelegatorStakingRewards(addr, block.timestamp.add(duration));

        estimatedDelegatorStakingRewards = delegatorRewardsFuture.balance.sub(delegatorRewardsNow.balance);
        estimatedGuardianStakingRewards = guardianRewardsFuture.balance.sub(guardianRewardsNow.balance);
    }

    /// Sets the guardian's delegators staking reward portion
    /// @dev by default uses the defaultDelegatorsStakingRewardsPercentMille
    /// @param delegatorRewardsPercentMille is the delegators portion in percent-mille (0 - maxDelegatorsStakingRewardsPercentMille)
    function setGuardianDelegatorsStakingRewardsPercentMille(uint32 delegatorRewardsPercentMille) external override onlyWhenActive {
        require(delegatorRewardsPercentMille <= PERCENT_MILLIE_BASE, "delegatorRewardsPercentMille must be 100000 at most");
        require(delegatorRewardsPercentMille <= settings.maxDelegatorsStakingRewardsPercentMille, "delegatorRewardsPercentMille must not be larger than maxDelegatorsStakingRewardsPercentMille");
        updateDelegatorStakingRewards(msg.sender);
        _setGuardianDelegatorsStakingRewardsPercentMille(msg.sender, delegatorRewardsPercentMille);
    }

    /// Returns a guardian's delegators staking reward portion
    /// @dev If not explicitly set, returns the defaultDelegatorsStakingRewardsPercentMille
    /// @return delegatorRewardsRatioPercentMille is the delegators portion in percent-mille
    function getGuardianDelegatorsStakingRewardsPercentMille(address guardian) external override view returns (uint256 delegatorRewardsRatioPercentMille) {
        return _getGuardianDelegatorsStakingRewardsPercentMille(guardian, settings);
    }

    /// Returns the amount of ORBS tokens in the staking rewards wallet allocated to staking rewards
    /// @dev The staking wallet balance must always larger than the allocated value
    /// @return allocated is the amount of tokens allocated in the staking rewards wallet
    function getStakingRewardsWalletAllocatedTokens() external override view returns (uint256 allocated) {
        (, uint96 unclaimedStakingRewards) = getStakingRewardsState();
        return uint256(unclaimedStakingRewards).sub(stakingRewardsContractBalance);
    }

    /// Returns the current annual staking reward rate
    /// @dev calculated based on the current total committee weight
    /// @return annualRate is the current staking reward rate in percent-mille
    function getCurrentStakingRewardsRatePercentMille() external override view returns (uint256 annualRate) {
        (, , uint totalCommitteeWeight) = committeeContract.getCommitteeStats();
        annualRate = _getAnnualRewardPerWeight(totalCommitteeWeight, settings).mul(PERCENT_MILLIE_BASE).div(TOKEN_BASE);
    }

    /// Notifies an expected change in the committee membership of the guardian
    /// @dev Called only by: the Committee contract
    /// @dev called upon expected change in the committee membership of the guardian
    /// @dev triggers update of the global rewards state and the guardian rewards state
    /// @dev updates the rewards state based on the committee state prior to the change
    /// @param guardian is the guardian who's committee membership is updated
    /// @param weight is the weight of the guardian prior to the change
    /// @param totalCommitteeWeight is the total committee weight prior to the change
    /// @param inCommittee indicates whether the guardian was in the committee prior to the change
    /// @param inCommitteeAfter indicates whether the guardian is in the committee after the change
    function committeeMembershipWillChange(address guardian, uint256 weight, uint256 totalCommitteeWeight, bool inCommittee, bool inCommitteeAfter) external override onlyWhenActive onlyCommitteeContract {
        uint256 delegatedStake = delegationsContract.getDelegatedStake(guardian);

        Settings memory _settings = settings;
        StakingRewardsState memory _stakingRewardsState = _updateStakingRewardsState(totalCommitteeWeight, _settings);
        _updateGuardianStakingRewards(guardian, inCommittee, inCommitteeAfter, weight, delegatedStake, _stakingRewardsState, _settings);
    }

    /// Notifies an expected change in a delegator and his guardian delegation state
    /// @dev Called only by: the Delegation contract
    /// @dev called upon expected change in a delegator's delegation state
    /// @dev triggers update of the global rewards state, the guardian rewards state and the delegator rewards state
    /// @dev on delegation change, updates also the new guardian and the delegator's lastDelegatorRewardsPerToken accordingly
    /// @param guardian is the delegator's guardian prior to the change
    /// @param guardianDelegatedStake is the delegated stake of the delegator's guardian prior to the change
    /// @param delegator is the delegator about to change delegation state
    /// @param delegatorStake is the stake of the delegator
    /// @param nextGuardian is the delegator's guardian after to the change
    /// @param nextGuardianDelegatedStake is the delegated stake of the delegator's guardian after to the change
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

    /*
    * Governance functions
    */

    /// Activates staking rewards allocation
    /// @dev governance function called only by the initialization admin
    /// @dev On migrations, startTime should be set to the previous contract deactivation time
    /// @param startTime sets the last assignment time
    function activateRewardDistribution(uint startTime) external override onlyMigrationManager {
        require(!settings.rewardAllocationActive, "reward distribution is already activated");

        stakingRewardsState.lastAssigned = uint32(startTime);
        settings.rewardAllocationActive = true;

        emit RewardDistributionActivated(startTime);
    }

    /// Deactivates fees and bootstrap allocation
    /// @dev governance function called only by the migration manager
    /// @dev guardians updates remain active based on the current perMember value
    function deactivateRewardDistribution() external override onlyMigrationManager {
        require(settings.rewardAllocationActive, "reward distribution is already deactivated");

        StakingRewardsState memory _stakingRewardsState = updateStakingRewardsState();

        settings.rewardAllocationActive = false;

        withdrawRewardsWalletAllocatedTokens(_stakingRewardsState);

        emit RewardDistributionDeactivated();
    }

    /// Sets the default delegators staking reward portion
    /// @dev governance function called only by the functional manager
    /// @param defaultDelegatorsStakingRewardsPercentMille is the default delegators portion in percent-mille(0 - maxDelegatorsStakingRewardsPercentMille)
    function setDefaultDelegatorsStakingRewardsPercentMille(uint32 defaultDelegatorsStakingRewardsPercentMille) public override onlyFunctionalManager {
        require(defaultDelegatorsStakingRewardsPercentMille <= PERCENT_MILLIE_BASE, "defaultDelegatorsStakingRewardsPercentMille must not be larger than 100000");
        require(defaultDelegatorsStakingRewardsPercentMille <= settings.maxDelegatorsStakingRewardsPercentMille, "defaultDelegatorsStakingRewardsPercentMille must not be larger than maxDelegatorsStakingRewardsPercentMille");
        settings.defaultDelegatorsStakingRewardsPercentMille = defaultDelegatorsStakingRewardsPercentMille;
        emit DefaultDelegatorsStakingRewardsChanged(defaultDelegatorsStakingRewardsPercentMille);
    }

    /// Returns the default delegators staking reward portion
    /// @return defaultDelegatorsStakingRewardsPercentMille is the default delegators portion in percent-mille
    function getDefaultDelegatorsStakingRewardsPercentMille() public override view returns (uint32) {
        return settings.defaultDelegatorsStakingRewardsPercentMille;
    }

    /// Sets the maximum delegators staking reward portion
    /// @dev governance function called only by the functional manager
    /// @param maxDelegatorsStakingRewardsPercentMille is the maximum delegators portion in percent-mille(0 - 100,000)
    function setMaxDelegatorsStakingRewardsPercentMille(uint32 maxDelegatorsStakingRewardsPercentMille) public override onlyFunctionalManager {
        require(maxDelegatorsStakingRewardsPercentMille <= PERCENT_MILLIE_BASE, "maxDelegatorsStakingRewardsPercentMille must not be larger than 100000");
        settings.maxDelegatorsStakingRewardsPercentMille = maxDelegatorsStakingRewardsPercentMille;
        emit MaxDelegatorsStakingRewardsChanged(maxDelegatorsStakingRewardsPercentMille);
    }

    /// Returns the default delegators staking reward portion
    /// @return maxDelegatorsStakingRewardsPercentMille is the maximum delegators portion in percent-mille
    function getMaxDelegatorsStakingRewardsPercentMille() public override view returns (uint32) {
        return settings.maxDelegatorsStakingRewardsPercentMille;
    }

    /// Sets the annual rate and cap for the staking reward
    /// @dev governance function called only by the functional manager
    /// @param annualRateInPercentMille is the annual rate in percent-mille
    /// @param annualCap is the annual staking rewards cap
    function setAnnualStakingRewardsRate(uint32 annualRateInPercentMille, uint96 annualCap) external override onlyFunctionalManager {
        updateStakingRewardsState();
        return _setAnnualStakingRewardsRate(annualRateInPercentMille, annualCap);
    }

    /// Returns the annual staking reward rate
    /// @return annualStakingRewardsRatePercentMille is the annual rate in percent-mille
    function getAnnualStakingRewardsRatePercentMille() external override view returns (uint32) {
        return settings.annualRateInPercentMille;
    }

    /// Returns the annual staking rewards cap
    /// @return annualStakingRewardsCap is the annual rate in percent-mille
    function getAnnualStakingRewardsCap() external override view returns (uint256) {
        return settings.annualCap;
    }

    /// Checks if rewards allocation is active
    /// @return rewardAllocationActive is a bool that indicates that rewards allocation is active
    function isRewardAllocationActive() external override view returns (bool) {
        return settings.rewardAllocationActive;
    }

    /// Returns the contract's settings
    /// @return annualStakingRewardsCap is the annual rate in percent-mille
    /// @return annualStakingRewardsRatePercentMille is the annual rate in percent-mille
    /// @return defaultDelegatorsStakingRewardsPercentMille is the default delegators portion in percent-mille
    /// @return maxDelegatorsStakingRewardsPercentMille is the maximum delegators portion in percent-mille
    /// @return rewardAllocationActive is a bool that indicates that rewards allocation is active
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

    /// Migrates the staking rewards balance of the given addresses to a new staking rewards contract
    /// @dev The new rewards contract is determined according to the contracts registry
    /// @dev No impact of the calling contract if the currently configured contract in the registry
    /// @dev may be called also while the contract is locked
    /// @param addrs is the list of addresses to migrate
    function migrateRewardsBalance(address[] calldata addrs) external override {
        require(!settings.rewardAllocationActive, "Reward distribution must be deactivated for migration");

        IStakingRewards currentRewardsContract = IStakingRewards(getStakingRewardsContract());
        require(address(currentRewardsContract) != address(this), "New rewards contract is not set");

        uint256 totalAmount = 0;
        uint256[] memory guardianRewards = new uint256[](addrs.length);
        uint256[] memory delegatorRewards = new uint256[](addrs.length);
        for (uint i = 0; i < addrs.length; i++) {
            (guardianRewards[i], delegatorRewards[i]) = claimStakingRewardsLocally(addrs[i]);
            totalAmount = totalAmount.add(guardianRewards[i]).add(delegatorRewards[i]);
        }

        require(token.approve(address(currentRewardsContract), totalAmount), "migrateRewardsBalance: approve failed");
        currentRewardsContract.acceptRewardsBalanceMigration(addrs, guardianRewards, delegatorRewards, totalAmount);

        for (uint i = 0; i < addrs.length; i++) {
            emit StakingRewardsBalanceMigrated(addrs[i], guardianRewards[i], delegatorRewards[i], address(currentRewardsContract));
        }
    }

    /// Accepts addresses balance migration from a previous rewards contract
    /// @dev the function may be called by any caller that approves the amounts provided for transfer
    /// @param addrs is the list migrated addresses
    /// @param migratedGuardianStakingRewards is the list of received guardian rewards balance for each address
    /// @param migratedDelegatorStakingRewards is the list of received delegator rewards balance for each address
    /// @param totalAmount is the total amount of staking rewards migrated for all addresses in the list. Must match the sum of migratedGuardianStakingRewards and migratedDelegatorStakingRewards lists.
    function acceptRewardsBalanceMigration(address[] calldata addrs, uint256[] calldata migratedGuardianStakingRewards, uint256[] calldata migratedDelegatorStakingRewards, uint256 totalAmount) external override {
        uint256 _totalAmount = 0;

        for (uint i = 0; i < addrs.length; i++) {
            _totalAmount = _totalAmount.add(migratedGuardianStakingRewards[i]).add(migratedDelegatorStakingRewards[i]);
        }

        require(totalAmount == _totalAmount, "totalAmount does not match sum of rewards");

        if (totalAmount > 0) {
            require(token.transferFrom(msg.sender, address(this), totalAmount), "acceptRewardBalanceMigration: transfer failed");
        }

        for (uint i = 0; i < addrs.length; i++) {
            guardiansStakingRewards[addrs[i]].balance = guardiansStakingRewards[addrs[i]].balance.add(migratedGuardianStakingRewards[i]);
            delegatorsStakingRewards[addrs[i]].balance = delegatorsStakingRewards[addrs[i]].balance.add(migratedDelegatorStakingRewards[i]);
            emit StakingRewardsBalanceMigrationAccepted(msg.sender, addrs[i], migratedGuardianStakingRewards[i], migratedDelegatorStakingRewards[i]);
        }

        stakingRewardsContractBalance = stakingRewardsContractBalance.add(totalAmount);
        stakingRewardsState.unclaimedStakingRewards = stakingRewardsState.unclaimedStakingRewards.add(totalAmount);
    }

    /// Performs emergency withdrawal of the contract balance
    /// @dev called with a token to withdraw, should be called twice with the fees and bootstrap tokens
    /// @dev governance function called only by the migration manager
    /// @param erc20 is the ERC20 token to withdraw
    function emergencyWithdraw(address erc20) external override onlyMigrationManager {
        IERC20 _token = IERC20(erc20);
        emit EmergencyWithdrawal(msg.sender, address(_token));
        require(_token.transfer(msg.sender, _token.balanceOf(address(this))), "StakingRewards::emergencyWithdraw - transfer failed");
    }

    /*
    * Private functions
    */

    // Global state

    /// Returns the annual reward per weight
    /// @dev calculates the current annual rewards per weight based on the annual rate and annual cap
    function _getAnnualRewardPerWeight(uint256 totalCommitteeWeight, Settings memory _settings) private pure returns (uint256) {
        return totalCommitteeWeight == 0 ? 0 : Math.min(uint256(_settings.annualRateInPercentMille).mul(TOKEN_BASE).div(PERCENT_MILLIE_BASE), uint256(_settings.annualCap).mul(TOKEN_BASE).div(totalCommitteeWeight));
    }

    /// Calculates the added rewards per weight for the given duration based on the committee data
    /// @param totalCommitteeWeight is the current committee total weight
    /// @param duration is the duration to calculate for in seconds
    /// @param _settings is the contract settings
    function calcStakingRewardPerWeightDelta(uint256 totalCommitteeWeight, uint duration, Settings memory _settings) private pure returns (uint256 stakingRewardsPerWeightDelta) {
        stakingRewardsPerWeightDelta = 0;

        if (totalCommitteeWeight > 0) {
            uint annualRewardPerWeight = _getAnnualRewardPerWeight(totalCommitteeWeight, _settings);
            stakingRewardsPerWeightDelta = annualRewardPerWeight.mul(duration).div(365 days);
        }
    }

    /// Returns the up global staking rewards state for a specific time
    /// @dev receives the relevant committee data
    /// @dev for future time calculations assumes no change in the committee data
    /// @param totalCommitteeWeight is the current committee total weight
    /// @param currentTime is the time to calculate the rewards for
    /// @param _settings is the contract settings
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

    /// Updates the global staking rewards
    /// @dev calculated to the latest block, may differ from the state read
    /// @dev uses the _getStakingRewardsState function
    /// @param totalCommitteeWeight is the current committee total weight
    /// @param _settings is the contract settings
    /// @return _stakingRewardsState is the updated global staking rewards struct
    function _updateStakingRewardsState(uint256 totalCommitteeWeight, Settings memory _settings) private returns (StakingRewardsState memory _stakingRewardsState) {
        if (!_settings.rewardAllocationActive) {
            return stakingRewardsState;
        }

        uint allocatedRewards;
        (_stakingRewardsState, allocatedRewards) = _getStakingRewardsState(totalCommitteeWeight, block.timestamp, _settings);
        stakingRewardsState = _stakingRewardsState;
        emit StakingRewardsAllocated(allocatedRewards, _stakingRewardsState.stakingRewardsPerWeight);
    }

    /// Updates the global staking rewards
    /// @dev calculated to the latest block, may differ from the state read
    /// @dev queries the committee state from the committee contract
    /// @dev uses the _updateStakingRewardsState function
    /// @return _stakingRewardsState is the updated global staking rewards struct
    function updateStakingRewardsState() private returns (StakingRewardsState memory _stakingRewardsState) {
        (, , uint totalCommitteeWeight) = committeeContract.getCommitteeStats();
        return _updateStakingRewardsState(totalCommitteeWeight, settings);
    }

    // Guardian state

    /// Returns the current guardian staking rewards state
    /// @dev receives the relevant committee and guardian data along with the global updated global state
    /// @dev calculated to the latest block, may differ from the state read
    /// @param guardian is the guardian to query
    /// @param inCommittee indicates whether the guardian is currently in the committee
    /// @param inCommitteeAfter indicates whether after a potential change the guardian is in the committee
    /// @param guardianWeight is the guardian committee weight
    /// @param guardianDelegatedStake is the guardian delegated stake
    /// @param _stakingRewardsState is the updated global staking rewards state
    /// @param _settings is the contract settings
    /// @return guardianStakingRewards is the updated guardian staking rewards state
    /// @return rewardsAdded is the amount awarded to the guardian since the last update
    /// @return stakingRewardsPerWeightDelta is the delta added to the stakingRewardsPerWeight since the last update
    /// @return delegatorRewardsPerTokenDelta is the delta added to the guardian's delegatorRewardsPerToken since the last update
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

    /// Returns the guardian staking rewards state for a given time
    /// @dev if the time to estimate is in the future, estimates the rewards for the given time
    /// @dev for future time estimation assumes no change in the committee and the guardian state
    /// @param guardian is the guardian to query
    /// @param currentTime is the time to calculate the rewards for
    /// @return guardianStakingRewards is the guardian staking rewards state updated to the give time
    /// @return stakingRewardsPerWeightDelta is the delta added to the stakingRewardsPerWeight since the last update
    /// @return delegatorRewardsPerTokenDelta is the delta added to the guardian's delegatorRewardsPerToken since the last update
    function getGuardianStakingRewards(address guardian, uint256 currentTime) private view returns (GuardianStakingRewards memory guardianStakingRewards, uint256 stakingRewardsPerWeightDelta, uint256 delegatorRewardsPerTokenDelta) {
        Settings memory _settings = settings;

        (bool inCommittee, uint256 guardianWeight, ,uint256 totalCommitteeWeight) = committeeContract.getMemberInfo(guardian);
        uint256 guardianDelegatedStake = delegationsContract.getDelegatedStake(guardian);

        (StakingRewardsState memory _stakingRewardsState,) = _getStakingRewardsState(totalCommitteeWeight, currentTime, _settings);
        (guardianStakingRewards,,stakingRewardsPerWeightDelta,delegatorRewardsPerTokenDelta) = _getGuardianStakingRewards(guardian, inCommittee, inCommittee, guardianWeight, guardianDelegatedStake, _stakingRewardsState, _settings);
    }

    /// Updates a guardian staking rewards state
    /// @dev receives the relevant committee and guardian data along with the global updated global state
    /// @dev updates the global staking rewards state prior to calculating the guardian's
    /// @dev uses _getGuardianStakingRewards
    /// @param guardian is the guardian to update
    /// @param inCommittee indicates whether the guardian was in the committee prior to the change
    /// @param inCommitteeAfter indicates whether the guardian is in the committee after the change
    /// @param guardianWeight is the committee weight of the guardian prior to the change
    /// @param guardianDelegatedStake is the delegated stake of the guardian prior to the change
    /// @param _stakingRewardsState is the updated global staking rewards state
    /// @param _settings is the contract settings
    /// @return guardianStakingRewards is the updated guardian staking rewards state
    function _updateGuardianStakingRewards(address guardian, bool inCommittee, bool inCommitteeAfter, uint256 guardianWeight, uint256 guardianDelegatedStake, StakingRewardsState memory _stakingRewardsState, Settings memory _settings) private returns (GuardianStakingRewards memory guardianStakingRewards) {
        uint256 guardianStakingRewardsAdded;
        uint256 stakingRewardsPerWeightDelta;
        uint256 delegatorRewardsPerTokenDelta;
        (guardianStakingRewards, guardianStakingRewardsAdded, stakingRewardsPerWeightDelta, delegatorRewardsPerTokenDelta) = _getGuardianStakingRewards(guardian, inCommittee, inCommitteeAfter, guardianWeight, guardianDelegatedStake, _stakingRewardsState, _settings);
        guardiansStakingRewards[guardian] = guardianStakingRewards;
        emit GuardianStakingRewardsAssigned(guardian, guardianStakingRewardsAdded, guardianStakingRewards.claimed.add(guardianStakingRewards.balance), guardianStakingRewards.delegatorRewardsPerToken, delegatorRewardsPerTokenDelta, _stakingRewardsState.stakingRewardsPerWeight, stakingRewardsPerWeightDelta);
    }

    /// Updates a guardian staking rewards state
    /// @dev queries the relevant guardian and committee data from the committee contract
    /// @dev uses _updateGuardianStakingRewards
    /// @param guardian is the guardian to update
    /// @param _stakingRewardsState is the updated global staking rewards state
    /// @param _settings is the contract settings
    /// @return guardianStakingRewards is the updated guardian staking rewards state
    function updateGuardianStakingRewards(address guardian, StakingRewardsState memory _stakingRewardsState, Settings memory _settings) private returns (GuardianStakingRewards memory guardianStakingRewards) {
        (bool inCommittee, uint256 guardianWeight,,) = committeeContract.getMemberInfo(guardian);
        return _updateGuardianStakingRewards(guardian, inCommittee, inCommittee, guardianWeight, delegationsContract.getDelegatedStake(guardian), _stakingRewardsState, _settings);
    }

    // Delegator state

    /// Returns the current delegator staking rewards state
    /// @dev receives the relevant delegator data along with the delegator's current guardian updated global state
    /// @dev calculated to the latest block, may differ from the state read
    /// @param delegator is the delegator to query
    /// @param delegatorStake is the stake of the delegator
    /// @param guardianStakingRewards is the updated guardian staking rewards state
    /// @return delegatorStakingRewards is the updated delegator staking rewards state
    /// @return delegatorRewardsAdded is the amount awarded to the delegator since the last update
    /// @return delegatorRewardsPerTokenDelta is the delta added to the delegator's delegatorRewardsPerToken since the last update
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

    /// Returns the delegator staking rewards state for a given time
    /// @dev if the time to estimate is in the future, estimates the rewards for the given time
    /// @dev for future time estimation assumes no change in the committee, delegation and the delegator state
    /// @param delegator is the delegator to query
    /// @param currentTime is the time to calculate the rewards for
    /// @return delegatorStakingRewards is the updated delegator staking rewards state
    /// @return guardian is the guardian the delegator delegated to
    /// @return delegatorStakingRewardsPerTokenDelta is the delta added to the delegator's delegatorRewardsPerToken since the last update
    function getDelegatorStakingRewards(address delegator, uint256 currentTime) private view returns (DelegatorStakingRewards memory delegatorStakingRewards, address guardian, uint256 delegatorStakingRewardsPerTokenDelta) {
        uint256 delegatorStake;
        (guardian, delegatorStake) = delegationsContract.getDelegationInfo(delegator);
        (GuardianStakingRewards memory guardianStakingRewards,,) = getGuardianStakingRewards(guardian, currentTime);

        (delegatorStakingRewards,,delegatorStakingRewardsPerTokenDelta) = _getDelegatorStakingRewards(delegator, delegatorStake, guardianStakingRewards);
    }

    /// Updates a delegator staking rewards state
    /// @dev receives the relevant delegator data along with the delegator's current guardian updated global state
    /// @dev updates the guardian staking rewards state prior to calculating the delegator's
    /// @dev uses _getDelegatorStakingRewards
    /// @param delegator is the delegator to update
    /// @param delegatorStake is the stake of the delegator
    /// @param guardianStakingRewards is the updated guardian staking rewards state
    function _updateDelegatorStakingRewards(address delegator, uint256 delegatorStake, address guardian, GuardianStakingRewards memory guardianStakingRewards) private {
        uint256 delegatorStakingRewardsAdded;
        uint256 delegatorRewardsPerTokenDelta;
        DelegatorStakingRewards memory delegatorStakingRewards;
        (delegatorStakingRewards, delegatorStakingRewardsAdded, delegatorRewardsPerTokenDelta) = _getDelegatorStakingRewards(delegator, delegatorStake, guardianStakingRewards);
        delegatorsStakingRewards[delegator] = delegatorStakingRewards;

        emit DelegatorStakingRewardsAssigned(delegator, delegatorStakingRewardsAdded, delegatorStakingRewards.claimed.add(delegatorStakingRewards.balance), guardian, guardianStakingRewards.delegatorRewardsPerToken, delegatorRewardsPerTokenDelta);
    }

    /// Updates a delegator staking rewards state
    /// @dev queries the relevant delegator and committee data from the committee contract and delegation contract
    /// @dev uses _updateDelegatorStakingRewards
    /// @param delegator is the delegator to update
    function updateDelegatorStakingRewards(address delegator) private {
        Settings memory _settings = settings;

        (, , uint totalCommitteeWeight) = committeeContract.getCommitteeStats();
        StakingRewardsState memory _stakingRewardsState = _updateStakingRewardsState(totalCommitteeWeight, _settings);

        (address guardian, uint delegatorStake) = delegationsContract.getDelegationInfo(delegator);
        GuardianStakingRewards memory guardianRewards = updateGuardianStakingRewards(guardian, _stakingRewardsState, _settings);

        _updateDelegatorStakingRewards(delegator, delegatorStake, guardian, guardianRewards);
    }

    // Guardian settings

    /// Returns the guardian's delegator portion in percent-mille
    /// @dev if no explicit value was set by the guardian returns the default value
    /// @dev enforces the maximum delegators staking rewards cut
    function _getGuardianDelegatorsStakingRewardsPercentMille(address guardian, Settings memory _settings) private view returns (uint256 delegatorRewardsRatioPercentMille) {
        GuardianRewardSettings memory guardianSettings = guardiansRewardSettings[guardian];
        delegatorRewardsRatioPercentMille =  guardianSettings.overrideDefault ? guardianSettings.delegatorsStakingRewardsPercentMille : _settings.defaultDelegatorsStakingRewardsPercentMille;
        return Math.min(delegatorRewardsRatioPercentMille, _settings.maxDelegatorsStakingRewardsPercentMille);
    }

    /// Migrates a list of guardians' delegators portion setting from a previous staking rewards contract
    /// @dev called by the constructor
    function migrateGuardiansSettings(IStakingRewards previousRewardsContract, address[] memory guardiansToMigrate) private {
        for (uint i = 0; i < guardiansToMigrate.length; i++) {
            _setGuardianDelegatorsStakingRewardsPercentMille(guardiansToMigrate[i], uint32(previousRewardsContract.getGuardianDelegatorsStakingRewardsPercentMille(guardiansToMigrate[i])));
        }
    }

    // Governance and misc.

    /// Sets the annual rate and cap for the staking reward
    /// @param annualRateInPercentMille is the annual rate in percent-mille
    /// @param annualCap is the annual staking rewards cap
    function _setAnnualStakingRewardsRate(uint32 annualRateInPercentMille, uint96 annualCap) private {
        Settings memory _settings = settings;
        _settings.annualRateInPercentMille = annualRateInPercentMille;
        _settings.annualCap = annualCap;
        settings = _settings;

        emit AnnualStakingRewardsRateChanged(annualRateInPercentMille, annualCap);
    }

    /// Sets the guardian's delegators staking reward portion
    /// @param guardian is the guardian to set
    /// @param delegatorRewardsPercentMille is the delegators portion in percent-mille (0 - maxDelegatorsStakingRewardsPercentMille)
    function _setGuardianDelegatorsStakingRewardsPercentMille(address guardian, uint32 delegatorRewardsPercentMille) private {
        guardiansRewardSettings[guardian] = GuardianRewardSettings({
            overrideDefault: true,
            delegatorsStakingRewardsPercentMille: delegatorRewardsPercentMille
            });

        emit GuardianDelegatorsStakingRewardsPercentMilleUpdated(guardian, delegatorRewardsPercentMille);
    }

    /// Claims an addr staking rewards and update its rewards state without transferring the rewards
    /// @dev used by claimStakingRewards and migrateRewardsBalance
    /// @param addr is the address to claim rewards for
    /// @return guardianRewards is the claimed guardian rewards balance
    /// @return delegatorRewards is the claimed delegator rewards balance
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

    /// Withdraws the tokens that were allocated to the contract from the staking rewards wallet
    /// @dev used as part of the migration flow to withdraw all the funds allocated for participants before updating the wallet client to a new contract
    /// @param _stakingRewardsState is the updated global staking rewards state
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

    /// Refreshes the address of the other contracts the contract interacts with
    /// @dev called by the registry contract upon an update of a contract in the registry
    function refreshContracts() external override {
        committeeContract = ICommittee(getCommitteeContract());
        delegationsContract = IDelegations(getDelegationsContract());
        stakingRewardsWallet = IProtocolWallet(getStakingRewardsWallet());
        stakingContract = IStakingContract(getStakingContract());
    }
}
