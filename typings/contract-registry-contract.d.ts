import {Contract} from "../eth";
import {TransactionConfig, TransactionReceipt} from "web3-core";
import { ContractName } from "../test/driver";

export interface ContractRegistryContract extends Contract {
  set(contractName: ContractName, addr: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  get(contractName: ContractName, params?: TransactionConfig): Promise<string>;
}

export interface ContractAddressUpdatedEvent {
  contractName: string,
  addr: string
}

