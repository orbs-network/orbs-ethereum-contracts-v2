// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./SafeMath48.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./spec_interfaces/ICommittee.sol";
import "./spec_interfaces/IProtocolWallet.sol";
import "./spec_interfaces/IFeesWallet.sol";
import "./spec_interfaces/IFeesAndBootstrapRewards.sol";
import "./ManagedContract.sol";

contract FeesAndBootstrapRewards is IFeesAndBootstrapRewards, ManagedContract {
    using SafeMath for uint256;
    using SafeMath48 for uint48;

    uint constant TOKEN_GRANULARITY = 1000000000000000;
    uint256 constant PERCENT_MILLIE_BASE = 100000;
    uint256 constant TOKEN_BASE = 1e18;

    struct Settings {
        uint48 generalCommitteeAnnualBootstrap;
        uint48 certifiedCommitteeAnnualBootstrap;
        bool rewardAllocationActive;
    }
    Settings settings;

    IERC20 public bootstrapToken;
    IERC20 public erc20;

    struct FeesAndBootstrapState {
        uint48 certifiedFeesPerMember;
        uint48 generalFeesPerMember;
        uint48 certifiedBootstrapPerMember;
        uint48 generalBootstrapPerMember;
        uint32 lastAssigned;
    }
    FeesAndBootstrapState public feesAndBootstrapState;

    struct FeesAndBootstrap {
        uint48 feeBalance;
        uint48 lastFeesPerMember;
        uint48 bootstrapBalance;
        uint48 lastBootstrapPerMember;
    }
    mapping(address => FeesAndBootstrap) public feesAndBootstrap;

    modifier onlyCommitteeContract() {
        require(msg.sender == address(committeeContract), "caller is not the elections contract");

        _;
    }

    constructor(
        IContractRegistry _contractRegistry,
        address _registryAdmin,
        IERC20 _erc20,
        IERC20 _bootstrapToken,
        uint generalCommitteeAnnualBootstrap,
        uint certifiedCommitteeAnnualBootstrap
    ) ManagedContract(_contractRegistry, _registryAdmin) public {
        require(address(_bootstrapToken) != address(0), "bootstrapToken must not be 0");
        require(address(_erc20) != address(0), "erc20 must not be 0");

        _setGeneralCommitteeAnnualBootstrap(generalCommitteeAnnualBootstrap);
        _setCertifiedCommitteeAnnualBootstrap(certifiedCommitteeAnnualBootstrap);

        erc20 = _erc20;
        bootstrapToken = _bootstrapToken;
    }

    /*
    * External functions
    */

    function committeeMembershipWillChange(address guardian, bool inCommittee, bool isCertified, bool nextCertification, uint generalCommitteeSize, uint certifiedCommitteeSize) external override onlyWhenActive onlyCommitteeContract {
        _updateGuardianFeesAndBootstrap(guardian, inCommittee, isCertified, nextCertification, generalCommitteeSize, certifiedCommitteeSize);
    }

    function getFeesAndBootstrapBalance(address guardian) external override view returns (uint256 feeBalance, uint256 bootstrapBalance) {
        FeesAndBootstrap memory guardianFeesAndBootstrap = getGuardianFeesAndBootstrap(guardian);
        return (fromMilliToken(guardianFeesAndBootstrap.feeBalance), fromMilliToken(guardianFeesAndBootstrap.bootstrapBalance));
    }

    function withdrawBootstrapFunds(address guardian) external override onlyWhenActive {
        updateGuardianFeesAndBootstrap(guardian);
        uint256 amount = fromMilliToken(feesAndBootstrap[guardian].bootstrapBalance);
        feesAndBootstrap[guardian].bootstrapBalance = 0;
        emit BootstrapRewardsWithdrawn(guardian, amount);

        require(bootstrapToken.transfer(guardian, amount), "Rewards::withdrawBootstrapFunds - insufficient funds");
    }

    function withdrawFees(address guardian) external override onlyWhenActive {
        updateGuardianFeesAndBootstrap(guardian);

        uint256 amount = fromMilliToken(feesAndBootstrap[guardian].feeBalance);
        feesAndBootstrap[guardian].feeBalance = 0;
        emit FeesWithdrawn(guardian, amount);
        require(erc20.transfer(guardian, amount), "Rewards::withdrawFees - insufficient funds");
    }

    function getFeesAndBootstrapState() external override view returns (
        uint256 certifiedFeesPerMember,
        uint256 generalFeesPerMember,
        uint256 certifiedBootstrapPerMember,
        uint256 generalBootstrapPerMember,
        uint256 lastAssigned
    ) {
        (uint generalCommitteeSize, uint certifiedCommitteeSize, ) = committeeContract.getCommitteeStats();
        (FeesAndBootstrapState memory _feesAndBootstrapState,) = _getFeesAndBootstrapState(generalCommitteeSize, certifiedCommitteeSize, generalFeesWallet.getOutstandingFees(), certifiedFeesWallet.getOutstandingFees(), settings);
        certifiedFeesPerMember = fromMilliToken(_feesAndBootstrapState.certifiedFeesPerMember);
        generalFeesPerMember = fromMilliToken(_feesAndBootstrapState.generalFeesPerMember);
        certifiedBootstrapPerMember = fromMilliToken(_feesAndBootstrapState.certifiedBootstrapPerMember);
        generalBootstrapPerMember = fromMilliToken(_feesAndBootstrapState.generalBootstrapPerMember);
        lastAssigned = _feesAndBootstrapState.lastAssigned;
    }

    function getFeesAndBootstrapData(address guardian) external override view returns (
        uint256 feeBalance,
        uint256 lastFeesPerMember,
        uint256 bootstrapBalance,
        uint256 lastBootstrapPerMember
    ) {
        FeesAndBootstrap memory guardianFeesAndBootstrap = getGuardianFeesAndBootstrap(guardian);
        return (
        fromMilliToken(guardianFeesAndBootstrap.feeBalance),
        fromMilliToken(guardianFeesAndBootstrap.lastFeesPerMember),
        fromMilliToken(guardianFeesAndBootstrap.bootstrapBalance),
        fromMilliToken(guardianFeesAndBootstrap.lastBootstrapPerMember)
        );
    }

    /*
     * Governance functions
     */

    function migrateRewardsBalance(address guardian) external override {
        require(!settings.rewardAllocationActive, "Reward distribution must be deactivated for migration");

        IFeesAndBootstrapRewards currentRewardsContract = IFeesAndBootstrapRewards(getFeesAndBootstrapRewardsContract());
        require(address(currentRewardsContract) != address(this), "New rewards contract is not set");

        updateGuardianFeesAndBootstrap(guardian);

        FeesAndBootstrap memory guardianFeesAndBootstrap = feesAndBootstrap[guardian];
        uint256 fees = fromMilliToken(guardianFeesAndBootstrap.feeBalance);
        uint256 bootstrap = fromMilliToken(guardianFeesAndBootstrap.bootstrapBalance);

        guardianFeesAndBootstrap.feeBalance = 0;
        guardianFeesAndBootstrap.bootstrapBalance = 0;
        feesAndBootstrap[guardian] = guardianFeesAndBootstrap;

        require(erc20.approve(address(currentRewardsContract), fees), "migrateRewardsBalance: approve failed");
        require(bootstrapToken.approve(address(currentRewardsContract), bootstrap), "migrateRewardsBalance: approve failed");
        currentRewardsContract.acceptRewardsBalanceMigration(guardian, fees, bootstrap);

        emit FeesAndBootstrapRewardsBalanceMigrated(guardian, fees, bootstrap, address(currentRewardsContract));
    }

    function acceptRewardsBalanceMigration(address guardian, uint256 fees, uint256 bootstrap) external override {
        FeesAndBootstrap memory guardianFeesAndBootstrap = feesAndBootstrap[guardian];
        guardianFeesAndBootstrap.feeBalance = guardianFeesAndBootstrap.feeBalance.add(toMilliToken(fees));
        guardianFeesAndBootstrap.bootstrapBalance = guardianFeesAndBootstrap.bootstrapBalance.add(toMilliToken(bootstrap));
        feesAndBootstrap[guardian] = guardianFeesAndBootstrap;

        if (fees > 0) {
            require(erc20.transferFrom(msg.sender, address(this), fees), "acceptRewardBalanceMigration: transfer failed");
        }
        if (bootstrap > 0) {
            require(bootstrapToken.transferFrom(msg.sender, address(this), bootstrap), "acceptRewardBalanceMigration: transfer failed");
        }

        emit FeesAndBootstrapRewardsBalanceMigrationAccepted(msg.sender, guardian, fees, bootstrap);
    }

    function activateRewardDistribution(uint startTime) external override onlyMigrationManager {
        feesAndBootstrapState.lastAssigned = uint32(startTime);
        settings.rewardAllocationActive = true;

        emit RewardDistributionActivated(startTime);
    }

    function deactivateRewardDistribution() external override onlyMigrationManager {
        require(settings.rewardAllocationActive, "reward distribution is already deactivated");

        updateFeesAndBootstrapState();

        settings.rewardAllocationActive = false;

        emit RewardDistributionDeactivated();
    }

    function getSettings() external override view returns (
        uint generalCommitteeAnnualBootstrap,
        uint certifiedCommitteeAnnualBootstrap,
        bool rewardAllocationActive
    ) {
        Settings memory _settings = settings;
        generalCommitteeAnnualBootstrap = fromMilliToken(_settings.generalCommitteeAnnualBootstrap);
        certifiedCommitteeAnnualBootstrap = fromMilliToken(_settings.certifiedCommitteeAnnualBootstrap);
        rewardAllocationActive = _settings.rewardAllocationActive;
    }

    function setGeneralCommitteeAnnualBootstrap(uint256 annualAmount) external override onlyFunctionalManager {
        updateFeesAndBootstrapState();
        _setGeneralCommitteeAnnualBootstrap(annualAmount);
    }

    function getGeneralCommitteeAnnualBootstrap() external override view returns (uint256) {
        return fromMilliToken(settings.generalCommitteeAnnualBootstrap);
    }

    function setCertifiedCommitteeAnnualBootstrap(uint256 annualAmount) external override onlyFunctionalManager {
        updateFeesAndBootstrapState();
        _setCertifiedCommitteeAnnualBootstrap(annualAmount);
    }

    function getCertifiedCommitteeAnnualBootstrap() external override view returns (uint256) {
        return fromMilliToken(settings.certifiedCommitteeAnnualBootstrap);
    }

    function emergencyWithdraw() external override onlyMigrationManager {
        emit EmergencyWithdrawal(msg.sender);
        require(erc20.transfer(msg.sender, erc20.balanceOf(address(this))), "Rewards::emergencyWithdraw - transfer failed (fee token)");
        require(bootstrapToken.transfer(msg.sender, bootstrapToken.balanceOf(address(this))), "Rewards::emergencyWithdraw - transfer failed (bootstrap token)");
    }

    /*
    * Private functions
    */

    // Global state

    function _getFeesAndBootstrapState(uint generalCommitteeSize, uint certifiedCommitteeSize, uint256 collectedGeneralFees, uint256 collectedCertifiedFees, Settings memory _settings) private view returns (FeesAndBootstrapState memory _feesAndBootstrapState, uint256 allocatedBootstrap) {
        _feesAndBootstrapState = feesAndBootstrapState;

        if (_settings.rewardAllocationActive) {
            uint48 generalFeesDelta = generalCommitteeSize == 0 ? 0 : toMilliToken(collectedGeneralFees.div(generalCommitteeSize));
            uint48 certifiedFeesDelta = generalFeesDelta.add(certifiedCommitteeSize == 0 ? 0 : toMilliToken(collectedCertifiedFees.div(certifiedCommitteeSize)));

            _feesAndBootstrapState.generalFeesPerMember = _feesAndBootstrapState.generalFeesPerMember.add(generalFeesDelta);
            _feesAndBootstrapState.certifiedFeesPerMember = _feesAndBootstrapState.certifiedFeesPerMember.add(certifiedFeesDelta);

            uint duration = block.timestamp.sub(_feesAndBootstrapState.lastAssigned);
            uint48 generalBootstrapDelta = _settings.generalCommitteeAnnualBootstrap.mul(uint48(duration)).div(365 days);
            uint48 certifiedBootstrapDelta = generalBootstrapDelta.add(_settings.certifiedCommitteeAnnualBootstrap.mul(uint48(duration)).div(365 days));

            _feesAndBootstrapState.generalBootstrapPerMember = _feesAndBootstrapState.generalBootstrapPerMember.add(generalBootstrapDelta);
            _feesAndBootstrapState.certifiedBootstrapPerMember = _feesAndBootstrapState.certifiedBootstrapPerMember.add(certifiedBootstrapDelta);
            _feesAndBootstrapState.lastAssigned = uint32(block.timestamp);

            allocatedBootstrap = fromMilliToken(generalBootstrapDelta).mul(generalCommitteeSize).add(fromMilliToken(certifiedBootstrapDelta).mul(certifiedCommitteeSize));
        }
    }

    function _updateFeesAndBootstrapState(uint generalCommitteeSize, uint certifiedCommitteeSize) private returns (FeesAndBootstrapState memory _feesAndBootstrapState) {
        Settings memory _settings = settings;
        if (!_settings.rewardAllocationActive) {
            return feesAndBootstrapState;
        }

        uint256 collectedGeneralFees = generalFeesWallet.collectFees();
        uint256 collectedCertifiedFees = certifiedFeesWallet.collectFees();
        uint256 allocatedBootstrap;

        (_feesAndBootstrapState, allocatedBootstrap) = _getFeesAndBootstrapState(generalCommitteeSize, certifiedCommitteeSize, collectedGeneralFees, collectedCertifiedFees, _settings);
        bootstrapRewardsWallet.withdraw(allocatedBootstrap);

        feesAndBootstrapState = _feesAndBootstrapState;
    }

    function updateFeesAndBootstrapState() private returns (FeesAndBootstrapState memory _feesAndBootstrapState) {
        (uint generalCommitteeSize, uint certifiedCommitteeSize, ) = committeeContract.getCommitteeStats();
        return _updateFeesAndBootstrapState(generalCommitteeSize, certifiedCommitteeSize);
    }

    // Guardian state

    function _getGuardianFeesAndBootstrap(address guardian, bool inCommittee, bool isCertified, bool nextCertification, FeesAndBootstrapState memory _feesAndBootstrapState) private view returns (FeesAndBootstrap memory guardianFeesAndBootstrap, uint256 addedBootstrapAmount, uint256 addedFeesAmount) {
        guardianFeesAndBootstrap = feesAndBootstrap[guardian];

        if (inCommittee) {
            uint48 bootstrapAmount = (isCertified ? _feesAndBootstrapState.certifiedBootstrapPerMember : _feesAndBootstrapState.generalBootstrapPerMember).sub(guardianFeesAndBootstrap.lastBootstrapPerMember);
            guardianFeesAndBootstrap.bootstrapBalance = guardianFeesAndBootstrap.bootstrapBalance.add(bootstrapAmount);
            addedBootstrapAmount = fromMilliToken(bootstrapAmount);

            uint48 feesAmount = (isCertified ? _feesAndBootstrapState.certifiedFeesPerMember : _feesAndBootstrapState.generalFeesPerMember).sub(guardianFeesAndBootstrap.lastFeesPerMember);
            guardianFeesAndBootstrap.feeBalance = guardianFeesAndBootstrap.feeBalance.add(feesAmount);
            addedFeesAmount = fromMilliToken(feesAmount);
        }

        guardianFeesAndBootstrap.lastBootstrapPerMember = nextCertification ?  _feesAndBootstrapState.certifiedBootstrapPerMember : _feesAndBootstrapState.generalBootstrapPerMember;
        guardianFeesAndBootstrap.lastFeesPerMember = nextCertification ?  _feesAndBootstrapState.certifiedFeesPerMember : _feesAndBootstrapState.generalFeesPerMember;
    }

    function _updateGuardianFeesAndBootstrap(address guardian, bool inCommittee, bool isCertified, bool nextCertification, uint generalCommitteeSize, uint certifiedCommitteeSize) private {
        uint256 addedBootstrapAmount;
        uint256 addedFeesAmount;

        FeesAndBootstrapState memory _feesAndBootstrapState = _updateFeesAndBootstrapState(generalCommitteeSize, certifiedCommitteeSize);
        (feesAndBootstrap[guardian], addedBootstrapAmount, addedFeesAmount) = _getGuardianFeesAndBootstrap(guardian, inCommittee, isCertified, nextCertification, _feesAndBootstrapState);

        emit BootstrapRewardsAssigned(guardian, addedBootstrapAmount);
        emit FeesAssigned(guardian, addedFeesAmount);
    }

    function getGuardianFeesAndBootstrap(address guardian) private view returns (FeesAndBootstrap memory guardianFeesAndBootstrap) {
        ICommittee _committeeContract = committeeContract;
        (uint generalCommitteeSize, uint certifiedCommitteeSize, ) = _committeeContract.getCommitteeStats();
        (FeesAndBootstrapState memory _feesAndBootstrapState,) = _getFeesAndBootstrapState(generalCommitteeSize, certifiedCommitteeSize, generalFeesWallet.getOutstandingFees(), certifiedFeesWallet.getOutstandingFees(), settings);
        (bool inCommittee, , bool isCertified,) = _committeeContract.getMemberInfo(guardian);
        (guardianFeesAndBootstrap, ,) = _getGuardianFeesAndBootstrap(guardian, inCommittee, isCertified, isCertified, _feesAndBootstrapState);
    }

    function updateGuardianFeesAndBootstrap(address guardian) private {
        ICommittee _committeeContract = committeeContract;
        (uint generalCommitteeSize, uint certifiedCommitteeSize, ) = _committeeContract.getCommitteeStats();
        (bool inCommittee, , bool isCertified,) = _committeeContract.getMemberInfo(guardian);
        _updateGuardianFeesAndBootstrap(guardian, inCommittee, isCertified, isCertified, generalCommitteeSize, certifiedCommitteeSize);
    }

    // Governance and misc.

    function _setGeneralCommitteeAnnualBootstrap(uint256 annualAmount) private {
        settings.generalCommitteeAnnualBootstrap = toMilliToken(annualAmount);
        emit GeneralCommitteeAnnualBootstrapChanged(annualAmount);
    }

    function _setCertifiedCommitteeAnnualBootstrap(uint256 annualAmount) private {
        settings.certifiedCommitteeAnnualBootstrap = toMilliToken(annualAmount);
        emit CertifiedCommitteeAnnualBootstrapChanged(annualAmount);
    }

    function toMilliToken(uint256 v) internal pure returns (uint48) {
        return uint48(v / TOKEN_GRANULARITY);
    }

    function fromMilliToken(uint48 v) internal pure returns (uint256) {
        return uint256(v) * TOKEN_GRANULARITY;
    }

    /*
     * Contracts topology / registry interface
     */

    ICommittee committeeContract;
    IFeesWallet generalFeesWallet;
    IFeesWallet certifiedFeesWallet;
    IProtocolWallet bootstrapRewardsWallet;
    function refreshContracts() external override {
        committeeContract = ICommittee(getCommitteeContract());
        generalFeesWallet = IFeesWallet(getGeneralFeesWallet());
        certifiedFeesWallet = IFeesWallet(getCertifiedFeesWallet());
        bootstrapRewardsWallet = IProtocolWallet(getBootstrapRewardsWallet());
    }
}
