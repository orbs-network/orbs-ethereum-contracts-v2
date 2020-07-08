pragma solidity 0.5.16;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./spec_interfaces/IProtocolWallet.sol";
import "./WithClaimableMigrationOwnership.sol";
import "./WithClaimableFunctionalOwnership.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract ProtocolWallet is IProtocolWallet, WithClaimableMigrationOwnership, WithClaimableFunctionalOwnership{
    using SafeMath for uint256;

    IERC20 public token;
    address public client;

    uint lastApprovedAt;
    uint annualRate;

    modifier onlyClient() {
        require(msg.sender == client, "caller is not the wallet client");

        _;
    }

    constructor(IERC20 _token, address _client) public {
        token = _token;
        client = _client;
        lastApprovedAt = now; // TODO init here, or in first call to setMaxAnnualRate?
    }

    /// @dev Returns the address of the underlying staked token.
    /// @return IERC20 The address of the token.
    function getToken() external view returns (IERC20) {
        return token;
    }

    /// @dev Returns the address of the underlying staked token.
    /// @return IERC20 The address of the token.
    function getBalance() public view returns (uint256 balance) {
        return token.balanceOf(address(this));
    }

    /// @dev Transfers the given amount of orbs tokens form the sender to this contract an update the pool.
    function topUp(uint256 amount) external {
        emit FundsAddedToPool(amount, getBalance() + amount);
        require(token.transferFrom(msg.sender, address(this), amount), "ProtocolWallet::topUp - insufficient allowance");
    }

    /// @dev Approves withdraw from pool to a spender, limited by the pool's MaxRate.
    /// A maximum of MaxRate x time period since the last Orbs transfer may be transferred out.
    /// Flow:
    /// PoolWallet.approveTransfer(amount);
    /// ERC20.transferFrom(PoolWallet, client, amount)
    function withdraw(uint256 amount) external onlyClient {
        uint duration = now - lastApprovedAt;
        uint maxAmount = duration.mul(annualRate).div(365 * 24 * 60 * 60);
        require(amount <= maxAmount, "ProtocolWallet:approve - requested amount is larger than allowed by rate");

        lastApprovedAt = now;
        require(token.transfer(msg.sender, amount), "ProtocolWallet::withdraw - transfer failed"); // TODO May skip the transfer on amount == 0.
    }

    /* Governance */
    /// @dev Sets a new transfer rate for the Orbs pool.
    function setMaxAnnualRate(uint256 _annualRate) external onlyMigrationOwner {
        annualRate = _annualRate;
        emit MaxAnnualRateSet(_annualRate);
    }

    /// @dev transfer the entire pool's balance to a new wallet.
    function emergencyWithdraw() external onlyMigrationOwner {
        emit EmergencyWithdrawal(msg.sender);
        require(token.transfer(msg.sender, getBalance()), "ProtocolWallet::emergencyWithdraw - transfer failed");
    }

    /// @dev sets the address of the new contract
    function setClient(address _client) external onlyFunctionalOwner {
        client = _client;
        emit ClientSet(_client);
    }
}
