import {TransactionConfig, TransactionReceipt} from "web3-core";
import {Contract} from "../eth";
import * as BN from "bn.js";
import {OwnedContract} from "./base-contract";

export interface FeesAddedToBucketEvent {
    bucketId: string|BN,
    added: string|BN,
    total: string|BN,
}

export interface FeesWithdrawnFromBucketEvent {
    bucketId: string|BN,
    withdrawn: string|BN,
    total: string|BN,
}

export interface FeesWalletContract extends OwnedContract {
    fillFeeBuckets(amount: number|BN, monthlyRate: number|BN, fromTimestamp: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
    collectFees(params?: TransactionConfig): Promise<TransactionReceipt>;
    emergencyWithdrawal(params?: TransactionConfig): Promise<TransactionReceipt>;
    migrateBucket(destination: string, bucektStartTime: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
    emergencyWithdraw(token: string, params?: TransactionConfig): Promise<TransactionReceipt>;

    setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;
}
