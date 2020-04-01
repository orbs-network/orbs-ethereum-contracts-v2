import {Contract} from "../eth";
import {TransactionConfig, TransactionReceipt} from "web3-core";
import * as BN from "bn.js";

export interface CommitteeChangedEvent {
    addrs: string[];
    orbsAddrs: string[];
    weights: (number | BN)[];
}

export interface StandbysChangedEvent {
    addrs: string[];
    orbsAddrs: string[];
    weights: (number | BN)[];
}

export interface CommitteeContract extends Contract {
    setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    setMinimumWeight(minimumWeight: number, minimumAddress: string, minCommitteeSize: number, params?: TransactionConfig): Promise<TransactionReceipt>;
    memberNotReadyToSync(addr: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    getLowestCommitteeMember(params?: TransactionConfig): Promise<string>;
    getCommittee(params?: TransactionConfig): Promise<[string[], Array<number|BN>]>;
    getStandbys(params?: TransactionConfig): Promise<[string[], Array<number|BN>]>;
    getCommitteeInfo(params?: TransactionConfig): Promise<[string[], Array<number|BN>, string[], string[]]>;
    getStandbysInfo(params?: TransactionConfig): Promise<[string[], Array<number|BN>, string[], string[]]>;
    getTopology(): Promise<TransactionReceipt>;
}
