pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./IStakingContract.sol";
import "./interfaces/IContractRegistry.sol";
import "./interfaces/IElections.sol";

contract StakingRewards is Ownable {
    using SafeMath for uint256;

    IContractRegistry contractRegistry;

    uint256 pool;
    uint256 poolMonthlyRate;

    uint256 lastPayedAt;

    mapping(address => uint256) orbsBalance;

    IERC20 erc20;
    address rewardsGovernor;

    modifier onlyRewardsGovernor() {
        require(msg.sender == rewardsGovernor, "caller is not the rewards governor");

        _;
    }

    constructor(IERC20 _erc20, address _rewardsGovernor) public {
        require(address(_erc20) != address(0), "erc20 must not be 0");

        erc20 = _erc20;
        lastPayedAt = now;
        rewardsGovernor = _rewardsGovernor;
    }

    function setContractRegistry(IContractRegistry _contractRegistry) external onlyOwner {
        require(address(_contractRegistry) != address(0), "contractRegistry must not be 0");
        contractRegistry = _contractRegistry;
    }

    function setPoolMonthlyRate(uint256 rate) external onlyRewardsGovernor {
        _assignRewards();
        poolMonthlyRate = rate;
    }

    function topUpPool(uint256 amount) external {
        pool = pool.add(amount);
        require(erc20.transferFrom(msg.sender, address(this), amount), "Rewards::topUpProRataPool - insufficient allowance");
    }

    function getOrbsBalance(address addr) external view returns (uint256) {
        return orbsBalance[addr];
    }

    function getLastPayedAt() external view returns (uint256) {
        return lastPayedAt;
    }

    function assignRewards() external {
        _assignRewards();
    }

    function _assignRewards() private {
        // TODO we often do integer division for rate related calculation, which floors the result. Do we need to address this?
        // TODO for an empty committee or a committee with 0 total stake the divided amounts will be locked in the contract FOREVER

        uint256 duration = now.sub(lastPayedAt);

        uint256 amount = Math.min(poolMonthlyRate.mul(duration).div(30 days), pool);
        assignAmountProRata(amount);
        pool = pool.sub(amount);

        lastPayedAt = now;
    }

    function addToBalance(address addr, uint256 amount) private {
        orbsBalance[addr] = orbsBalance[addr].add(amount);
    }

    function assignAmountProRata(uint256 amount) private {
        (address[] memory validators, uint256[] memory weights) = _getCommittee();

        uint256 totalAssigned = 0;
        uint256 totalStake = 0;
        for (uint i = 0; i < validators.length; i++) {
            totalStake = totalStake.add(weights[i]);
        }

        if (totalStake == 0) { // TODO - handle this case. consider also an empty committee. consider returning a boolean saying if the amount was successfully distributed or not and handle on caller side.
            return;
        }

        for (uint i = 0; i < validators.length; i++) {
            uint256 curAmount = amount.mul(weights[i]).div(totalStake);
            address curAddr = validators[i];
            addToBalance(curAddr, curAmount);
            totalAssigned = totalAssigned.add(curAmount);
        }

        uint256 remainder = amount.sub(totalAssigned);
        if (remainder > 0 && validators.length > 0) {
            address addr = validators[now % validators.length];
            addToBalance(addr, remainder);
        }
    }

    function distributeOrbsTokenRewards(address[] calldata to, uint256[] calldata amounts) external {
        require(to.length == amounts.length, "expected to and amounts to be of same length");

        uint256 totalAmount = 0;
        for (uint i = 0; i < to.length; i++) {
            totalAmount = totalAmount.add(amounts[i]);
        }
        require(totalAmount <= orbsBalance[msg.sender], "not enough balance for this distribution");
        orbsBalance[msg.sender] = orbsBalance[msg.sender].sub(totalAmount);

        IStakingContract stakingContract = IStakingContract(contractRegistry.get("staking"));
        erc20.approve(address(stakingContract), totalAmount);
        stakingContract.distributeRewards(totalAmount, to, amounts);
    }

    function _getCommittee() private view returns (address[] memory, uint256[] memory weights) {
        // todo - use committee contracts, for both general and kyc committees
        IElections e = IElections(contractRegistry.get("elections"));
        return e.getCommittee();
    }

}
