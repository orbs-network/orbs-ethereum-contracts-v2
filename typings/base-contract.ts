import {Contract} from "../eth";
import {TransactionConfig, TransactionReceipt} from "web3-core";

export interface LockedEvent {}
export interface UnlockedEvent {}

export interface ContractRegistryAddressUpdatedEvent {
    addr: string;
}

export interface ManagedContract extends Contract {
    transferRegistryManagement(newManager: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    claimRegistryManagement(params?: TransactionConfig): Promise<TransactionReceipt>;

    lock(params?: TransactionConfig): Promise<TransactionReceipt>;
    unlock(params?: TransactionConfig): Promise<TransactionReceipt>;

    refreshContracts(): Promise<TransactionReceipt>;

    setContractRegistry(address: string, params?: TransactionConfig): Promise<TransactionReceipt>;

    initializationComplete(params?: TransactionConfig): Promise<TransactionReceipt>;
    isInitializationComplete(): Promise<boolean>;

    getContractRegistry(): Promise<string>;

    setRegistryAdmin(adming: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    registryAdmin(): Promise<string>;
}
