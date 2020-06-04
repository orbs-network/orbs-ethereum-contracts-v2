import {Contract} from "../eth";
import {TransactionConfig, TransactionReceipt} from "web3-core";
import { ContractName, ContractName4Testkit } from "../test/driver";
import {OwnedContract} from "./base-contract";

export interface ContractRegistryContract extends OwnedContract {
  set(contractName: ContractName | ContractName4Testkit, addr: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  get(contractName: ContractName | ContractName4Testkit, params?: TransactionConfig): Promise<string>;
}

export interface ContractAddressUpdatedEvent {
  contractName: ContractName,
  addr: string
}

