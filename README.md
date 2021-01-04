[![Version](https://img.shields.io/npm/v/@orbs-network/orbs-ethereum-contracts-v2)](https://www.npmjs.com/package/@orbs-network/orbs-ethereum-contracts-v2)
![Licence](https://img.shields.io/npm/l/@orbs-network/orbs-ethereum-contracts-v2)
# orbs-ethereum-contracts-v2
Orbs PoS V2 contracts and testkit.

See also:
- [posv2-contracts-deployment-migration](https://github.com/orbs-network/posv2-contracts-deployment-migration) - Instructions and scripts for contract deplyment and data migration.
- [List of deployed contracts](https://github.com/orbs-network/posv2-contracts-deployment-migration/blob/master/DEPLOYED_CONTRACTS.md).
- [Gas costs for delegators](https://github.com/orbs-network/orbs-ethereum-contracts-v2/blob/master/GAS.md)

### To acquire contract ABIs:
```javascript
// By name
import { getAbiByContractName } from "@orbs-network/orbs-ethereum-contracts-v2";
const ProtocolWalletABI = getAbiByContractName('ProcotolWallet');

// By contract registry key
import { getAbiByContractRegistryKey } from "@orbs-network/orbs-ethereum-contracts-v2";
const StakingRewardsWalletABI = getAbiByContractRegistryKey('stakingRewardsWallet');

// By address
import { getAbiByContractAddress } from "@orbs-network/orbs-ethereum-contracts-v2";
const DelegationsContractABI = getAbiByContractRegistryKey("0xB97178870F39d4389210086E4BcaccACD715c71d");
```
**Important** - `getAbiByContractAddress()` needs to be manually updated for every newly deployed contract. It may return `undefined` when the given address is unrecognized. The address->ABI mapping is defined [here](https://github.com/orbs-network/orbs-ethereum-contracts-v2/blob/master/deployed-contracts.ts). See [Upgrading contracts](https://github.com/orbs-network/posv2-contracts-deployment-migration#upgrading-contracts). 

### To use the test-kit 
```bash
npm install @orbs-network/orbs-ethereum-contracts-v2
```

#### Known issues
- many capabilities are still not exported. Please be patient and tell us about needed features
- currently the Driver object does not shutdown correctly, sometimes calling process.exit() will be required, until we expose a `shutdown` method

#### setup ganache
Ganache must run in order for the testkit to function.
By default the test-kit will assume Ganache is running locally with these default settings: 
```bash
ganache-cli -p 7545 -i 5777 -a 100 -m  "vanish junk genuine web seminar cook absurd royal ability series taste method identify elevator liquid"
```

##### alternative options to running ganache:
- Launch Ganache programatically: 
```javascript
import { ganache } from "@orbs-network/orbs-ethereum-contracts-v2";
...
await ganache.startGanache()
...
await ganache.stopGanache()
```
- Access a remote Ethereum node/network:
  - `ETHEREUM_MNEMONIC` (default: `vanish junk genuine web seminar cook absurd royal ability series taste method identify elevator liquid`)
  - `ETHEREUM_URL` (default: `http://localhost:7545`)

#### Usage Example - javascript:

```javascript
const BN = require('bn.js').BN;
const Driver = require('@orbs-network/orbs-ethereum-contracts-v2').Driver;

async function createVC() {
    const d = await Driver.new(); // deploys all contracts and returns a driver object

    const monthlyRate = new BN(1000);
    const firstPayment = monthlyRate.mul(new BN(2));

    const subscriber = await d.newSubscriber('defaultTier', monthlyRate);

    // buy subscription for a new VC
    const appOwner = d.newParticipant();

    await d.erc20.assign(appOwner.address, firstPayment); // mint fake ORBS

    await d.erc20.approve(subscriber.address, firstPayment, {
        from: appOwner.address
    });

    return subscriber.createVC(firstPayment, "main", {
        from: appOwner.address
    });
}


// just print the tx Hash and exit

createVC().then((r)=>{
    console.log('Success, txHash', r.transactionHash);
    process.exit(0);
}).catch((e)=>{
    console.error(e);
    process.exit(1);
});
```
