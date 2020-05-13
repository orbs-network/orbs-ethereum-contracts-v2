import {TransactionConfig, TransactionReceipt} from "web3-core";
import {Contract} from "../eth";
import * as BN from "bn.js";

export interface StakingRewardAssignedEvent {
  assignee: string,
  amount: string|BN,
  balance: string|BN
}

export interface StakingRewardsDistributedEvent {
  distributer: string,
  fromBlock: string|BN,
  toBlock: string|BN,
  split: string|BN,
  txIndex: string|BN,
  to: string[],
  amounts: (string|BN)[]
}


export interface StakingRewardsContract extends Contract {
  getLastRewardsAssignment(): Promise<string>;
  getRewardBalance(address: string): Promise<string>;
  assignRewards(params?: TransactionConfig): Promise<TransactionReceipt>;
  distributeOrbsTokenRewards(totalAmount: (number|BN), fromBlock: (number|BN), toBlock: (number|BN), split: (number|BN), txIndex: (number|BN), to: string[], amounts: (number | BN)[], params?: TransactionConfig): Promise<TransactionReceipt>;
  setAnnualRate(annual_rate_in_percent_mille: number | BN, annual_cap: number | BN,  params?: TransactionConfig): Promise<TransactionReceipt>;
  topUpPool(amount: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;
  setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;
}
