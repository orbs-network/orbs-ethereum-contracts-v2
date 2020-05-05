
import BN from 'bn.js';
import {
    Driver,
    DEPLOYMENT_SUBSET_MAIN,
    Participant,
    COMPLIANCE_TYPE_GENERAL,
    COMPLIANCE_TYPE_COMPLIANCE
} from './driver';
import {MonthlySubscriptionPlanContract} from "../typings/monthly-subscription-plan-contract";

export async function createVC(d : Driver, compliance?: typeof COMPLIANCE_TYPE_GENERAL | typeof COMPLIANCE_TYPE_COMPLIANCE, subscriber?: MonthlySubscriptionPlanContract, monthlyRate?: number, appOwner?: Participant) {
    monthlyRate = monthlyRate != null ? monthlyRate : 1000;
    const firstPayment = monthlyRate * 2;

    subscriber = subscriber || await d.newSubscriber('defaultTier', monthlyRate);
    // buy subscription for a new VC
    appOwner =  appOwner || d.newParticipant();
    await d.erc20.assign(appOwner.address, firstPayment);
    await d.erc20.approve(subscriber.address, firstPayment, {
        from: appOwner.address
    });

    return subscriber.createVC(firstPayment, compliance || COMPLIANCE_TYPE_GENERAL, DEPLOYMENT_SUBSET_MAIN, {
        from: appOwner.address
    });
}
