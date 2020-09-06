// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;

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

}
