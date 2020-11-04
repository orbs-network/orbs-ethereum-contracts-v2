import {TransactionConfig, TransactionReceipt} from "web3-core";
import * as BN from "bn.js";
import {ManagedContract} from "./base-contract";

export interface MaxCommitteeSizeChangedEvent {
    newValue: string|BN;
    oldValue: string|BN;
}

export interface CommitteeChangeEvent {
    addr: string;
    weight: string|BN;
    certification: boolean;
    inCommittee: boolean;
}

export interface CommitteeSnapshotEvent {
    addrs: string[];
    weights: (string|BN)[];
    certification: boolean[];
}

export interface CommitteeContract extends ManagedContract {
    setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    memberWeightChange(addr: string, weight: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
    memberCertificationChange(addr: string, isCertified: boolean, params?: TransactionConfig): Promise<TransactionReceipt>;
    memberWeightChange(addr: string, weight: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
    addMember(addr: string, weight: number|BN, certification: boolean, params?: TransactionConfig): Promise<TransactionReceipt>;
    removeMember(addr: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    getLowestCommitteeMember(params?: TransactionConfig): Promise<string>;
    getCommittee(params?: TransactionConfig): Promise<[string[], Array<number|BN>, Array<boolean>]>;
    setMaxCommitteeSize(maxCommitteeSize: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
    getMaxCommitteeSize(): Promise<number>;
    getMemberInfo(addr: string): Promise<{inCommittee: boolean, weight: string, isCertified: boolean, totalCommitteeWeight: string}>
    emitCommitteeSnapshot(): Promise<TransactionReceipt>;
    importMembers(previousCommitteeContract: string, TransactionConfig): Promise<TransactionReceipt>;
    getTopology(): Promise<TransactionReceipt>;
}
