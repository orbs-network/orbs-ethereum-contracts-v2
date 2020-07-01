import {TransactionConfig, TransactionReceipt} from "web3-core";
import {Contract} from "../eth";
import * as BN from "bn.js";
import {OwnedContract} from "./base-contract";

export interface ProtocolVersionChangedEvent {
  deploymentSubset: string,
  currentVersion: number,
  nextVersion: number,
  fromTimestamp: number
}

export interface ProtocolContract extends OwnedContract {
  createDeploymentSubset(deploymentSubset: string, initialProtocolVersion: number, params?: TransactionConfig): Promise<TransactionReceipt>;
  setProtocolVersion(deploymentSubset: string, nextVersion: number, fromTimestamp: number,params?: TransactionConfig): Promise<TransactionReceipt>;
  getProtocolVersion(deploymentSubset: string ,params?: TransactionConfig): Promise<BN>;
  deploymentSubsetExists(deploymentSubset: string, params?: TransactionConfig): Promise<boolean>;
}
