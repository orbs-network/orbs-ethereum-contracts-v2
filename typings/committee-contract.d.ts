import {Contract} from "../eth";
import {TransactionConfig, TransactionReceipt} from "web3-core";
import * as BN from "bn.js";
import {OwnedContract} from "./base-contract";

export interface CommitteeSnapshotEvent {
    addrs: string[];
    weights: (number | BN)[];
    compliance: boolean[];
}

export interface ReadyToSyncTimeoutChangedEvent {
    newValue: string|BN;
    oldValue: string|BN;
}

export interface MaxCommitteeSizeChangedEvent {
    newValue: string|BN;
    oldValue: string|BN;
}

export interface MaxStandbysChangedEvent {
    newValue: string|BN;
    oldValue: string|BN;
}

export interface ValidatorStatusUpdatedEvent {
    addr: string;
    readyToSync: boolean;
    readyForCommittee: boolean;
}

export interface ValidatorCommitteeChangeEvent {
    addr: string;
    weight: string|BN;
    compliance: boolean;
    inCommittee: boolean;
    isStandby: boolean;
}

export interface MaxTimeBetweenRewardAssignmentsChangedEvent {
    newValue: string|BN;
    oldValue: string|BN;
}

export interface CommitteeContract extends OwnedContract {
    setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    memberWeightChange(addr: string, weight: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
    memberReadyToSync(addr: string, readyForCommittee: boolean, params?: TransactionConfig): Promise<TransactionReceipt>;
    memberNotReadyToSync(addr: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    memberComplianceChange(addr: string, compliance: boolean, params?: TransactionConfig): Promise<TransactionReceipt>;
    addMember(addr: string, weight: number|BN, compliance: boolean, params?: TransactionConfig): Promise<TransactionReceipt>;
    removeMember(addr: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    getLowestCommitteeMember(params?: TransactionConfig): Promise<string>;
    getCommittee(params?: TransactionConfig): Promise<[string[], Array<number|BN>]>;
    getStandbys(params?: TransactionConfig): Promise<[string[], Array<number|BN>, boolean[]]>;
    getCommitteeInfo(params?: TransactionConfig): Promise<[string[], Array<number|BN>, string[], boolean[], string[]]>;
    getStandbysInfo(params?: TransactionConfig): Promise<[string[], Array<number|BN>, string[], boolean[], string[]]>;
    setReadyToSyncTimeout(readyToSyncTimeout: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
    setMaxTimeBetweenRewardAssignments(maxTimeBetweenRewardAssignments: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
    setMaxCommitteeAndStandbys(maxCommitteeSize: number|BN, maxStandbys: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;

    getSettings(params?: TransactionConfig): Promise<[string /* readyToSyncTimeout */, string /* maxTimeBetweenRewardAssignments */, string /* maxCommitteeSize */, string /* maxStandbys */]>;
    getTopology(): Promise<TransactionReceipt>;

}
