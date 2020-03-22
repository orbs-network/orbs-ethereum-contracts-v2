import {TransactionConfig, TransactionReceipt} from "web3-core";
import {Contract} from "../eth";
import * as BN from "bn.js";

export interface BootstrapRewardsAssignedEvent {
  assignees: string[],
  amounts: Array<string|BN>
}

export interface BootstrapAddedToPoolEvent {
  added: number|BN,
  total: number|BN
}

export interface BootstrapRewardsContract extends Contract {
  getLastPayedAt(): Promise<string>;
  getBootstrapBalance(address: string): Promise<string>;
  assignRewards(params?: TransactionConfig): Promise<TransactionReceipt>;
  distributeOrbsTokenRewards(addrs: string[], amounts: (number | BN)[], params?: TransactionConfig): Promise<TransactionReceipt>;
  setGeneralCommitteeAnnualBootstrap(annual_bootstrap: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;
  setComplianceCommitteeAnnualBootstrap(annual_bootstrap: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;
  topUpBootstrapPool(amount: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;
  withdrawFunds(params?: TransactionConfig): Promise<TransactionReceipt>;
  setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;
}
