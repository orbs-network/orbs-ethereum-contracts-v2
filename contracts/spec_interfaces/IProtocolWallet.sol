// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Protocol Wallet interface
interface IProtocolWallet {
    event FundsAddedToPool(uint256 added, uint256 total);

    /*
    * External functions
    */

    /// Returns the address of the underlying staked token
    /// @return balance is the wallet balance
    function getBalance() external view returns (uint256 balance);

    /// Transfers the given amount of orbs tokens form the sender to this contract an updates the pool
    /// @dev assumes the caller approved the amount prior to calling
    /// @param amount is the amount to add to the wallet
    function topUp(uint256 amount) external;

    /// Withdraws from pool to the client address, limited by the pool's MaxRate.
    /// @dev may only be called by the wallet client
    /// @dev no more than MaxRate x time period since the last withdraw may be withdrawn
    /// @dev allocation that wasn't withdrawn can not be withdrawn in the next call
    /// @param amount is the amount to withdraw
    function withdraw(uint256 amount) external; /* onlyClient */


    /*
    * Governance functions
    */

    event ClientSet(address client);
    event MaxAnnualRateSet(uint256 maxAnnualRate);
    event EmergencyWithdrawal(address addr, address token);
    event OutstandingTokensReset(uint256 startTime);

    /// Sets a new annual withdraw rate for the pool
    /// @dev governance function called only by the migration owner
    /// @dev the rate for a duration is duration x annualRate / 1 year 
    /// @param _annualRate is the maximum annual rate that can be withdrawn
    function setMaxAnnualRate(uint256 _annualRate) external; /* onlyMigrationOwner */

    /// Returns the annual withdraw rate of the pool
    /// @return annualRate is the maximum annual rate that can be withdrawn
    function getMaxAnnualRate() external view returns (uint256);

    /// Resets the outstanding tokens to new start time
    /// @dev governance function called only by the migration owner
    /// @dev the next duration will be calculated starting from the given time
    /// @param startTime is the time to set as the last withdrawal time
    function resetOutstandingTokens(uint256 startTime) external; /* onlyMigrationOwner */

    /// Emergency withdraw the wallet funds
    /// @dev governance function called only by the migration owner
    /// @dev used in emergencies, when a migration to a new wallet is needed
    /// @param erc20 is the erc20 address of the token to withdraw
    function emergencyWithdraw(address erc20) external; /* onlyMigrationOwner */

    /// Sets the address of the client that can withdraw funds
    /// @dev governance function called only by the functional owner
    /// @param _client is the address of the new client
    function setClient(address _client) external; /* onlyFunctionalOwner */

}
