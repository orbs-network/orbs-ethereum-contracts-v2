import {TransactionConfig, TransactionReceipt} from "web3-core";
import {Contract} from "../eth";

export interface FeesContract extends Contract {
  getLastPayedAt(): Promise<string>;
  getOrbsBalance(address: string): Promise<string>;
  assignFees(params?: TransactionConfig): Promise<TransactionReceipt>;
  withdrawFunds(params?: TransactionConfig): Promise<TransactionReceipt>;
  setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;
}
