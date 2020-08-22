import {Contract} from "../eth";
import {TransactionConfig, TransactionReceipt} from "web3-core";
import { ContractName, ContractName4Testkit } from "../test/driver";
import {OwnedContract} from "./base-contract";

export interface ContractRegistryContract extends OwnedContract {
  setContract(contractId: string, addr: string, isManaged: boolean, params?: TransactionConfig): Promise<TransactionReceipt>;
  getContract(contractId: string, params?: TransactionConfig): Promise<string[]>;
}

export interface ContractAddressUpdatedEvent {
  contractName: string,
  addr: string,
  managedContract: boolean
}

