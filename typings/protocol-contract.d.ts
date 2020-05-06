import {TransactionConfig, TransactionReceipt} from "web3-core";
import {Contract} from "../eth";
import * as BN from "bn.js";

export interface ProtocolChangedEvent {
  deploymentSubset: string,
  protocolVersion: number,
  asOfBlock: number
}

export interface ProtocolContract extends Contract {
  createDeploymentSubset(deploymentSubset: string, initialProtocolVersion: number, params?: TransactionConfig): Promise<TransactionReceipt>;
  setProtocolVersion(deploymentSubset: string, protocolVersion: number, asOfBlock: number,params?: TransactionConfig): Promise<TransactionReceipt>;
  getProtocolVersion(deploymentSubset: string ,params?: TransactionConfig): Promise<BN>;
  deploymentSubsetExists(deploymentSubset: string, params?: TransactionConfig): Promise<boolean>;
}
