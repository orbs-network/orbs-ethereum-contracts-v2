
import BN from 'bn.js';
import {
    Driver,
    DEPLOYMENT_SUBSET_MAIN,
    Participant,
    CONFORMANCE_TYPE_GENERAL,
    CONFORMANCE_TYPE_COMPLIANCE
} from './driver';
import {MonthlySubscriptionPlanContract} from "../typings/monthly-subscription-plan-contract";

export async function createVC(d : Driver, compliance?: typeof CONFORMANCE_TYPE_GENERAL | typeof CONFORMANCE_TYPE_COMPLIANCE, subscriber?: MonthlySubscriptionPlanContract, monthlyRate?: number, appOwner?: Participant) {
    monthlyRate = monthlyRate != null ? monthlyRate : 1000;
    const firstPayment = monthlyRate * 2;

    subscriber = subscriber || await d.newSubscriber('defaultTier', monthlyRate);
    // buy subscription for a new VC
    appOwner =  appOwner || d.newParticipant();
    await d.erc20.assign(appOwner.address, firstPayment);
    await d.erc20.approve(subscriber.address, firstPayment, {
        from: appOwner.address
    });

    return subscriber.createVC(firstPayment, compliance || CONFORMANCE_TYPE_GENERAL, DEPLOYMENT_SUBSET_MAIN, {
        from: appOwner.address
    });
}
