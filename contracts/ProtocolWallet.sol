// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./spec_interfaces/IProtocolWallet.sol";
import "./WithClaimableMigrationOwnership.sol";
import "./WithClaimableFunctionalOwnership.sol";

/// @title Protocol Wallet contract
/// @dev the protocol wallet utilizes two claimable owners: migrationOwner and functionalOwner
contract ProtocolWallet is IProtocolWallet, WithClaimableMigrationOwnership, WithClaimableFunctionalOwnership {
    using SafeMath for uint256;

    IERC20 public token;
    address public client;
    uint256 public lastWithdrawal;
    uint256 maxAnnualRate;

    /// Constructor
    /// @param _token is the wallet token
    /// @param _client is the initial wallet client address
    /// @param _maxAnnualRate is the maximum annual rate that can be withdrawn
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

    /// Returns the address of the underlying staked token
    /// @return balance is the wallet balance
    function getBalance() public override view returns (uint256 balance) {
        return token.balanceOf(address(this));
    }

    /// Transfers the given amount of orbs tokens form the sender to this contract and updates the pool
    /// @dev assumes the caller approved the amount prior to calling
    /// @param amount is the amount to add to the wallet
    function topUp(uint256 amount) external override {
        emit FundsAddedToPool(amount, getBalance().add(amount));
        require(token.transferFrom(msg.sender, address(this), amount), "ProtocolWallet::topUp - insufficient allowance");
    }

    /// Withdraws from pool to the client address, limited by the pool's MaxRate.
    /// @dev may only be called by the wallet client
    /// @dev no more than MaxRate x time period since the last withdraw may be withdrawn
    /// @dev allocation that wasn't withdrawn can not be withdrawn in the next call
    /// @param amount is the amount to withdraw
    function withdraw(uint256 amount) external override onlyClient {
        uint256 _lastWithdrawal = lastWithdrawal;
        require(_lastWithdrawal <= block.timestamp, "withdrawal is not yet active");

        uint duration = block.timestamp.sub(_lastWithdrawal);
        require(amount.mul(365 * 24 * 60 * 60) <= maxAnnualRate.mul(duration), "ProtocolWallet::withdraw - requested amount is larger than allowed by rate");

        lastWithdrawal = block.timestamp;
        if (amount > 0) {
            require(token.transfer(msg.sender, amount), "ProtocolWallet::withdraw - transfer failed");
        }
    }

    /*
    * Governance functions
    */

    /// Sets a new annual withdraw rate for the pool
    /// @dev governance function called only by the migration owner
    /// @dev the rate for a duration is duration x annualRate / 1 year
    /// @param _annualRate is the maximum annual rate that can be withdrawn
    function setMaxAnnualRate(uint256 _annualRate) public override onlyMigrationOwner {
        maxAnnualRate = _annualRate;
        emit MaxAnnualRateSet(_annualRate);
    }

    /// Returns the annual withdraw rate of the pool
    /// @return annualRate is the maximum annual rate that can be withdrawn
    function getMaxAnnualRate() external override view returns (uint256) {
        return maxAnnualRate;
    }

    /// Resets the outstanding tokens to new start time
    /// @dev governance function called only by the migration owner
    /// @dev the next duration will be calculated starting from the given time
    /// @param startTime is the time to set as the last withdrawal time
    function resetOutstandingTokens(uint256 startTime) external override onlyMigrationOwner {
        lastWithdrawal = startTime;
        emit OutstandingTokensReset(startTime);
    }

    /// Emergency withdraw the wallet funds
    /// @dev governance function called only by the migration owner
    /// @dev used in emergencies, when a migration to a new wallet is needed
    /// @param erc20 is the erc20 address of the token to withdraw
    function emergencyWithdraw(address erc20) external override onlyMigrationOwner {
        IERC20 _token = IERC20(erc20);
        emit EmergencyWithdrawal(msg.sender, address(_token));
        require(_token.transfer(msg.sender, _token.balanceOf(address(this))), "FeesWallet::emergencyWithdraw - transfer failed");
    }

    /// Sets the address of the client that can withdraw funds
    /// @dev governance function called only by the functional owner
    /// @param _client is the address of the new client
    function setClient(address _client) external override onlyFunctionalOwner {
        client = _client;
        emit ClientSet(_client);
    }
}
