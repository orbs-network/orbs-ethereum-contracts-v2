// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;

import "./IContractRegistry.sol";


/// @title Elections contract interface
interface ICertification /* is Ownable */ {
	event GuardianCertificationUpdate(address guardian, bool isCertified);

	/*
     * External methods
     */

	function isGuardianCertified(address addr) external view returns (bool isCertified);

	function setGuardianCertification(address addr, bool isCertified) external /* Owner only */ ;

}
