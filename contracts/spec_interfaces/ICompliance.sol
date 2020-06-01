pragma solidity 0.5.16;

import "./IContractRegistry.sol";


/// @title Elections contract interface
interface ICompliance /* is Ownable */ { // TODO rename to IValidatorIdentification? or make compliance API more generic?
	event ValidatorComplianceUpdate(address validator, bool isCompliant);

	/*
     * External methods
     */

    /// @dev Called by a validator as part of the automatic vote unready flow
    /// Used by the Election contract
	function isValidatorCompliant(address addr) external view returns (bool isCompliant);

    /// @dev Called by a validator as part of the automatic vote unready flow
    /// Used by the Election contract
	function setValidatorCompliance(address addr, bool isCompliant) external /* Owner only */ ;

	/*
	 * Governance
	 */

    /// @dev Updates the address calldata of the contract registry
	function setContractRegistry(IContractRegistry _contractRegistry) external /* onlyMigrationOwner */;

}
