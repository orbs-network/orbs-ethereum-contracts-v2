import {TransactionConfig, TransactionReceipt} from "web3-core";
import * as BN from "bn.js";
import {OwnedContract} from "./base-contract";

export interface CommitteeSnapshotEvent {
    addrs: string[];
    weights: (number | BN)[];
    certification: boolean[];
}

export interface MaxCommitteeSizeChangedEvent {
    newValue: string|BN;
    oldValue: string|BN;
}

export interface GuardianStatusUpdatedEvent {
    addr: string;
    readyToSync: boolean;
    readyForCommittee: boolean;
}

export interface GuardianCommitteeChangeEvent {
    addr: string;
    weight: string|BN;
    certification: boolean;
    inCommittee: boolean;
}

export interface MaxTimeBetweenRewardAssignmentsChangedEvent {
    newValue: string|BN;
    oldValue: string|BN;
}

export interface CommitteeContract extends OwnedContract {
    setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    memberChange(addr: string, weight: number|BN, isCertified: boolean, params?: TransactionConfig): Promise<TransactionReceipt>;
    memberWeightChange(addr: string, weight: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
    addMember(addr: string, weight: number|BN, certification: boolean, params?: TransactionConfig): Promise<TransactionReceipt>;
    removeMember(addr: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    getLowestCommitteeMember(params?: TransactionConfig): Promise<string>;
    getCommittee(params?: TransactionConfig): Promise<[string[], Array<number|BN>, Array<boolean>]>;
    getCommitteeInfo(params?: TransactionConfig): Promise<[string[], Array<number|BN>, string[], boolean[], string[]]>;
    setMaxTimeBetweenRewardAssignments(maxTimeBetweenRewardAssignments: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
    setMaxCommitteeSize(maxCommitteeSize: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
    getMaxTimeBetweenRewardAssignments(): Promise<number>;
    getMaxCommitteeSize(): Promise<number>;

    getSettings(params?: TransactionConfig): Promise<[string /* maxTimeBetweenRewardAssignments */, string /* maxCommitteeSize */]>;
    getTopology(): Promise<TransactionReceipt>;
}
