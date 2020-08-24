pragma solidity 0.5.16;

import "./IContractRegistry.sol";


/// @title Elections contract interface
interface ICertification /* is Ownable */ {
	event GuardianCertificationUpdate(address guardian, bool isCertified);

	/*
     * External methods
     */

    /// @dev Called by a guardian as part of the automatic vote unready flow
    /// Used by the Election contract
	function isGuardianCertified(address addr) external view returns (bool isCertified);

    /// @dev Called by a guardian as part of the automatic vote unready flow
    /// Used by the Election contract
	function setGuardianCertification(address addr, bool isCertified) external /* Owner only */ ;

	/*
	 * Governance
	 */

    /// @dev Updates the address calldata of the contract registry
	function setContractRegistry(IContractRegistry _contractRegistry) external /* onlyMigrationManager */;

}
