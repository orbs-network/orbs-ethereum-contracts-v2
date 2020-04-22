
import BN from 'bn.js';
import { Driver, DEPLOYMENT_SUBSET_MAIN } from './driver';

export async function createVC(d : Driver) {
    const monthlyRate = new BN(1000);
    const firstPayment = monthlyRate.mul(new BN(2));

    const subscriber = await d.newSubscriber('defaultTier', monthlyRate);
    // buy subscription for a new VC
    const appOwner = d.newParticipant();
    await d.erc20.assign(appOwner.address, firstPayment);
    await d.erc20.approve(subscriber.address, firstPayment, {
        from: appOwner.address
    });

    return subscriber.createVC(firstPayment, "General", DEPLOYMENT_SUBSET_MAIN, {
        from: appOwner.address
    });
}
