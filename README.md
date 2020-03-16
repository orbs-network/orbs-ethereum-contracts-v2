# orbs-ethereum-contracts-v2
Orbs PoS V2 contracts and testkit

To use the testkit 
```bash
npm install pos-v2
```
or
```bash
yarn add pos-v2
```

- Ganache must be started with these default settings: 
```bash
ganache-cli -p 7545 -i 5777 -a 100 -m  "vanish junk genuine web seminar cook absurd royal ability series taste method identify elevator liquid"
```

If you don't run ganache locally:
- `import { ganache } from "pos-v2";` to use `startGanache()` and `stopGanache()` methods to start and stop ganache programatically
- To override the default ethereum configuration set these env vars:
  - `ETHEREUM_MNEMONIC` (`vanish junk genuine web seminar cook absurd royal ability series taste method identify elevator liquid`)
  - `ETHEREUM_URL`(`http://localhost:7545`)


  
Usage Examples:



```typescript
import {Driver} from "pos-v2";
const BN = require('bn.js');

const test = async () => {
    const d = await Driver.new();
    const monthlyRate = new BN(1000);
    const firstPayment = monthlyRate.mul(new BN(2));

    const subscriber = await d.newSubscriber("defaultTier", monthlyRate);

    // buy subscription for a new VC
    const appOwner = d.newParticipant();
    await d.erc20.assign(appOwner.address, firstPayment);
    await d.erc20.approve(subscriber.address, firstPayment, {
        from: appOwner.address
    });

    await subscriber.createVC(firstPayment, "main", {
        from: appOwner.address
    });

    await d.subscriptions.web3Contract.getPastEvents("SubscriptionChanged", {
        fromBlock: 0,
        toBlock: "latest"
    });
};

test().catch(e => {
    console.log(e);
    process.exit(1);
});

```


```typescript
import BN from 'bn.js';
import { Driver } from 'pos-v2';

async function createVC(d : Driver) {
    const monthlyRate = new BN(1000);
    const firstPayment = monthlyRate.mul(new BN(2));

    const subscriber = await d.newSubscriber('defaultTier', monthlyRate);
    
    // buy subscription for a new VC
    const appOwner = d.newParticipant();
    await d.erc20.assign(appOwner.address, firstPayment); // TODO extract assign+approve to driver in two places
    await d.erc20.approve(subscriber.address, firstPayment, {
        from: appOwner.address
    });

    return subscriber.createVC(firstPayment, "main", {
        from: appOwner.address
    });
}
```
