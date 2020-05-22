pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./spec_interfaces/IContractRegistry.sol";
import "./spec_interfaces/IBootstrapRewards.sol";
import "./spec_interfaces/ICommittee.sol";
import "./ContractRegistryAccessor.sol";

contract BootstrapRewards is IBootstrapRewards, ContractRegistryAccessor {
    using SafeMath for uint256;

    uint256 pool;

    uint256 generalCommitteeAnnualBootstrap;
    uint256 complianceCommitteeAnnualBootstrap;

    uint256 lastPayedAt;

    mapping(address => uint256) bootstrapBalance;

    IERC20 bootstrapToken;
    address rewardsGovernor;

    modifier onlyElectionsContract() {
        require(msg.sender == address(getElectionsContract()), "caller is not the elections");

        _;
    }

    // TODO - add functionality similar to ownable (transfer governance, etc)
    modifier onlyRewardsGovernor() {
        require(msg.sender == rewardsGovernor, "caller is not the rewards governor");

        _;
    }

    constructor(IERC20 _bootstrapToken, address _rewardsGovernor) public {
        require(address(_bootstrapToken) != address(0), "bootstrapToken must not be 0");

        bootstrapToken = _bootstrapToken;
        // TODO - The initial lastPayedAt should be set in the first assignRewards.
        lastPayedAt = now;
        rewardsGovernor = _rewardsGovernor;
    }

    function setGeneralCommitteeAnnualBootstrap(uint256 annual_amount) external {
        (address[] memory generalCommittee,, bool[] memory compliance) = getCommitteeContract().getCommittee();
        _assignRewards(generalCommittee, compliance);
        generalCommitteeAnnualBootstrap = annual_amount;
    }

    function setComplianceCommitteeAnnualBootstrap(uint256 annual_amount) external {
        (address[] memory generalCommittee,, bool[] memory compliance) = getCommitteeContract().getCommittee();
        _assignRewards(generalCommittee, compliance);
        complianceCommitteeAnnualBootstrap = annual_amount;
    }

    function topUpBootstrapPool(uint256 amount) external {
        pool = pool.add(amount);
        require(bootstrapToken.transferFrom(msg.sender, address(this), amount), "Rewards::topUpFixedPool - insufficient allowance");
        emit BootstrapAddedToPool(amount, pool);
    }

    function getBootstrapBalance(address addr) external view returns (uint256) {
        return bootstrapBalance[addr];
    }

    function getLastBootstrapAssignment() external view returns (uint256) {
        return lastPayedAt;
    }

    function assignRewards(address[] calldata generalCommittee, bool[] calldata compliance) external onlyElectionsContract {
        _assignRewards(generalCommittee, compliance);
    }

    function _assignRewards(address[] memory committee, bool[] memory compliance) private {
        if (committee.length > 0) {
            uint nCompliance = 0;
            for (uint i = 0; i < committee.length; i++) {
                if (compliance[i]) nCompliance++;
            }

            uint256 duration = now.sub(lastPayedAt);
            uint256 amountPerGeneralValidator = Math.min(generalCommitteeAnnualBootstrap.mul(duration).div(365 days), pool.div(committee.length));
            uint256 amountPerCompliantValidator = nCompliance == 0 ? 0 :
                Math.min(complianceCommitteeAnnualBootstrap.mul(duration).div(365 days), pool.div(nCompliance));

            pool = pool.sub(amountPerGeneralValidator * committee.length).sub(amountPerCompliantValidator * nCompliance);

            uint256[] memory assignedRewards = new uint256[](committee.length);
            for (uint i = 0; i < committee.length; i++) {
                assignedRewards[i] = amountPerGeneralValidator + (compliance[i] ? amountPerCompliantValidator : 0);
                addToBalance(committee[i], assignedRewards[i]);
            }

            emit BootstrapRewardsAssigned(committee, assignedRewards, lastPayedAt); // TODO separate event per committee?
        }
        // todo compliance committee
        lastPayedAt = now;
    }

    function addToBalance(address addr, uint256 amount) private {
        bootstrapBalance[addr] = bootstrapBalance[addr].add(amount);
    }

    function withdrawFunds() external {
        uint256 amount = bootstrapBalance[msg.sender];
        bootstrapBalance[msg.sender] = bootstrapBalance[msg.sender].sub(amount);
        require(bootstrapToken.transfer(msg.sender, amount), "Rewards::claimbootstrapTokenRewards - insufficient funds");
    }

}
