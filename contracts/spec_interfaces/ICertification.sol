// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.12;

/// @title Elections contract interface
interface ICertification /* is Ownable */ {
	event GuardianCertificationUpdate(address indexed guardian, bool isCertified);

	/*
     * External methods
     */

	/// Returns the certification status of a guardian
	/// @param guardian - the guardian to query
	function isGuardianCertified(address guardian) external view returns (bool isCertified);

	/// Sets the guardian certification status
	/// @dev governance function called only by the functional manager
	/// @param guardian - the guardian to query
	/// @param isCertified bool indication wether the guardian is certified
	function setGuardianCertification(address guardian, bool isCertified) external /* onlyFunctionalManager */ ;
}
