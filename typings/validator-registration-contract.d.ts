import {Contract} from "../eth";

import {TransactionConfig, TransactionReceipt} from "web3-core";
import * as BN from "bn.js";
import {OwnedContract} from "./base-contract";

export interface ValidatorRegisteredEvent {
    addr: string,
}

export interface ValidatorDataUpdatedEvent {
    addr: string,
    ip: string,
    orbsAddr: string,
    name: string,
    website: string,
    contact: string
}

export interface ValidatorUnregisteredEvent {
    addr: string
}

export interface ValidatorMetadataChangedEvent {
    addr: string,
    key: string,
    oldValue: string,
    newValue: string,
}

export interface ValidatorsRegistrationContract extends OwnedContract {
    setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    registerValidator(ip: string, orbsAddr: string, name: string, website: string, contact: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    unregisterValidator(params?: TransactionConfig): Promise<TransactionReceipt>;
    updateValidator(ip: string, orbsAddr: string, name: string, website: string, contact: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    setMetadata(key: string, value: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    getMetadata(addr: string, key: string, params?: TransactionConfig): Promise<string>;
    getValidatorData(addr: string, params?: TransactionConfig): Promise<{ip: string, orbsAddr: string, name: string, website: string, contact: string, registration_time: BN|string, last_update_time: BN|string}>;
    getOrbsAddresses(addrs: string[], params?: TransactionConfig): Promise<string[]>;
    getEthereumAddresses(addrs: string[], params?: TransactionConfig): Promise<string[]>;
}

