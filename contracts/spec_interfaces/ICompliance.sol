pragma solidity 0.5.16;

import "./IContractRegistry.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";


/// @title Elections contract interface
interface ICompliance /* is Ownable */ { // TODO rename to IValidatorIdentification? or make compliance API more generic?
	event ValidatorConformanceUpdate(address validator, string conformanceType);

	/*
     * External methods
     */

    /// @dev Called by a validator as part of the automatic vote unready flow
    /// Used by the Election contract
	function getValidatorCompliance(address addr) external view returns (string memory conformanceType);

    /// @dev Called by a validator as part of the automatic vote unready flow
    /// Used by the Election contract
	function setValidatorCompliance(address addr, string calldata conformanceType) external /* Owner only */ ;

	/*
	 * Governance
	 */

    /// @dev Updates the address calldata of the contract registry
	function setContractRegistry(IContractRegistry _contractRegistry) external /* onlyOwner */;

}
