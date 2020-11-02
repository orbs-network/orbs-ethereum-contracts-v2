// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./SafeMath96.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./spec_interfaces/ICommittee.sol";
import "./spec_interfaces/IProtocolWallet.sol";
import "./spec_interfaces/IFeesWallet.sol";
import "./spec_interfaces/IFeesAndBootstrapRewards.sol";
import "./ManagedContract.sol";

contract FeesAndBootstrapRewards is IFeesAndBootstrapRewards, ManagedContract {
    using SafeMath for uint256;
    using SafeMath96 for uint96;

    uint256 constant PERCENT_MILLIE_BASE = 100000;
    uint256 constant TOKEN_BASE = 1e18;

    struct Settings {
        uint96 generalCommitteeAnnualBootstrap;
        uint96 certifiedCommitteeAnnualBootstrap;
        bool rewardAllocationActive;
    }
    Settings settings;

    IERC20 public bootstrapToken;
    IERC20 public feesToken;

    struct FeesAndBootstrapState {
        uint96 certifiedFeesPerMember;
        uint96 generalFeesPerMember;
        uint96 certifiedBootstrapPerMember;
        uint96 generalBootstrapPerMember;
        uint32 lastAssigned;
    }
    FeesAndBootstrapState public feesAndBootstrapState;

    struct FeesAndBootstrap {
        uint96 feeBalance;
        uint96 bootstrapBalance;
        uint96 lastFeesPerMember;
        uint96 lastBootstrapPerMember;
        uint96 withdrawnFees;
        uint96 withdrawnBootstrap;
    }
    mapping(address => FeesAndBootstrap) public feesAndBootstrap;

    /// Constructor
    /// @param _contractRegistry is the contract registry address
    /// @param _registryAdmin is the registry admin address
    /// @param _feesToken is the token used for virtual chains fees 
    /// @param _bootstrapToken is the token used for the bootstrap reward
    /// @param generalCommitteeAnnualBootstrap is the general committee annual bootstrap reward
    /// @param certifiedCommitteeAnnualBootstrap is the certified committee additional annual bootstrap reward
    constructor(
        IContractRegistry _contractRegistry,
        address _registryAdmin,
        IERC20 _feesToken,
        IERC20 _bootstrapToken,
        uint generalCommitteeAnnualBootstrap,
        uint certifiedCommitteeAnnualBootstrap
    ) ManagedContract(_contractRegistry, _registryAdmin) public {
        require(address(_bootstrapToken) != address(0), "bootstrapToken must not be 0");
        require(address(_feesToken) != address(0), "feeToken must not be 0");

        _setGeneralCommitteeAnnualBootstrap(generalCommitteeAnnualBootstrap);
        _setCertifiedCommitteeAnnualBootstrap(certifiedCommitteeAnnualBootstrap);

        feesToken = _feesToken;
        bootstrapToken = _bootstrapToken;
    }

    modifier onlyCommitteeContract() {
        require(msg.sender == address(committeeContract), "caller is not the elections contract");

        _;
    }

    /*
    * External functions
    */

    /// Triggers update of the guardian rewards
	/// @dev Called by: the Committee contract
    /// @dev called upon expected change in the committee membership of the guardian
    /// @param guardian is the guardian who's committee membership is updated
    /// @param inCommittee indicates whether the guardian is in the committee prior to the change
    /// @param isCertified indicates whether the guardian is certified prior to the change
    /// @param nextCertification indicates whether after the change, the guardian is certified
    /// @param generalCommitteeSize indicates the general committee size prior to the change
    /// @param certifiedCommitteeSize indicates the certified committee size prior to the change
    function committeeMembershipWillChange(address guardian, bool inCommittee, bool isCertified, bool nextCertification, uint generalCommitteeSize, uint certifiedCommitteeSize) external override onlyWhenActive onlyCommitteeContract {
        _updateGuardianFeesAndBootstrap(guardian, inCommittee, isCertified, nextCertification, generalCommitteeSize, certifiedCommitteeSize);
    }

    /// Returns the fees and bootstrap balances of a guardian
    /// @dev calculates the up to date balances (differ from the state)
    /// @return feeBalance the guardian's fees balance
    /// @return bootstrapBalance the guardian's bootstrap balance
    function getFeesAndBootstrapBalance(address guardian) external override view returns (uint256 feeBalance, uint256 bootstrapBalance) {
        (FeesAndBootstrap memory guardianFeesAndBootstrap,) = getGuardianFeesAndBootstrap(guardian, block.timestamp);
        return (guardianFeesAndBootstrap.feeBalance, guardianFeesAndBootstrap.bootstrapBalance);
    }

    /// Returns an estimation of the fees and bootstrap a guardian will be entitled to for a duration of time
    /// The estimation is based on the current system state and there for only provides an estimation
    /// @param guardian is the guardian address
    /// @param duration is the amount of time in seconds for which the estimation is calculated
    /// @return estimatedFees is the estimated received fees for the duration
    /// @return estimatedBootstrapRewards is the estimated received bootstrap for the duration
    function estimateFutureFeesAndBootstrapRewards(address guardian, uint256 duration) external override view returns (uint256 estimatedFees, uint256 estimatedBootstrapRewards) {
        (FeesAndBootstrap memory guardianFeesAndBootstrapNow,) = getGuardianFeesAndBootstrap(guardian, block.timestamp);
        (FeesAndBootstrap memory guardianFeesAndBootstrapFuture,) = getGuardianFeesAndBootstrap(guardian, block.timestamp.add(duration));
        estimatedFees = guardianFeesAndBootstrapFuture.feeBalance.sub(guardianFeesAndBootstrapNow.feeBalance);
        estimatedBootstrapRewards = guardianFeesAndBootstrapFuture.bootstrapBalance.sub(guardianFeesAndBootstrapNow.bootstrapBalance);
    }

    /// Transfers the guardian Fees balance to their account
    /// @dev One may withdraw for another guardian
    /// @param guardian is the guardian address
    function withdrawFees(address guardian) external override onlyWhenActive {
        updateGuardianFeesAndBootstrap(guardian);

        uint256 amount = feesAndBootstrap[guardian].feeBalance;
        feesAndBootstrap[guardian].feeBalance = 0;
        uint96 withdrawnFees = feesAndBootstrap[guardian].withdrawnFees.add(amount);
        feesAndBootstrap[guardian].withdrawnFees = withdrawnFees;

        emit FeesWithdrawn(guardian, amount, withdrawnFees);
        require(feesToken.transfer(guardian, amount), "Rewards::withdrawFees - insufficient funds");
    }

    /// Transfers the guardian bootstrap balance to their account
    /// @dev One may withdraw for another guardian
    /// @param guardian is the guardian address
    function withdrawBootstrapFunds(address guardian) external override onlyWhenActive {
        updateGuardianFeesAndBootstrap(guardian);
        uint256 amount = feesAndBootstrap[guardian].bootstrapBalance;
        feesAndBootstrap[guardian].bootstrapBalance = 0;
        uint96 withdrawnBootstrap = feesAndBootstrap[guardian].withdrawnBootstrap.add(amount);
        feesAndBootstrap[guardian].withdrawnBootstrap = withdrawnBootstrap;
        emit BootstrapRewardsWithdrawn(guardian, amount, withdrawnBootstrap);

        require(bootstrapToken.transfer(guardian, amount), "Rewards::withdrawBootstrapFunds - insufficient funds");
    }

    /// Returns the current global Fees and Bootstrap rewards state 
    /// @dev calculated to the latest block, may differ from the state read
    /// @return certifiedFeesPerMember represents the fees a certified committee member from day 0 would have receive
    /// @return generalFeesPerMember represents the fees a non-certified committee member from day 0 would have receive
    /// @return certifiedBootstrapPerMember represents the bootstrap fund a certified committee member from day 0 would have receive
    /// @return generalBootstrapPerMember represents the bootstrap fund a non-certified committee member from day 0 would have receive
    /// @return lastAssigned is the time the calculation was done to (typically the latest block time)
    function getFeesAndBootstrapState() external override view returns (
        uint256 certifiedFeesPerMember,
        uint256 generalFeesPerMember,
        uint256 certifiedBootstrapPerMember,
        uint256 generalBootstrapPerMember,
        uint256 lastAssigned
    ) {
        (uint generalCommitteeSize, uint certifiedCommitteeSize, ) = committeeContract.getCommitteeStats();
        (FeesAndBootstrapState memory _feesAndBootstrapState,,) = _getFeesAndBootstrapState(generalCommitteeSize, certifiedCommitteeSize, generalFeesWallet.getOutstandingFees(block.timestamp), certifiedFeesWallet.getOutstandingFees(block.timestamp), block.timestamp, settings);
        certifiedFeesPerMember = _feesAndBootstrapState.certifiedFeesPerMember;
        generalFeesPerMember = _feesAndBootstrapState.generalFeesPerMember;
        certifiedBootstrapPerMember = _feesAndBootstrapState.certifiedBootstrapPerMember;
        generalBootstrapPerMember = _feesAndBootstrapState.generalBootstrapPerMember;
        lastAssigned = _feesAndBootstrapState.lastAssigned;
    }

    /// Returns the current guardian Fees and Bootstrap rewards state 
    /// @dev calculated to the latest block, may differ from the state read
    /// @return feeBalance is the guardian fees balance 
    /// @return lastFeesPerMember is the FeesPerMember on the last update based on the guardian certification state
    /// @return bootstrapBalance is the guardian bootstrap balance 
    /// @return lastBootstrapPerMember is the FeesPerMember on the last BootstrapPerMember based on the guardian certification state
    function getFeesAndBootstrapData(address guardian) external override view returns (
        uint256 feeBalance,
        uint256 lastFeesPerMember,
        uint256 bootstrapBalance,
        uint256 lastBootstrapPerMember,
        uint256 withdrawnFees,
        uint256 withdrawnBootstrap,
        bool certified
    ) {
        FeesAndBootstrap memory guardianFeesAndBootstrap;
        (guardianFeesAndBootstrap, certified) = getGuardianFeesAndBootstrap(guardian, block.timestamp);
        return (
            guardianFeesAndBootstrap.feeBalance,
            guardianFeesAndBootstrap.lastFeesPerMember,
            guardianFeesAndBootstrap.bootstrapBalance,
            guardianFeesAndBootstrap.lastBootstrapPerMember,
            guardianFeesAndBootstrap.withdrawnFees,
            guardianFeesAndBootstrap.withdrawnBootstrap,
            certified
        );
    }

    /*
     * Governance functions
     */

    /// Deactivates fees and bootstrap allocation
	/// @dev governance function called only by the migration manager
    /// @dev guardians updates remain active based on the current perMember value
    function deactivateRewardDistribution() external override onlyMigrationManager {
        require(settings.rewardAllocationActive, "reward distribution is already deactivated");

        updateFeesAndBootstrapState();

        settings.rewardAllocationActive = false;

        emit RewardDistributionDeactivated();
    }

    /// Activates fees and bootstrap allocation
	/// @dev governance function called only by the initialization manager
    /// @dev On migrations, startTime should be set as the previous contract deactivation time.
    /// @param startTime sets the last assignment time
    function activateRewardDistribution(uint startTime) external override onlyMigrationManager {
        require(!settings.rewardAllocationActive, "reward distribution is already activated");

        feesAndBootstrapState.lastAssigned = uint32(startTime);
        settings.rewardAllocationActive = true;

        emit RewardDistributionActivated(startTime);
    }

    /// Returns the rewards allocation activation status
    /// @return rewardAllocationActive is the activation status
    function isRewardAllocationActive() external override view returns (bool) {
        return settings.rewardAllocationActive;
    }

	/// Sets the annual rate for the general committee bootstrap
	/// @dev governance function called only by the functional manager
    /// @dev updates the global bootstrap and fees state before updating  
	/// @param annualAmount is the annual general committee bootstrap award
    function setGeneralCommitteeAnnualBootstrap(uint256 annualAmount) external override onlyFunctionalManager {
        updateFeesAndBootstrapState();
        _setGeneralCommitteeAnnualBootstrap(annualAmount);
    }

    /// Returns the general committee annual bootstrap award
    /// @return generalCommitteeAnnualBootstrap is the general committee annual bootstrap
    function getGeneralCommitteeAnnualBootstrap() external override view returns (uint256) {
        return settings.generalCommitteeAnnualBootstrap;
    }

	/// Sets the annual rate for the certified committee bootstrap
	/// @dev governance function called only by the functional manager
    /// @dev updates the global bootstrap and fees state before updating  
	/// @param annualAmount is the annual certified committee bootstrap award
    function setCertifiedCommitteeAnnualBootstrap(uint256 annualAmount) external override onlyFunctionalManager {
        updateFeesAndBootstrapState();
        _setCertifiedCommitteeAnnualBootstrap(annualAmount);
    }

    /// Returns the certified committee annual bootstrap reward
    /// @return certifiedCommitteeAnnualBootstrap is the certified committee additional annual bootstrap
    function getCertifiedCommitteeAnnualBootstrap() external override view returns (uint256) {
        return settings.certifiedCommitteeAnnualBootstrap;
    }

    /// Migrates the rewards balance to a new FeesAndBootstrap contract
    /// @dev The new rewards contract is determined according to the contracts registry
    /// @dev No impact of the calling contract if the currently configured contract in the registry
    /// @dev may be called also while the contract is locked
    /// @param guardian is the guardian to migrate
    function migrateRewardsBalance(address guardian) external override {
        require(!settings.rewardAllocationActive, "Reward distribution must be deactivated for migration");

        IFeesAndBootstrapRewards currentRewardsContract = IFeesAndBootstrapRewards(getFeesAndBootstrapRewardsContract());
        require(address(currentRewardsContract) != address(this), "New rewards contract is not set");

        updateGuardianFeesAndBootstrap(guardian);

        FeesAndBootstrap memory guardianFeesAndBootstrap = feesAndBootstrap[guardian];
        uint256 fees = guardianFeesAndBootstrap.feeBalance;
        uint256 bootstrap = guardianFeesAndBootstrap.bootstrapBalance;

        guardianFeesAndBootstrap.feeBalance = 0;
        guardianFeesAndBootstrap.bootstrapBalance = 0;
        feesAndBootstrap[guardian] = guardianFeesAndBootstrap;

        require(feesToken.approve(address(currentRewardsContract), fees), "migrateRewardsBalance: approve failed");
        require(bootstrapToken.approve(address(currentRewardsContract), bootstrap), "migrateRewardsBalance: approve failed");
        currentRewardsContract.acceptRewardsBalanceMigration(guardian, fees, bootstrap);

        emit FeesAndBootstrapRewardsBalanceMigrated(guardian, fees, bootstrap, address(currentRewardsContract));
    }

    /// Accepts guardian's balance migration from a previous rewards contract
    /// @dev the function may be called by any caller that approves the amounts provided for transfer
    /// @param guardian is the migrated guardian
    /// @param fees is the received guardian fees balance 
    /// @param bootstrapRewards is the received guardian bootstrap balance
    function acceptRewardsBalanceMigration(address guardian, uint256 fees, uint256 bootstrap) external override {
        FeesAndBootstrap memory guardianFeesAndBootstrap = feesAndBootstrap[guardian];
        guardianFeesAndBootstrap.feeBalance = guardianFeesAndBootstrap.feeBalance.add(fees);
        guardianFeesAndBootstrap.bootstrapBalance = guardianFeesAndBootstrap.bootstrapBalance.add(bootstrap);
        feesAndBootstrap[guardian] = guardianFeesAndBootstrap;

        if (fees > 0) {
            require(feesToken.transferFrom(msg.sender, address(this), fees), "acceptRewardBalanceMigration: transfer failed");
        }
        if (bootstrap > 0) {
            require(bootstrapToken.transferFrom(msg.sender, address(this), bootstrap), "acceptRewardBalanceMigration: transfer failed");
        }

        emit FeesAndBootstrapRewardsBalanceMigrationAccepted(msg.sender, guardian, fees, bootstrap);
    }

    /// Performs emergency withdrawal of the contract balance
    /// @dev called with a token to withdraw, should be called twice with the fees and bootstrap tokens
	/// @dev governance function called only by the migration manager
    /// @param token is the ERC20 token to withdraw
    function emergencyWithdraw(address erc20) external override onlyMigrationManager {
        IERC20 _token = IERC20(erc20);
        emit EmergencyWithdrawal(msg.sender, address(_token));
        require(_token.transfer(msg.sender, _token.balanceOf(address(this))), "Rewards::emergencyWithdraw - transfer failed");
    }

    /// Returns the contract's settings
    /// @return generalCommitteeAnnualBootstrap is the general committee annual bootstrap
    /// @return certifiedCommitteeAnnualBootstrap is the certified committee additional annual bootstrap
    /// @return rewardAllocationActive indicates the rewards allocation activation state 
    function getSettings() external override view returns (
        uint generalCommitteeAnnualBootstrap,
        uint certifiedCommitteeAnnualBootstrap,
        bool rewardAllocationActive
    ) {
        Settings memory _settings = settings;
        generalCommitteeAnnualBootstrap = _settings.generalCommitteeAnnualBootstrap;
        certifiedCommitteeAnnualBootstrap = _settings.certifiedCommitteeAnnualBootstrap;
        rewardAllocationActive = _settings.rewardAllocationActive;
    }

    /*
    * Private functions
    */

    // Global state

    /// Returns the current global Fees and Bootstrap rewards state 
    /// @dev receives the relevant committee and general state data
    /// @param generalCommitteeSize is the current number of members in the certified committee
    /// @param certifiedCommitteeSize is the current number of members in the general committee
    /// @param collectedGeneralFees is the amount of fees collected from general virtual chains for the calculated period
    /// @param collectedCertifiedFees is the amount of fees collected from general virtual chains for the calculated period
    /// @param currentTime is the time to calculate the fees and bootstrap for
    /// @param _settings is the contract settings
    function _getFeesAndBootstrapState(uint generalCommitteeSize, uint certifiedCommitteeSize, uint256 collectedGeneralFees, uint256 collectedCertifiedFees, uint256 currentTime, Settings memory _settings) private view returns (FeesAndBootstrapState memory _feesAndBootstrapState, uint256 allocatedGeneralBootstrap, uint256 allocatedCertifiedBootstrap) {
        _feesAndBootstrapState = feesAndBootstrapState;

        if (_settings.rewardAllocationActive) {
            uint256 generalFeesDelta = generalCommitteeSize == 0 ? 0 : collectedGeneralFees.div(generalCommitteeSize);
            uint256 certifiedFeesDelta = certifiedCommitteeSize == 0 ? 0 : generalFeesDelta.add(collectedCertifiedFees.div(certifiedCommitteeSize));

            _feesAndBootstrapState.generalFeesPerMember = _feesAndBootstrapState.generalFeesPerMember.add(generalFeesDelta);
            _feesAndBootstrapState.certifiedFeesPerMember = _feesAndBootstrapState.certifiedFeesPerMember.add(certifiedFeesDelta);

            uint duration = currentTime.sub(_feesAndBootstrapState.lastAssigned);
            uint256 generalBootstrapDelta = uint256(_settings.generalCommitteeAnnualBootstrap).mul(duration).div(365 days);
            uint256 certifiedBootstrapDelta = generalBootstrapDelta.add(uint256(_settings.certifiedCommitteeAnnualBootstrap).mul(duration).div(365 days));

            _feesAndBootstrapState.generalBootstrapPerMember = _feesAndBootstrapState.generalBootstrapPerMember.add(generalBootstrapDelta);
            _feesAndBootstrapState.certifiedBootstrapPerMember = _feesAndBootstrapState.certifiedBootstrapPerMember.add(certifiedBootstrapDelta);
            _feesAndBootstrapState.lastAssigned = uint32(currentTime);

            allocatedGeneralBootstrap = generalBootstrapDelta.mul(generalCommitteeSize);
            allocatedCertifiedBootstrap = certifiedBootstrapDelta.mul(certifiedCommitteeSize);
        }
    }

    /// Updates the global Fees and Bootstrap rewards state
    /// @dev utilizes _getFeesAndBootstrapState to calculate the global state 
    /// @param generalCommitteeSize is the current number of members in the certified committee
    /// @param certifiedCommitteeSize is the current number of members in the general committee
    /// @return _feesAndBootstrapState is a FeesAndBootstrapState struct with the updated state
    function _updateFeesAndBootstrapState(uint generalCommitteeSize, uint certifiedCommitteeSize) private returns (FeesAndBootstrapState memory _feesAndBootstrapState) {
        Settings memory _settings = settings;
        if (!_settings.rewardAllocationActive) {
            return feesAndBootstrapState;
        }

        uint256 collectedGeneralFees = generalFeesWallet.collectFees();
        uint256 collectedCertifiedFees = certifiedFeesWallet.collectFees();
        uint256 allocatedGeneralBootstrap;
        uint256 allocatedCertifiedBootstrap;

        (_feesAndBootstrapState, allocatedGeneralBootstrap, allocatedCertifiedBootstrap) = _getFeesAndBootstrapState(generalCommitteeSize, certifiedCommitteeSize, collectedGeneralFees, collectedCertifiedFees, block.timestamp, _settings);
        bootstrapRewardsWallet.withdraw(allocatedGeneralBootstrap.add(allocatedCertifiedBootstrap));

        feesAndBootstrapState = _feesAndBootstrapState;

        emit FeesAllocated(collectedGeneralFees, _feesAndBootstrapState.generalFeesPerMember, collectedCertifiedFees, _feesAndBootstrapState.certifiedFeesPerMember);
        emit BootstrapRewardsAllocated(allocatedGeneralBootstrap, _feesAndBootstrapState.generalBootstrapPerMember, allocatedCertifiedBootstrap, _feesAndBootstrapState.certifiedBootstrapPerMember);
    }

    /// Updates the global Fees and Bootstrap rewards state
    /// @dev utilizes _updateFeesAndBootstrapState
    /// @return _feesAndBootstrapState is a FeesAndBootstrapState struct with teh updated state
    function updateFeesAndBootstrapState() private returns (FeesAndBootstrapState memory _feesAndBootstrapState) {
        (uint generalCommitteeSize, uint certifiedCommitteeSize, ) = committeeContract.getCommitteeStats();
        return _updateFeesAndBootstrapState(generalCommitteeSize, certifiedCommitteeSize);
    }

    // Guardian state

    /// Returns the current guardian Fees and Bootstrap rewards state 
    /// @dev receives the relevant guardian committee membership data and the global state
    /// @param guardian is the guardian to query
    /// @param inCommittee indicates whether the guardian is currently in the committee
    /// @param isCertified indicates whether the guardian is currently certified
    /// @param nextCertification indicates whether after the change, the guardian is certified
    /// @param _feesAndBootstrapState is the current updated global fees and bootstrap state
    /// @return guardianFeesAndBootstrap is a struct with the guardian updated fees and bootstrap state
    /// @return addedBootstrapAmount is the amount added to the guardian bootstrap balance
    /// @return addedFeesAmount is the amount added to the guardian fees balance
    function _getGuardianFeesAndBootstrap(address guardian, bool inCommittee, bool isCertified, bool nextCertification, FeesAndBootstrapState memory _feesAndBootstrapState) private view returns (FeesAndBootstrap memory guardianFeesAndBootstrap, uint256 addedBootstrapAmount, uint256 addedFeesAmount) {
        guardianFeesAndBootstrap = feesAndBootstrap[guardian];

        if (inCommittee) {
            addedBootstrapAmount = (isCertified ? _feesAndBootstrapState.certifiedBootstrapPerMember : _feesAndBootstrapState.generalBootstrapPerMember).sub(guardianFeesAndBootstrap.lastBootstrapPerMember);
            guardianFeesAndBootstrap.bootstrapBalance = guardianFeesAndBootstrap.bootstrapBalance.add(addedBootstrapAmount);

            addedFeesAmount = (isCertified ? _feesAndBootstrapState.certifiedFeesPerMember : _feesAndBootstrapState.generalFeesPerMember).sub(guardianFeesAndBootstrap.lastFeesPerMember);
            guardianFeesAndBootstrap.feeBalance = guardianFeesAndBootstrap.feeBalance.add(addedFeesAmount);
        }

        guardianFeesAndBootstrap.lastBootstrapPerMember = nextCertification ?  _feesAndBootstrapState.certifiedBootstrapPerMember : _feesAndBootstrapState.generalBootstrapPerMember;
        guardianFeesAndBootstrap.lastFeesPerMember = nextCertification ?  _feesAndBootstrapState.certifiedFeesPerMember : _feesAndBootstrapState.generalFeesPerMember;
    }

    /// Updates a guardian Fees and Bootstrap rewards state
    /// @dev receives the relevant guardian committee membership data
    /// @dev updates the global Fees and Bootstrap state prior to calculating the guardian's
    /// @dev utilizes _getGuardianFeesAndBootstrap
    /// @param guardian is the guardian to update
    /// @param inCommittee indicates whether the guardian is currently in the committee
    /// @param isCertified indicates whether the guardian is currently certified
    /// @param nextCertification indicates whether after the change, the guardian is certified
    /// @param generalCommitteeSize indicates the general committee size prior to the change
    /// @param certifiedCommitteeSize indicates the certified committee size prior to the change
    function _updateGuardianFeesAndBootstrap(address guardian, bool inCommittee, bool isCertified, bool nextCertification, uint generalCommitteeSize, uint certifiedCommitteeSize) private {
        uint256 addedBootstrapAmount;
        uint256 addedFeesAmount;

        FeesAndBootstrapState memory _feesAndBootstrapState = _updateFeesAndBootstrapState(generalCommitteeSize, certifiedCommitteeSize);
        FeesAndBootstrap memory guardianFeesAndBootstrap;
        (guardianFeesAndBootstrap, addedBootstrapAmount, addedFeesAmount) = _getGuardianFeesAndBootstrap(guardian, inCommittee, isCertified, nextCertification, _feesAndBootstrapState);
        feesAndBootstrap[guardian] = guardianFeesAndBootstrap;

        emit BootstrapRewardsAssigned(guardian, addedBootstrapAmount, guardianFeesAndBootstrap.withdrawnBootstrap.add(guardianFeesAndBootstrap.bootstrapBalance), isCertified, guardianFeesAndBootstrap.lastBootstrapPerMember);
        emit FeesAssigned(guardian, addedFeesAmount, guardianFeesAndBootstrap.withdrawnFees.add(guardianFeesAndBootstrap.feeBalance), isCertified, guardianFeesAndBootstrap.lastFeesPerMember);
    }

    /// Returns the guardian Fees and Bootstrap rewards state for a given time
    /// @dev if the time to estimate is in the future, estimates the fees and rewards for the given time
    /// @dev for future time estimation assumes no change in the guardian committee membership and certification
    /// @param guardian is the guardian to query
    /// @param currentTime is the time to calculate the fees and bootstrap for
    /// @return guardianFeesAndBootstrap is a struct with the guardian updated fees and bootstrap state
    /// @return certified is the guardian certification status
    function getGuardianFeesAndBootstrap(address guardian, uint256 currentTime) private view returns (FeesAndBootstrap memory guardianFeesAndBootstrap, bool certified) {
        ICommittee _committeeContract = committeeContract;
        (uint generalCommitteeSize, uint certifiedCommitteeSize, ) = _committeeContract.getCommitteeStats();
        (FeesAndBootstrapState memory _feesAndBootstrapState,,) = _getFeesAndBootstrapState(generalCommitteeSize, certifiedCommitteeSize, generalFeesWallet.getOutstandingFees(currentTime), certifiedFeesWallet.getOutstandingFees(currentTime), currentTime, settings);
        bool inCommittee;
        (inCommittee, , certified,) = _committeeContract.getMemberInfo(guardian);
        (guardianFeesAndBootstrap, ,) = _getGuardianFeesAndBootstrap(guardian, inCommittee, certified, certified, _feesAndBootstrapState);
    }

    /// Updates a guardian Fees and Bootstrap rewards state
    /// @dev query the relevant guardian and committee data from the committee contract
    /// @dev utilizes _updateGuardianFeesAndBootstrap
    /// @param guardian is the guardian to update
    function updateGuardianFeesAndBootstrap(address guardian) private {
        ICommittee _committeeContract = committeeContract;
        (uint generalCommitteeSize, uint certifiedCommitteeSize, ) = _committeeContract.getCommitteeStats();
        (bool inCommittee, , bool isCertified,) = _committeeContract.getMemberInfo(guardian);
        _updateGuardianFeesAndBootstrap(guardian, inCommittee, isCertified, isCertified, generalCommitteeSize, certifiedCommitteeSize);
    }

    // Governance and misc.

	/// Sets the annual rate for the general committee bootstrap
	/// @param annualAmount is the annual general committee bootstrap award
    function _setGeneralCommitteeAnnualBootstrap(uint256 annualAmount) private {
        require(uint256(uint96(annualAmount)) == annualAmount, "annualAmount must fit in uint96");

        settings.generalCommitteeAnnualBootstrap = uint96(annualAmount);
        emit GeneralCommitteeAnnualBootstrapChanged(annualAmount);
    }

	/// Sets the annual rate for the certified committee bootstrap
	/// @param annualAmount is the annual certified committee bootstrap award
    function _setCertifiedCommitteeAnnualBootstrap(uint256 annualAmount) private {
        require(uint256(uint96(annualAmount)) == annualAmount, "annualAmount must fit in uint96");

        settings.certifiedCommitteeAnnualBootstrap = uint96(annualAmount);
        emit CertifiedCommitteeAnnualBootstrapChanged(annualAmount);
    }

    /*
     * Contracts topology / registry interface
     */

    ICommittee committeeContract;
    IFeesWallet generalFeesWallet;
    IFeesWallet certifiedFeesWallet;
    IProtocolWallet bootstrapRewardsWallet;

	/// Refreshes the address of the other contracts the contract interacts with
    /// @dev called by the registry contract upon an update of a contract in the registry
    function refreshContracts() external override {
        committeeContract = ICommittee(getCommitteeContract());
        generalFeesWallet = IFeesWallet(getGeneralFeesWallet());
        certifiedFeesWallet = IFeesWallet(getCertifiedFeesWallet());
        bootstrapRewardsWallet = IProtocolWallet(getBootstrapRewardsWallet());
    }
}
