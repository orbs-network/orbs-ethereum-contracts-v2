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
    setMinimumWeight(minimumWeight: number, minCommitteeSize: number, params?: TransactionConfig): Promise<TransactionReceipt>;
    memberNotReadyToSync(addr: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    getTopology(): Promise<TransactionReceipt>;
}
