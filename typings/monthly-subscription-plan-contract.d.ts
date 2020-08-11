import {TransactionConfig, TransactionReceipt} from "web3-core";
import {Contract} from "../eth";
import * as BN from "bn.js";
import {OwnedContract} from "./base-contract";

export interface MonthlySubscriptionPlanContract extends OwnedContract {
  createVC(name: string, payment: number | BN, isCertified: boolean, deploymentSubset: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  extendSubscription(vcid: string, payment: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;
  setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;
}
