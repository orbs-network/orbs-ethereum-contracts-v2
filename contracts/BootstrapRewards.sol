pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./spec_interfaces/IContractRegistry.sol";
import "./spec_interfaces/IBootstrapRewards.sol";
import "./spec_interfaces/ICommittee.sol";

contract BootstrapRewards is IBootstrapRewards, Ownable {
    using SafeMath for uint256;

    IContractRegistry contractRegistry;

    uint256 pool;

    uint256 generalCommitteeAnnualBootstrap;
    uint256 complianceCommitteeAnnualBootstrap;

    uint256 lastPayedAt;

    mapping(address => uint256) bootstrapBalance;

    IERC20 bootstrapToken;
    address rewardsGovernor;

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

    function setContractRegistry(IContractRegistry _contractRegistry) external onlyOwner {
        require(address(_contractRegistry) != address(0), "contractRegistry must not be 0");
        contractRegistry = _contractRegistry;
    }

    function setGeneralCommitteeAnnualBootstrap(uint256 annual_amount) external {
        _assignRewards();
        generalCommitteeAnnualBootstrap = annual_amount;
    }

    function setComplianceCommitteeAnnualBootstrap(uint256 annual_amount) external {
        _assignRewards();
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

    function assignRewards() external {
        _assignRewards();
    }

    function _assignRewards() private {
        _assignRewardsToCommittee(_getGeneralCommittee(), generalCommitteeAnnualBootstrap);
        _assignRewardsToCommittee(_getComplianceCommittee(), complianceCommitteeAnnualBootstrap);

        lastPayedAt = now;
    }

    function _assignRewardsToCommittee(address[] memory committee, uint256 annualBootstrapRewards) private {
        if (committee.length > 0) {
            uint256 duration = now.sub(lastPayedAt);
            uint256 amountPerValidator = Math.min(annualBootstrapRewards.mul(duration).div(365 days), pool.div(committee.length));
            pool = pool.sub(amountPerValidator * committee.length);

            uint256[] memory assignedRewards = new uint256[](committee.length);

            for (uint i = 0; i < committee.length; i++) {
                addToBalance(committee[i], amountPerValidator);
                assignedRewards[i] = amountPerValidator;
            }

            emit BootstrapRewardsAssigned(committee, assignedRewards); // TODO separate event per committee?
        }
    }

    function addToBalance(address addr, uint256 amount) private {
        bootstrapBalance[addr] = bootstrapBalance[addr].add(amount);
    }

    function withdrawFunds() external {
        uint256 amount = bootstrapBalance[msg.sender];
        bootstrapBalance[msg.sender] = bootstrapBalance[msg.sender].sub(amount);
        require(bootstrapToken.transfer(msg.sender, amount), "Rewards::claimbootstrapTokenRewards - insufficient funds");
    }

    function _getCommittee(string memory committeeContract) private view returns (address[] memory) {
        ICommittee e = ICommittee(contractRegistry.get(committeeContract));
        (address[] memory validators,) = e.getCommittee();
        return validators;
    }

    function _getGeneralCommittee() private view returns (address[] memory) {
        return _getCommittee("committee-general");
    }

    function _getComplianceCommittee() private view returns (address[] memory) {
        return _getCommittee("committee-compliance");
    }

}
