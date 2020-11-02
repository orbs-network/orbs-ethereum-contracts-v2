import {TransactionConfig, TransactionReceipt} from "web3-core";
import {Contract} from "../eth";
import * as BN from "bn.js";
import {OwnedContract} from "./base-contract";

interface FundsAddedToPoolEvent {
  added: string|BN;
  total: string|BN;
}

interface ClientSetEvent {
  client: string;
}

export interface MaxAnnualRateSetEvent {
  maxAnnualRate: string|BN;
}

export interface EmergencyWithdrawalEvent {
  addr: string;
  token: string;
}

export interface OutstandingTokensResetEvent {
  startTime: string|BN;
}

export interface ProtocolWalletContract extends OwnedContract {
  getMaxAnnualRate(): Promise<number>;
  token(params?: TransactionConfig): Promise<string>;
  getBalance(params?: TransactionConfig): Promise<string>;
  topUp(amount: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
  withdraw(amount: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
  setMaxAnnualRate(annualRate: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
  emergencyWithdraw(token: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  setClient(client: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  resetOutstandingTokens(startTime: number, params?: TransactionConfig): Promise<TransactionReceipt>;
  transferMigrationOwnership(newOwner: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  claimMigrationOwnership(params?: TransactionConfig): Promise<TransactionReceipt>;
  migrationOwner(params?: TransactionConfig): Promise<string>;
  transferFunctionalOwnership(newOwner: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  claimFunctionalOwnership(params?: TransactionConfig): Promise<TransactionReceipt>;
  functionalOwner(params?: TransactionConfig): Promise<string>;
}
