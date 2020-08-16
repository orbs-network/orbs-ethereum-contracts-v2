import {Contract} from "../eth";
import {TransactionConfig, TransactionReceipt} from "web3-core";
import { ContractName, ContractName4Testkit } from "../test/driver";
import {OwnedContract} from "./base-contract";

export interface ContractRegistryContract extends OwnedContract {
  setContracts(contractIds: string[] /* bytes32[] */, addrs: string[], isManaged: boolean[], params?: TransactionConfig): Promise<TransactionReceipt>;
  getContracts(contractIds: string[] /* bytes32[] */, params?: TransactionConfig): Promise<string[]>;

  setManager(role: string, manager: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  getManager(role: string): Promise<string>;
}

export interface ContractAddressUpdatedEvent {
  contractId: string,
  addr: string,
  isManaged: boolean
}

export interface ManagerChangedEvent {
  role: string,
  newManager: string
}
