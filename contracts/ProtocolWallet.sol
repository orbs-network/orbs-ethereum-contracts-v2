// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./spec_interfaces/IProtocolWallet.sol";
import "./WithClaimableMigrationOwnership.sol";
import "./WithClaimableFunctionalOwnership.sol";

contract ProtocolWallet is IProtocolWallet, WithClaimableMigrationOwnership, WithClaimableFunctionalOwnership {
    using SafeMath for uint256;

    IERC20 public token;
    address public client;
    uint256 public lastWithdrawal;
    uint256 maxAnnualRate;

    constructor(IERC20 _token, address _client, uint256 _maxAnnualRate) public {
        token = _token;
        client = _client;
        lastWithdrawal = block.timestamp;

        setMaxAnnualRate(_maxAnnualRate);
    }

    modifier onlyClient() {
        require(msg.sender == client, "caller is not the wallet client");

        _;
    }

    /*
    * External functions
    */

    /// @dev Returns the address of the underlying staked token.
    /// @return balance IERC20 The address of the token.
    function getBalance() public override view returns (uint256 balance) {
        return token.balanceOf(address(this));
    }

    /// @dev Transfers the given amount of orbs tokens form the sender to this contract an update the pool.
    function topUp(uint256 amount) external override {
        emit FundsAddedToPool(amount, getBalance().add(amount));
        require(token.transferFrom(msg.sender, address(this), amount), "ProtocolWallet::topUp - insufficient allowance");
    }

    /// @dev withdraws from the pool to a spender, limited by the pool's MaxRate.
    /// A maximum of MaxRate x time period since the last Orbs transfer may be transferred out.
    function withdraw(uint256 amount) external override onlyClient {
        uint256 _lastWithdrawal = lastWithdrawal;
        require(_lastWithdrawal <= block.timestamp, "withdrawal is not yet active");

        uint duration = block.timestamp.sub(_lastWithdrawal);
        uint maxAmount = duration.mul(maxAnnualRate).div(365 * 24 * 60 * 60);
        require(amount <= maxAmount, "ProtocolWallet::withdraw - requested amount is larger than allowed by rate");

        lastWithdrawal = block.timestamp;
        if (amount > 0) {
            require(token.transfer(msg.sender, amount), "ProtocolWallet::withdraw - transfer failed");
        }
    }

    /*
    * Governance functions
    */

    /// @dev Sets a new transfer rate for the Orbs pool.
    function setMaxAnnualRate(uint256 _annualRate) public override onlyMigrationOwner {
        maxAnnualRate = _annualRate;
        emit MaxAnnualRateSet(_annualRate);
    }

    function getMaxAnnualRate() external override view returns (uint256) {
        return maxAnnualRate;
    }

    /// @dev Sets a new transfer rate for the Orbs pool.
    function resetOutstandingTokens(uint256 startTime) external override onlyMigrationOwner {
        lastWithdrawal = startTime;
        emit OutstandingTokensReset(startTime);
    }

    /// @dev transfer the entire pool's balance to a new wallet.
    function emergencyWithdraw(address erc20) external override onlyMigrationOwner {
        IERC20 _token = IERC20(erc20);
        emit EmergencyWithdrawal(msg.sender, address(_token));
        require(_token.transfer(msg.sender, _token.balanceOf(address(this))), "FeesWallet::emergencyWithdraw - transfer failed");
    }

    /// @dev sets the address of the new contract
    function setClient(address _client) external override onlyFunctionalOwner {
        client = _client;
        emit ClientSet(_client);
    }
}
