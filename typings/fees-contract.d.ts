import {TransactionConfig, TransactionReceipt} from "web3-core";
import {Contract} from "../eth";
import * as BN from "bn.js";

export interface FeesAssignedEvent {
  assignees: string[],
  orbs_amounts: Array<string|BN>
}

export interface FeesContract extends Contract {
  getLastFeesAssignment(): Promise<string>;
  getOrbsBalance(address: string): Promise<string>;
  assignFees(params?: TransactionConfig): Promise<TransactionReceipt>;
  withdrawFunds(params?: TransactionConfig): Promise<TransactionReceipt>;
  setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;
}
