// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

/// @title Elections contract interface
interface ICertification /* is Ownable */ {
	event GuardianCertificationUpdate(address indexed guardian, bool isCertified);

	/*
     * External methods
     */

	/// Returns the certification status of a guardian
	/// @param guardian is the guardian to query
	function isGuardianCertified(address guardian) external view returns (bool isCertified);

	/// Sets the guardian certification status
	/// @dev governance function called only by the certification manager
	/// @param guardian is the guardian to update
	/// @param isCertified bool indication whether the guardian is certified
	function setGuardianCertification(address guardian, bool isCertified) external /* onlyCertificationManager */ ;
}
