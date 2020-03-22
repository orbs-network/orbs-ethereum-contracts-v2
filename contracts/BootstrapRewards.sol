pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./spec_interfaces/IContractRegistry.sol";
import "./interfaces/IElections.sol";
import "./spec_interfaces/IBootstrapRewards.sol";

contract BootstrapRewards is IBootstrapRewards, Ownable {
    using SafeMath for uint256;

    IContractRegistry contractRegistry;

    uint256 pool;

    uint256 generalCommitteeAnnualBootstrap;
    uint256 complianceCommitteeAnnualBootstrap; // todo - assign rewards to compliance committee

    uint256 lastPayedAt;

    mapping(address => uint256) bootstrapBalance;

    IERC20 bootstrapToken;
    address rewardsGovernor;

    modifier onlyRewardsGovernor() {
        require(msg.sender == rewardsGovernor, "caller is not the rewards governor");

        _;
    }

    constructor(IERC20 _bootstrapToken, address _rewardsGovernor) public {
        require(address(_bootstrapToken) != address(0), "bootstrapToken must not be 0");

        bootstrapToken = _bootstrapToken;
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
        uint256 duration = now.sub(lastPayedAt);

        address[] memory currentCommittee = _getCommittee(); //todo: also assign to compliance committee
        if (currentCommittee.length > 0) {
            uint256 amountPerValidator = Math.min(generalCommitteeAnnualBootstrap.mul(duration).div(365 days), pool.div(currentCommittee.length));
            pool = pool.sub(amountPerValidator * currentCommittee.length);

            uint256[] memory assignedRewards = new uint256[](currentCommittee.length);

            for (uint i = 0; i < currentCommittee.length; i++) {
                addToBalance(currentCommittee[i], amountPerValidator);
                assignedRewards[i] = amountPerValidator;
            }

            emit BootstrapRewardsAssigned(currentCommittee, assignedRewards);
        }
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

    function _getCommittee() private view returns (address[] memory) {
        // todo - use committee contracts, for both general and kyc committees
        IElections e = IElections(contractRegistry.get("elections"));
        (address[] memory validators, ) =  e.getCommittee();
        return validators;
    }

}
