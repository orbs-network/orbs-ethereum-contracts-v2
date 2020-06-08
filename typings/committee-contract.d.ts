import {Contract} from "../eth";
import {TransactionConfig, TransactionReceipt} from "web3-core";
import * as BN from "bn.js";
import {OwnedContract} from "./base-contract";

export interface CommitteeChangedEvent {
    addrs: string[];
    orbsAddrs: string[];
    weights: (number | BN)[];
    compliance: boolean[];
}

export interface StandbysChangedEvent {
    addrs: string[];
    orbsAddrs: string[];
    weights: (number | BN)[];
    compliance: boolean[];
}

export interface CommitteeContract extends OwnedContract {
    setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    memberNotReadyToSync(addr: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    getLowestCommitteeMember(params?: TransactionConfig): Promise<string>;
    getCommittee(params?: TransactionConfig): Promise<[string[], Array<number|BN>]>;
    getStandbys(params?: TransactionConfig): Promise<[string[], Array<number|BN>]>;
    getCommitteeInfo(params?: TransactionConfig): Promise<[string[], Array<number|BN>, string[], boolean[], string[]]>;
    getStandbysInfo(params?: TransactionConfig): Promise<[string[], Array<number|BN>, string[], boolean[], string[]]>;
    getTopology(): Promise<TransactionReceipt>;
}
