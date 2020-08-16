import {Contract} from "../eth";
import {TransactionConfig, TransactionReceipt} from "web3-core";
import { ContractName, ContractName4Testkit } from "../test/driver";
import {OwnedContract} from "./base-contract";

export interface ContractRegistryContract extends OwnedContract {
  setContracts(contractIds: string[] /* bytes32[] */, addrs: string[], isManaged: boolean[], params?: TransactionConfig): Promise<TransactionReceipt>;
  getContracts(contractIds: string[] /* bytes32[] */, params?: TransactionConfig): Promise<string[]>;
}

export interface ContractAddressUpdatedEvent {
  contractId: string,
  addr: string,
  isManaged: boolean
}

