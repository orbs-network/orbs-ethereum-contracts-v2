// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

/// @title Subscriptions contract interface
interface ISubscriptions {
    event SubscriptionChanged(uint256 indexed vcId, address owner, string name, uint256 genRefTime, string tier, uint256 rate, uint256 expiresAt, bool isCertified, string deploymentSubset);
    event Payment(uint256 indexed vcId, address by, uint256 amount, string tier, uint256 rate);
    event VcConfigRecordChanged(uint256 indexed vcId, string key, string value);
    event VcCreated(uint256 indexed vcId);
    event VcOwnerChanged(uint256 indexed vcId, address previousOwner, address newOwner);

    /*
     *   External functions
     */

    /// Creates a new virtual chain
    /// @dev Called only by: an authorized subscription plan contract
    /// @dev the initial amount paid for the virtual chain must be large than minimumInitialVcPayment
    /// @param name is the virtual chain name
    /// @param tier is the virtual chain tier
    /// @param rate is the virtual chain tier rate as determined by the subscription plan
    /// @param amount is the amount paid for the virtual chain initial subscription
    /// @param owner is the virtual chain owner. The owner may change virtual chain properties or ser config records
    /// @param isCertified indicates the virtual is run by the certified committee
    /// @param deploymentSubset indicates the code deployment subset the virtual chain uses such as main or canary
    /// @return vcId is the virtual chain ID allocated to the new virtual chain
    /// @return genRefTime is the virtual chain genesis reference time that determines the first block committee
    function createVC(string calldata name, string calldata tier, uint256 rate, uint256 amount, address owner, bool isCertified, string calldata deploymentSubset) external returns (uint vcId, uint genRefTime);

    /// Extends the subscription of an existing virtual chain.
    /// @dev Called only by: an authorized subscription plan contract
    /// @dev assumes that the msg.sender approved the amount prior to the call
    /// @param vcId is the virtual chain ID
    /// @param amount is the amount paid for the virtual chain subscription extension
    /// @param tier is the virtual chain tier, must match the tier selected in the virtual creation
    /// @param rate is the virtual chain tier rate as determined by the subscription plan
    /// @param payer is the address paying for the subscription extension
    function extendSubscription(uint256 vcId, uint256 amount, string calldata tier, uint256 rate, address payer) external;

    /// Sets a virtual chain config record
    /// @dev may be called only by the virtual chain owner
    /// @param vcId is the virtual chain ID
    /// @param key iis the name of the config record to update
    /// @param value is the config record value
    function setVcConfigRecord(uint256 vcId, string calldata key, string calldata value) external /* onlyVcOwner */;

    /// Returns the value of a virtual chain config record
    /// @param vcId is the virtual chain ID
    /// @param key iis the name of the config record to query
    /// @return value is the config record value
    function getVcConfigRecord(uint256 vcId, string calldata key) external view returns (string memory);

    /// Transfers a virtual chain ownership to a new owner 
    /// @dev may be called only by the current virtual chain owner
    /// @param vcId is the virtual chain ID
    /// @param owner is the address of the new owner
    function setVcOwner(uint256 vcId, address owner) external /* onlyVcOwner */;

    /// Returns the data of a virtual chain
    /// @dev does not include config records data
    /// @param vcId is the virtual chain ID
    /// @return name is the virtual chain name
    /// @return tier is the virtual chain tier
    /// @return rate is the virtual chain tier rate
    /// @return expiresAt the virtual chain subscription expiration time
    /// @return genRefTime is the virtual chain genesis reference time
    /// @return owner is the virtual chain owner. The owner may change virtual chain properties or ser config records
    /// @return deploymentSubset indicates the code deployment subset the virtual chain uses such as main or canary
    /// @return isCertified indicates the virtual is run by the certified committee
    function getVcData(uint256 vcId) external view returns (
        string memory name,
        string memory tier,
        uint256 rate,
        uint expiresAt,
        uint256 genRefTime,
        address owner,
        string memory deploymentSubset,
        bool isCertified
    );

    /*
     *   Governance functions
     */

    event SubscriberAdded(address subscriber);
    event SubscriberRemoved(address subscriber);
    event GenesisRefTimeDelayChanged(uint256 newGenesisRefTimeDelay);
    event MinimumInitialVcPaymentChanged(uint256 newMinimumInitialVcPayment);

    /// Adds a subscription plan contract to the authorized subscribers list
	/// @dev governance function called only by the functional manager
    /// @param addr is the address of the subscription plan contract
    function addSubscriber(address addr) external /* onlyFunctionalManager */;

    /// Removes a subscription plan contract to the authorized subscribers list
	/// @dev governance function called only by the functional manager
    /// @param addr is the address of the subscription plan contract
    function removeSubscriber(address addr) external /* onlyFunctionalManager */;

    /// Set the genesis reference time delay from the virtual chain creation time
	/// @dev governance function called only by the functional manager
    /// @dev the reference time delay allows the guardian to be ready with the virtual chain resources for the first block consensus
    /// @param newGenesisRefTimeDelay is the delay time in seconds
    function setGenesisRefTimeDelay(uint256 newGenesisRefTimeDelay) external /* onlyFunctionalManager */;

    /// Returns the genesis reference time delay
    /// @return genesisRefTimeDelay is the delay time in seconds
    function getGenesisRefTimeDelay() external view returns (uint256);

    /// Sets the minimum initial virtual chain payment 
    /// @dev Prevents abuse of the guardian nodes resources
    /// @param newMinimumInitialVcPayment is the minimum payment required for the initial subscription
    function setMinimumInitialVcPayment(uint256 newMinimumInitialVcPayment) external /* onlyFunctionalManager */;

    /// Returns the minimum initial virtual chain payment 
    /// @return minimumInitialVcPayment is the minimum payment required for the initial subscription
    function getMinimumInitialVcPayment() external view returns (uint256);

    /// Returns the settings of this contract
    /// @return genesisRefTimeDelay is the delay time in seconds
    /// @return minimumInitialVcPayment is the minimum payment required for the initial subscription
    function getSettings() external view returns(
        uint genesisRefTimeDelay,
        uint256 minimumInitialVcPayment
    );

    /// Imports virtual chain subscription from a previous subscriptions contract
	/// @dev governance function called only by the initialization admin during migration
    /// @dev if the migrated vcId is larger or equal to the next virtual chain ID to allocate, increment the next virtual chain ID
    /// @param vcId is the virtual chain ID to migrate
    /// @param previousSubscriptionsContract is the address of the previous subscription contract
    function importSubscription(uint vcId, ISubscriptions previousSubscriptionsContract) external /* onlyInitializationAdmin */;

}
