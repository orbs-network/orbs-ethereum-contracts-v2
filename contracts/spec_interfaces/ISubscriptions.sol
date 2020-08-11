pragma solidity 0.5.16;

import "./IContractRegistry.sol";

/// @title Subscriptions contract interface
interface ISubscriptions {
    event SubscriptionChanged(uint256 vcid, string name, uint256 genRefTime, uint256 expiresAt, string tier, string deploymentSubset);
    event Payment(uint256 vcid, address by, uint256 amount, string tier, uint256 rate);
    event VcConfigRecordChanged(uint256 vcid, string key, string value);
    event VcCreated(uint256 vcid, address owner); // TODO what about isCertified, deploymentSubset?
    event VcOwnerChanged(uint256 vcid, address previousOwner, address newOwner);
    event SubscriberAdded(address subscriber);
    event SubscriberRemoved(address subscriber);
    event GenesisRefTimeDelayChanged(uint256 newGenesisRefTimeDelay);
    event MinimumInitialVcPaymentChanged(uint256 newMinimumInitialVcPayment);

    /*
     *   Methods restricted to other Orbs contracts
     */

    /// @dev Called by: authorized subscriber (plan) contracts
    /// Creates a new VC
    function createVC(string calldata name, string calldata tier, uint256 rate, uint256 amount, address owner, bool isCertified, string calldata deploymentSubset) external returns (uint, uint);

    /// @dev Called by: authorized subscriber (plan) contracts
    /// Extends the subscription of an existing VC.
    function extendSubscription(uint256 vcid, uint256 amount, address payer) external;

    /// @dev called by VC owner to set a VC config record. Emits a VcConfigRecordChanged event.
    function setVcConfigRecord(uint256 vcid, string calldata key, string calldata value) external /* onlyVcOwner */;

    /// @dev returns the value of a VC config record
    function getVcConfigRecord(uint256 vcid, string calldata key) external view returns (string memory);

    /// @dev Transfers VC ownership to a new owner (can only be called by the current owner)
    function setVcOwner(uint256 vcid, address owner) external /* onlyVcOwner */;

    /// @dev Returns the genesis ref time delay
    function getGenesisRefTimeDelay() external view returns (uint256);

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
     *   Governance methods
     */

    /// @dev Called by the owner to authorize a subscriber (plan)
    function addSubscriber(address addr) external /* onlyFunctionalOwner */;

    /// @dev Called by the owner to set the genesis ref time delay
    function setGenesisRefTimeDelay(uint256 newGenesisRefTimeDelay) external /* onlyFunctionalOwner */;

    /// @dev Called by the owner to set the minimum initial vc payment
    function setMinimumInitialVcPayment(uint256 minimumInitialVcPayment) external /* onlyFunctionalOwner */;

    /// @dev Updates the address of the contract registry
    function setContractRegistry(IContractRegistry _contractRegistry) external /* onlyMigrationOwner */;

}
