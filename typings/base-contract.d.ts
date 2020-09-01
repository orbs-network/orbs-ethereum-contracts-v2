import {Contract} from "../eth";
import {TransactionConfig, TransactionReceipt} from "web3-core";

export interface LockedEvent {}
export interface UnlockedEvent {}

export interface ContractRegistryAddressUpdatedEvent {
    addr: string;
}

export interface OwnedContract extends Contract {
    transferRegistryManagement(newManager: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    claimRegistryManagement(params?: TransactionConfig): Promise<TransactionReceipt>;

    lock(params?: TransactionConfig): Promise<TransactionReceipt>;
    unlock(params?: TransactionConfig): Promise<TransactionReceipt>;

    refreshContracts(): Promise<TransactionReceipt>;

    setContractRegistry(address: string, params?: TransactionConfig): Promise<TransactionReceipt>;

    initializationComplete(): Promise<TransactionReceipt>;

    registryManager(): Promise<string>;
}
