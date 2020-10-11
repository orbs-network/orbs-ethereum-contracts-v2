import {Contract} from "../eth";

import {TransactionConfig, TransactionReceipt} from "web3-core";
import * as BN from "bn.js";
import { DEPLOYMENT_SUBSET_MAIN, DEPLOYMENT_SUBSET_CANARY } from "../test/driver";
import {OwnedContract} from "./base-contract";

export interface SubscriptionChangedEvent {
  vcId: number | BN;
  owner: string;
  name: string;
  genRefTime: number | BN;
  expiresAt: number | BN;
  tier: string;
  rate: number|BN;
  isCertified: boolean;
  deploymentSubset: typeof DEPLOYMENT_SUBSET_MAIN | typeof DEPLOYMENT_SUBSET_CANARY;
}

export interface PaymentEvent {
  vcId: number | BN;
  by: string;
  amount: number | BN;
  tier: string;
  rate: number | BN;
}

export interface VcConfigRecordChangedEvent {
  vcId: number | BN;
  key: string,
  value: string
}

export interface VcOwnerChangedEvent {
    vcId: number | BN;
    previousOwner: string;
    newOwner: string;
}

export interface VcCreatedEvent {
    vcId: number | BN;
}

export interface SubscriberAddedEvent {
  subscriber: string;
}

export interface SubscriberRemovedEvent {
  subscriber: string;
}

export interface GenesisRefTimeDelayChangedEvent {
  newGenesisRefTimeDelay: number|BN;
}

export interface MinimumInitialVcPaymentChangedEvent {
  newMinimumInitialVcPayment: number|BN;
}

export interface SubscriptionsContract extends OwnedContract {
  addSubscriber(address,params?: TransactionConfig): Promise<TransactionReceipt>;
  removeSubscriber(address,params?: TransactionConfig): Promise<TransactionReceipt>;
  setVcConfigRecord(vcId: number|BN, key: string, value: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  extendSubscription(vcId: number, amount: number|BN, tier: string, rate: number|BN, payer: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  getVcConfigRecord(vcId: number|BN, key: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  setVcOwner(vcId: number|BN, owner: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  setGenesisRefTimeDelay(genRefTimeDelay: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
  getGenesisRefTimeDelay(params?: TransactionConfig): Promise<string>;
  setMinimumInitialVcPayment(newMin: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
  getMinimumInitialVcPayment(params?: TransactionConfig): Promise<string>;
  getVcData(vcId: number|string|BN, params?: TransactionConfig): Promise<[
    string /* name */,
    string /* tier */,
    string /* rate */,
    string /* expiresAt */,
    string /* genRefTime */,
    string /* owner */,
    string /* deploymentSubset */,
    boolean /* isCertified */
  ]>;
  getSettings(): Promise<any>;
}
