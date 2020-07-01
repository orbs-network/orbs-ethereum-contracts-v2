import {TransactionConfig, TransactionReceipt} from "web3-core";
import {Contract} from "../eth";
import * as BN from "bn.js";
import {OwnedContract} from "./base-contract";

interface FundsAddedToPool {
  added: string|BN;
  total: string|BN;
}

interface ClientSet {
  client: string;
}

interface MaxAnnualRateSet {
  maxAnnualRate: string|BN;
}

interface EmergencyWithdrawal {
  addr: string;
}


export interface ProtocolWalletContract extends OwnedContract {
  getToken(params?: TransactionConfig): Promise<string>;
  getBalance(params?: TransactionConfig): Promise<string>;
  topUp(amount: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
  withdraw(amount: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
  setMaxAnnualRate(annualRate: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
  emergencyWithdraw(params?: TransactionConfig): Promise<TransactionReceipt>;
  setClient(client: string, params?: TransactionConfig): Promise<TransactionReceipt>;
}
