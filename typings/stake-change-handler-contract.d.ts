import {TransactionConfig, TransactionReceipt} from "web3-core";
import {OwnedContract} from "./base-contract";
import * as BN from "bn.js";

export interface StakeChangeNotificationFailedEvent {
  stakeOwner: string
}

export interface StakeChangeBatchNotificationFailedEvent {
  stakeOwners: string[]
}

export interface StakeMigrationNotificationFailedEvent {
  stakeOwner: string
}

export interface NotifyDelegationsChangedEvent {
  notifyDelegations: boolean;
}

export interface StakeChangeNotificationSkippedEvent {
  stakeOwner: string
}

export interface StakeChangeBatchNotificationSkippedEvent {
  stakeOwners: string[]
}

export interface StakeMigrationNotificationSkippedEvent {
  stakeOwner: string
}

export interface StakingContractHandlerContract extends OwnedContract {
  stakeChange(stakeOwner: string, amount: number, sign: boolean, updatedStake: number, params?: TransactionConfig): Promise<TransactionReceipt>;
  stakeChangeBatch(stakeOwners: string[], amounts: number[], signs: boolean[], updatedStakes: number[], params?: TransactionConfig) : Promise<TransactionReceipt>;
  stakeMigration(stakeOwner: string, amount: number, params?: TransactionConfig) : Promise<TransactionReceipt>;
  getStakeBalanceOf(stakeOwner: string, params?: TransactionConfig): Promise<BN>;
  getTotalStakedTokens(): Promise<BN>;
  setNotifyDelegations(notifyDelegations: boolean, params?: TransactionConfig): Promise<TransactionReceipt>;
}

