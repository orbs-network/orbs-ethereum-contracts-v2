import {TransactionConfig, TransactionReceipt} from "web3-core";
import {Contract} from "../eth";
import * as BN from "bn.js";

export interface StakingRewardAssignedEvent {
  assignee: string,
  amount: string|BN,
  balance: string|BN
}

export interface StakingRewardsContract extends Contract {
  getLastRewardsAssignment(): Promise<string>;
  getRewardBalance(address: string): Promise<string>;
  assignRewards(params?: TransactionConfig): Promise<TransactionReceipt>;
  distributeOrbsTokenRewards(addrs: string[], amounts: (number | BN)[], params?: TransactionConfig): Promise<TransactionReceipt>;
  setAnnualRate(rate: number | BN, annual_cap: number | BN,  params?: TransactionConfig): Promise<TransactionReceipt>;
  topUpPool(amount: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;
  setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;
}
