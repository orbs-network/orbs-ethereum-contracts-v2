import {Contract} from "../eth";
import {TransactionConfig, TransactionReceipt} from "web3-core";
import * as BN from "bn.js";

export interface DelegationsContract extends Contract {
  stakeChange(stakeOwner: string, amount: number, sign: boolean, updatedStake: number, params?: TransactionConfig): Promise<TransactionReceipt>;
  stakeChangeBatch(stakeOwners: string[], amounts: number[], signs: boolean[], updatedStakes: number[], params?: TransactionConfig) : Promise<TransactionReceipt>;
  delegate( to: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  refreshStakes(addrs: string[], params?: TransactionConfig): Promise<TransactionReceipt>;
  getDelegation(address: string): Promise<string>;
  setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;
}

export interface DelegatedEvent {
  from: string;
  to: string;
}

export interface DelegatedStakeChangedEvent {
  addr: string;
  selfStake: BN;
  delegatedStake: BN;
}

