# Gas Costs For Delegators

## Normal gas costs

Below is the gas usage of common delegator actions (small differences may apply due to difference in Ethereum versions).

|                                                 | Gas    | Estimated cost (assuming: 1 gas = 50 gwei, 1 ETH = $500) |
|-------------------------------------------------|--------|------------------------------------------------------------|
| New delegator delegates and stakes (Tetra flow) | 292837 | $7.32                                                      |
| Delegator increases stake                       | 214802 | $5.37                                                      |
| Delegator unstakes partially                    | 188899 | $4.72                                                      |
| Delegator fully unstakes                        | 186712 | $4.66                                                      |
| Delegator claims staking rewards (first time)   | 342404 | $8.56                                                      |
| Delegator claims staking rewards (second time)  | 272122 | $6.80                                                      |

Cost formula: `gas * <gas price in gwei> * <ether price in usd> / 1000000000`. If gas price goes up x2 (to 100 gwei), total cost will go up x2 as well. If ETH price goes up x2 (to $1000), total cost will go up x2 as well.

It's worth mentioning that claiming rewards gives very little value to delegators and should rarely be done. The main value of claiming is adjusting the delegator's Guardian election weight to count for the reward. This change is normally negligble and will not influence election results. In any case, the rewards belong via contract to the delegator whether or not they are claimed, and can be claimed at any time. It's recommended to claim no more than once a year.

## Subsidizing gas costs

In the case where the rising gas prices becomes an issue, a governance decision can me made to subsidize staking and unstaking actions.
The suggested flow is as follows:

1. Disconnect the staking contract from the PoS ecosystem. Once this is done, staking actions will not immediatly be reflected on the committe, rewards, etc.
  This operation can be done by the migrationManager, by calling the StakingContractHandler contract: `StakingContractHandler.setNotifyDelegations(false)`.
  
2. From this point, the StakingContractHandler contract will emit a `StakeChangeNotificationSkipped` event whenever a staking action takes place, containing the address of the staker. These events should be tracked by the subsidizer.

3. The subsidizer (which does not require any permissions) should then call the DelegationsContract `refreshStake` with each staker address from the list of stakers aquired in 2. This will update the PoS echosystem with the stake change.

4. To reconnect the staking contract and disable subsidizing, the migrationManager should call `StakingContractHandler.setNotifyDelegations(false)`.

### Costs after subsidization

|                                                 | Gas    | Estimated cost (assuming: 1 gas = 50 gwei, 1 ETH = $500) |
|-------------------------------------------------|--------|------------------------------------------------------------|
| **Delegator costs**                             |        |                                                            |
| Delegator increases stake (subsidized)          | 98663  | $2.46                                                      |
| Delegator unstakes partially (subsidized)       | 85573  | $2.13                                                      |
| Delegator fully unstakes                        | 70561  | $1.76                                                      |
| **Subsidizer costs**                            |        |                                                            |
| Subsidizer: refreshStake()                      | 157682 | $3.94                                                      |
  
