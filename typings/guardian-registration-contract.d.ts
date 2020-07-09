import {Contract} from "../eth";

import {TransactionConfig, TransactionReceipt} from "web3-core";
import * as BN from "bn.js";
import {OwnedContract} from "./base-contract";

export interface GuardianRegisteredEvent {
    addr: string,
}

export interface GuardianDataUpdatedEvent {
    addr: string,
    ip: string,
    orbsAddr: string,
    name: string,
    website: string,
    contact: string
}

export interface GuardianUnregisteredEvent {
    addr: string
}

export interface GuardianMetadataChangedEvent {
    addr: string,
    key: string,
    oldValue: string,
    newValue: string,
}

export interface GuardiansRegistrationContract extends OwnedContract {
    setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    registerGuardian(ip: string, orbsAddr: string, name: string, website: string, contact: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    unregisterGuardian(params?: TransactionConfig): Promise<TransactionReceipt>;
    updateGuardian(ip: string, orbsAddr: string, name: string, website: string, contact: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    updateGuardianIp(ip: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    resolveGuardianAddress(ethereumOrOrbs: string, params?: TransactionConfig): Promise<string>;
    setMetadata(key: string, value: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    getMetadata(addr: string, key: string, params?: TransactionConfig): Promise<string>;
    getGuardianData(addr: string, params?: TransactionConfig): Promise<{ip: string, orbsAddr: string, name: string, website: string, contact: string, registration_time: BN|string, last_update_time: BN|string}>;
    getOrbsAddresses(addrs: string[], params?: TransactionConfig): Promise<string[]>;
    getEthereumAddresses(addrs: string[], params?: TransactionConfig): Promise<string[]>;
}

