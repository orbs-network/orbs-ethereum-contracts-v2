import {Contract} from "../eth";
import {TransactionConfig, TransactionReceipt} from "web3-core";
import { ContractName } from "../test/driver";
import {OwnedContract} from "./base-contract";

export interface ContractRegistryContract extends OwnedContract {
  set(contractName: ContractName, addr: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  get(contractName: ContractName, params?: TransactionConfig): Promise<string>;
}

export interface ContractAddressUpdatedEvent {
  contractName: ContractName,
  addr: string
}

