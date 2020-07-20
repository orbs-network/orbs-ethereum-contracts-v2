pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./spec_interfaces/IContractRegistry.sol";
import "./spec_interfaces/ICommittee.sol";
import "./spec_interfaces/IProtocolWallet.sol";
import "./ContractRegistryAccessor.sol";
import "./Erc20AccessorWithTokenGranularity.sol";
import "./WithClaimableFunctionalOwnership.sol";
import "./spec_interfaces/IGuardiansWallet.sol";
import "./spec_interfaces/IFeesWallet.sol";

contract Rewards is IRewards, ContractRegistryAccessor, ERC20AccessorWithTokenGranularity, WithClaimableFunctionalOwnership, Lockable {
    using SafeMath for uint256;
    using SafeMath for uint48;

    struct Settings {
        uint48 generalCommitteeAnnualBootstrap;
        uint48 certificationCommitteeAnnualBootstrap;
        uint48 annualRateInPercentMille;
        uint48 annualCap;
    }
    Settings settings;

    IERC20 bootstrapToken;
    IERC20 erc20;

    uint256 lastAssignedAt;

    modifier onlyCommitteeContract() {
        require(msg.sender == address(getCommitteeContract()), "caller is not the committee contract");

        _;
    }

    constructor(IERC20 _erc20, IERC20 _bootstrapToken) public {
        require(address(_bootstrapToken) != address(0), "bootstrapToken must not be 0");
        require(address(_erc20) != address(0), "erc20 must not be 0");

        erc20 = _erc20;
        bootstrapToken = _bootstrapToken;

        // TODO - The initial lastPayedAt should be set in the first assignRewards.
        lastAssignedAt = now;
    }

    // bootstrap rewards

    function setGeneralCommitteeAnnualBootstrap(uint256 annual_amount) external onlyFunctionalOwner onlyWhenActive {
        settings.generalCommitteeAnnualBootstrap = toUint48Granularity(annual_amount);
    }

    function setCertificationCommitteeAnnualBootstrap(uint256 annual_amount) external onlyFunctionalOwner onlyWhenActive {
        settings.certificationCommitteeAnnualBootstrap = toUint48Granularity(annual_amount);
    }

    function assignRewards() public onlyWhenActive {
        (address[] memory committee, uint256[] memory weights, bool[] memory certification) = getCommitteeContract().getCommittee();
        _assignRewardsToCommittee(committee, weights, certification);
    }

    function assignRewardsToCommittee(address[] calldata committee, uint256[] calldata committeeWeights, bool[] calldata certification) external onlyCommitteeContract onlyWhenActive {
        _assignRewardsToCommittee(committee, committeeWeights, certification);
    }

    function _assignRewardsToCommittee(address[] memory committee, uint256[] memory committeeWeights, bool[] memory certification) private {
        Settings memory _settings = settings;
        IGuardiansWallet guardiansWallet = getGuardiansWallet();

        (uint256[] memory bootstrapRewards, uint256 totalBootstrapRewards) = collectBootstrapRewards(_settings, committee, certification);
        (uint256[] memory fees, uint256 totalGeneralFees, uint256 totalCertifiedFees) = collectFees(committee, certification);
        (uint256[] memory stakingRewards, uint256 totalStakingRewards) = collectStakingRewards(committee, committeeWeights, _settings);

        lastAssignedAt = now;

        IProtocolWallet stakingRewardsWallet = getStakingRewardsWallet();
        IProtocolWallet bootstrapRewardsWallet = getBootstrapRewardsWallet();
        stakingRewardsWallet.approve(address(guardiansWallet), totalStakingRewards);
        bootstrapRewardsWallet.approve(address(guardiansWallet), totalBootstrapRewards);

        erc20.transferFrom(address(getGeneralFeesWallet()), address(this), totalGeneralFees);
        erc20.transferFrom(address(getCertifiedFeesWallet()), address(this), totalCertifiedFees);
        erc20.approve(address(guardiansWallet), totalGeneralFees.add(totalCertifiedFees));

        guardiansWallet.assignRewardsToGuardians(committee, stakingRewards, address(stakingRewardsWallet), fees, address(this), bootstrapRewards, address(bootstrapRewardsWallet));
    }

    function collectBootstrapRewards(Settings memory _settings, address[] memory committee, bool[] memory certification) private view returns (uint256[] memory bootstrapRewards, uint256 totalBootstrapRewards){
        bootstrapRewards = new uint256[](committee.length);
        uint256 duration = now.sub(lastAssignedAt);

        uint256 generalGuardianBootstrap = toUint256Granularity(uint48(_settings.generalCommitteeAnnualBootstrap.mul(duration).div(365 days)));
        uint256 certifiedGuardianBootstrap = generalGuardianBootstrap + toUint256Granularity(uint48(_settings.certificationCommitteeAnnualBootstrap.mul(duration).div(365 days)));

        for (uint i = 0; i < committee.length; i++) {
            bootstrapRewards[i] = certification[i] ? certifiedGuardianBootstrap : generalGuardianBootstrap;
            totalBootstrapRewards = totalBootstrapRewards.add(bootstrapRewards[i]);
        }
    }

    // staking rewards

    function setAnnualStakingRewardsRate(uint256 annual_rate_in_percent_mille, uint256 annual_cap) external onlyFunctionalOwner onlyWhenActive {
        Settings memory _settings = settings;
        _settings.annualRateInPercentMille = uint48(annual_rate_in_percent_mille);
        _settings.annualCap = toUint48Granularity(annual_cap);
        settings = _settings;
    }

    function getLastRewardAssignmentTime() external view returns (uint256) {
        return lastAssignedAt;
    }

    function collectStakingRewards(address[] memory committee, uint256[] memory weights, Settings memory _settings) private view returns (uint256[] memory assignedRewards, uint256 totalStakingRewards) {
        // TODO we often do integer division for rate related calculation, which floors the result. Do we need to address this?
        // TODO for an empty committee or a committee with 0 total stake the divided amounts will be locked in the contract FOREVER
        assignedRewards = new uint256[](committee.length);

        uint256 totalWeight = 0;
        for (uint i = 0; i < committee.length; i++) {
            totalWeight = totalWeight.add(weights[i]);
        }

        if (totalWeight > 0) { // TODO - handle the case of totalStake == 0. consider also an empty committee. consider returning a boolean saying if the amount was successfully distributed or not and handle on caller side.
            uint256 duration = now.sub(lastAssignedAt);

            uint annualRateInPercentMille = Math.min(uint(_settings.annualRateInPercentMille), toUint256Granularity(_settings.annualCap).mul(100000).div(totalWeight)); // todo make 100000 constant?
            for (uint i = 0; i < committee.length; i++) {
                assignedRewards[i] = toUint256Granularity(toUint48Granularity(weights[i].mul(annualRateInPercentMille).mul(duration).div(36500000 days)));
                totalStakingRewards += assignedRewards[i];
            }
        }
    }

    function collectFees(address[] memory committee, bool[] memory certification) private returns (uint256[] memory fees, uint256 totalGeneralFees, uint256 totalCertifiedFees) {
        uint generalFeePoolAmount = getGeneralFeesWallet().collectFees(address(this));
        uint certificationFeePoolAmount = getCertifiedFeesWallet().collectFees(address(this));

        uint256 generalGuardianFee = divideFees(committee, certification, generalFeePoolAmount, false);
        uint256 certifiedGuardianFee = divideFees(committee, certification, certificationFeePoolAmount, true);

        fees = new uint256[](committee.length);
        uint fee;
        for (uint i = 0; i < committee.length; i++) {
            fee = generalGuardianFee;
            totalGeneralFees = totalGeneralFees.add(generalGuardianFee);
            if (certification[i]) {
                fee = fee.add(certifiedGuardianFee);
                totalCertifiedFees = totalCertifiedFees.add(certifiedGuardianFee);
            }
            fees[i] = fee;
        }
    }

    function divideFees(address[] memory committee, bool[] memory certification, uint256 amount, bool isCertified) private returns (uint256 guardianFee) {
        uint n = committee.length;
        if (isCertified)  {
            n = 0;
            for (uint i = 0; i < committee.length; i++) {
                if (certification[i]) n++;
            }
        }
        if (n > 0) {
            guardianFee = toUint256Granularity(toUint48Granularity(amount.div(n)));
        }
    }

}
