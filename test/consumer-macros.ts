
import BN from 'bn.js';
import {
    Driver,
    DEPLOYMENT_SUBSET_MAIN,
    Participant,
} from './driver';
import {MonthlySubscriptionPlanContract} from "../typings/monthly-subscription-plan-contract";

export async function createVC(d : Driver, isCompliant?: boolean, subscriber?: MonthlySubscriptionPlanContract, monthlyRate?: number, appOwner?: Participant) {
    monthlyRate = monthlyRate != null ? monthlyRate : 1000;
    const firstPayment = monthlyRate * 2;

    subscriber = subscriber || await d.newSubscriber('defaultTier', monthlyRate);
    // buy subscription for a new VC
    appOwner =  appOwner || d.newParticipant();
    await d.erc20.assign(appOwner.address, firstPayment);
    await d.erc20.approve(subscriber.address, firstPayment, {
        from: appOwner.address
    });

    return subscriber.createVC(firstPayment, isCompliant || false, DEPLOYMENT_SUBSET_MAIN, {
        from: appOwner.address
    });
}
