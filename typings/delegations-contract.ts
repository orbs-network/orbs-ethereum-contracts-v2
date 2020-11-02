import {Contract} from "../eth";
import {TransactionConfig, TransactionReceipt} from "web3-core";
import * as BN from "bn.js";
import {OwnedContract} from "./base-contract";

export interface DelegationsContract extends OwnedContract {
  stakeChange(stakeOwner: string, amount: number, sign: boolean, updatedStake: number, params?: TransactionConfig): Promise<TransactionReceipt>;
  stakeChangeBatch(stakeOwners: string[], amounts: number[], signs: boolean[], updatedStakes: number[], params?: TransactionConfig) : Promise<TransactionReceipt>;
  delegate(to: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  importDelegations(from: string[], to: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  initDelegation(from: string, to: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  refreshStake(addr: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  refreshStakeBatch(addr: string[], params?: TransactionConfig): Promise<TransactionReceipt>;

  // getters
  getDelegation(address: string): Promise<string>;
  getDelegationInfo(address: string): Promise<{delegation: string, delegatorStake: string}>
  getDelegatedStake(address: string): Promise<BN>;
  getOwnStake(address: string): Promise<BN>;
  getSelfDelegatedStake(address: string): Promise<BN>;
  getTotalDelegatedStake(): Promise<BN>;
  uncappedDelegatedStake(address: string): Promise<BN>;

  VOID_ADDR(): Promise<string>;
}

export interface DelegatedEvent {
  from: string;
  to: string;
}

export interface DelegationInitializedEvent {
  from: string;
  to: string;
}

export interface DelegatedStakeChangedEvent {
  addr: string;
  selfDelegatedStake: BN;
  delegatedStake: BN;
  delegator: string;
  delegatorContributedStake: BN;
}

export interface DelegationsImportedEvent {
  from: string[];
  to: string;
  notified: boolean;
}

export interface DelegationImportFinalizedEvent {}

