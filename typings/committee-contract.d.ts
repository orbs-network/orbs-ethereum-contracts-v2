import {TransactionConfig, TransactionReceipt} from "web3-core";
import * as BN from "bn.js";
import {OwnedContract} from "./base-contract";

export interface CommitteeSnapshotEvent {
    addrs: string[];
    weights: (number | BN)[];
    compliance: boolean[];
}

export interface MaxCommitteeSizeChangedEvent {
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
}

export interface MaxTimeBetweenRewardAssignmentsChangedEvent {
    newValue: string|BN;
    oldValue: string|BN;
}

export interface CommitteeContract extends OwnedContract {
    setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    memberWeightChange(addr: string, weight: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
    memberReadyForCommittee(addr: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    memberNotReadyForCommittee(addr: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    memberComplianceChange(addr: string, compliance: boolean, params?: TransactionConfig): Promise<TransactionReceipt>;
    addMember(addr: string, weight: number|BN, compliance: boolean, params?: TransactionConfig): Promise<TransactionReceipt>;
    removeMember(addr: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    getLowestCommitteeMember(params?: TransactionConfig): Promise<string>;
    getCommittee(params?: TransactionConfig): Promise<[string[], Array<number|BN>]>;
    getCommitteeInfo(params?: TransactionConfig): Promise<[string[], Array<number|BN>, string[], boolean[], string[]]>;
    setMaxTimeBetweenRewardAssignments(maxTimeBetweenRewardAssignments: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
    setMaxCommittee(maxCommitteeSize: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;

    getSettings(params?: TransactionConfig): Promise<[string /* maxTimeBetweenRewardAssignments */, string /* maxCommitteeSize */]>;
    getTopology(): Promise<TransactionReceipt>;
}
