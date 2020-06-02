import {Contract} from "../eth";

import {TransactionConfig, TransactionReceipt} from "web3-core";
import * as BN from "bn.js";
import { DEPLOYMENT_SUBSET_MAIN, DEPLOYMENT_SUBSET_CANARY } from "../test/driver";
import {OwnedContract} from "./base-contract";

export interface SubscriptionChangedEvent {
  vcid: number | BN;
  genRef: number | BN;
  expiresAt: number | BN;
  tier: 'defaultTier';
  deploymentSubset: typeof DEPLOYMENT_SUBSET_MAIN | typeof DEPLOYMENT_SUBSET_CANARY;
}

export interface PaymentEvent {
  vcid: number | BN;
  by: string;
  amount: number | BN;
  tier: string;
  rate: number | BN;
}

export interface VcConfigRecordChangedEvent {
  vcid: number | BN;
  key: string,
  value: string
}

export interface VcOwnerChangedEvent {
    vcid: number | BN;
    previousOwner: string;
    newOwner: string;
}

export interface VcCreatedEvent {
    vcid: number | BN;
    owner: string;
}

export interface SubscriptionsContract extends OwnedContract {
  addSubscriber(address,params?: TransactionConfig): Promise<TransactionReceipt>;
  setVcConfigRecord(vcid: number|BN, key: string, value: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  getVcConfigRecord(vcid: number|BN, key: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  setVcOwner(vcid: number|BN, owner: string, params?: TransactionConfig): Promise<TransactionReceipt>;
}
