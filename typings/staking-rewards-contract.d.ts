import {TransactionConfig, TransactionReceipt} from "web3-core";
import {Contract} from "../eth";
import * as BN from "bn.js";


export interface StakingRewardsContract extends Contract {
  getLastPayedAt(): Promise<string>;
  getOrbsBalance(address: string): Promise<string>;
  assignRewards(params?: TransactionConfig): Promise<TransactionReceipt>;
  distributeOrbsTokenRewards(addrs: string[], amounts: (number | BN)[], params?: TransactionConfig): Promise<TransactionReceipt>;
  setPoolMonthlyRate(rate: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;
  topUpPool(amount: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;
  setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;
}
