pragma solidity 0.5.16;
import "../spec_interfaces/IContractRegistry.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

pragma solidity 0.5.16;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
/// @title Protocol Wallet interface
interface IProtocolWallet {
    event FundsAddedToPool(uint256 added, uint256 total);
    event ClientSet(address client);
    event MaxAnnualRateSet(uint256 maxAnnualRate);
    event EmergencyWithdrawal(address addr);
    event OutstandingTokensReset();

    /// @dev Returns the address of the underlying staked token.
    /// @return IERC20 The address of the token.
    function getToken() external view returns (IERC20);

    /// @dev Returns the address of the underlying staked token.
    /// @return IERC20 The address of the token.
    function getBalance() external view returns (uint256 balance);

    /// @dev Transfers the given amount of orbs tokens form the sender to this contract an update the pool.
    function topUp(uint256 amount) external;

    /// @dev Withdraw from pool to a the sender's address, limited by the pool's MaxRate.
    /// A maximum of MaxRate x time period since the last Orbs transfer may be transferred out.
    function withdraw(uint256 amount) external; /* onlyClient */

    /* Governance */
    /// @dev Sets a new transfer rate for the Orbs pool.
    function setMaxAnnualRate(uint256 annual_rate) external; /* onlyMigrationManager */

    /// @dev transfer the entire pool's balance to a new wallet.
    function emergencyWithdraw() external; /* onlyMigrationManager */

    /// @dev sets the address of the new contract
    function setClient(address client) external; /* onlyFunctionalManager */

    function getMaxAnnualRate() external view returns (uint256);
}
