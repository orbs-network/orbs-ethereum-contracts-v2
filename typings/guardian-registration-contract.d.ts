import {Contract} from "../eth";

import {TransactionConfig, TransactionReceipt} from "web3-core";
import * as BN from "bn.js";
import {OwnedContract} from "./base-contract";

export interface GuardianRegisteredEvent {
    guardian: string,
}

export interface GuardianDataUpdatedEvent {
    guardian: string,
    isRegistered: boolean,
    ip: string,
    orbsAddr: string,
    name: string,
    website: string
}

export interface GuardianUnregisteredEvent {
    guardian: string
}

export interface GuardianMetadataChangedEvent {
    guardian: string,
    key: string,
    oldValue: string,
    newValue: string,
}

export interface GuardiansRegistrationContract extends OwnedContract {
    setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    registerGuardian(ip: string, orbsAddr: string, name: string, website: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    unregisterGuardian(params?: TransactionConfig): Promise<TransactionReceipt>;
    updateGuardian(ip: string, orbsAddr: string, name: string, website: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    updateGuardianIp(ip: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    resolveGuardianAddress(ethereumOrOrbs: string, params?: TransactionConfig): Promise<string>;
    setMetadata(key: string, value: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    getMetadata(addr: string, key: string, params?: TransactionConfig): Promise<string>;
    getGuardianData(addr: string, params?: TransactionConfig): Promise<{ip: string, orbsAddr: string, name: string, website: string, registrationTime: BN|string, lastUpdateTime: BN|string}>;
    getGuardiansOrbsAddress(addrs: string[], params?: TransactionConfig): Promise<string[]>;
    getGuardianAddresses(addrs: string[], params?: TransactionConfig): Promise<string[]>;
}

