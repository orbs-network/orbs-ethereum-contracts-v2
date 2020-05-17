import {Contract} from "../eth";
import {TransactionConfig, TransactionReceipt} from "web3-core";
import * as BN from "bn.js";

export interface DelegationsContract extends Contract {
  stakeChange(stakeOwner: string, amount: number, sign: boolean, updatedStake: number, params?: TransactionConfig): Promise<TransactionReceipt>;
  stakeChangeBatch(stakeOwners: string[], amounts: number[], signs: boolean[], updatedStakes: number[], params?: TransactionConfig) : Promise<TransactionReceipt>;
  delegate( to: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;

  // getters
  getDelegation(address: string): Promise<string>;
  getDelegatedStakes(address: string): Promise<BN>;
  getOwnStake(address: string): Promise<BN>;
  getTotalGovernanceStake(): Promise<BN>;
  getGovernanceEffectiveStake(address: string): Promise<BN>;
}

export interface DelegatedEvent {
  from: string;
  to: string;
}

export interface DelegatedStakeChangedEvent {
  addr: string;
  selfStake: BN;
  delegatedStake: BN;
  delegators: string[];
  delegatorTotalStakes: BN[];
}

