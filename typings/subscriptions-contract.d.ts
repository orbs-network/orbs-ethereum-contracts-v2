import {Contract} from "../eth";

import {TransactionConfig, TransactionReceipt} from "web3-core";
import * as BN from "bn.js";
import { DEPLOYMENT_SUBSET_MAIN, DEPLOYMENT_SUBSET_CANARY } from "../test/driver";

export interface SubscriptionChangedEvent {
  vcid: string;
  genRef: number | BN;
  expiresAt: number | BN;
  tier: 'defaultTier';
  deploymentSubset: typeof DEPLOYMENT_SUBSET_MAIN | typeof DEPLOYMENT_SUBSET_CANARY;
}

export interface PaymentEvent {
  vcid: string;
  by: string;
  amount: number | BN;
  tier: string;
  rate: number | BN;
}

export interface VcConfigRecordChangedEvent {
  vcid: string;
  key: string,
  value: string
}

export interface VcOwnerChangedEvent {
    vcid: string;
    previousOwner: string;
    newOwner: string;
}

export interface VcCreatedEvent {
    vcid: string;
    owner: string;
}

export interface SubscriptionsContract extends Contract {
  addSubscriber(address,params?: TransactionConfig): Promise<TransactionReceipt>;
  setVcConfigRecord(vcid: number|BN, key: string, value: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  getVcConfigRecord(vcid: number|BN, key: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  setVcOwner(vcid: number|BN, owner: string, params?: TransactionConfig): Promise<TransactionReceipt>;
}
