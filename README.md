# orbs-ethereum-contracts-v2
Orbs PoS V2 contracts and testkit

### To use the test-kit 
```bash
npm install pos-v2
```
or
```bash
yarn add pos-v2
```

#### setup ganache
Ganache must run in order for the testkit to function.
By default the test-kit will assume Ganache is running locally with these default settings: 
```bash
ganache-cli -p 7545 -i 5777 -a 100 -m  "vanish junk genuine web seminar cook absurd royal ability series taste method identify elevator liquid"
```

##### alternative options to running ganache:
- Launch Ganache programatically: `import { ganache } from "pos-v2";` to use `await startGanache()` and `await stopGanache()` from your code.
- Access a remote Ethereum node/network:
  - `ETHEREUM_MNEMONIC` (default: `vanish junk genuine web seminar cook absurd royal ability series taste method identify elevator liquid`)
  - `ETHEREUM_URL` (default: `http://localhost:7545`)

#### Usage Example:

```typescript
import BN from 'bn.js';
import { Driver } from 'pos-v2';

async function createVC(d : Driver) {
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
```
