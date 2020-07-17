import {TransactionConfig, TransactionReceipt} from "web3-core";
import {Contract} from "../eth";
import * as BN from "bn.js";
import {OwnedContract} from "./base-contract";

export interface FeesAddedToBucketEvent {
    bucketId: string|BN,
    added: string|BN,
    total: string|BN,
    isCertified: boolean
}

export interface FeesWithdrawnFromBucketEvent {
    bucketId: string|BN,
    withdrawen: string|BN,
    total: string|BN,
    isCertified: boolean
}

export interface RewardsContract extends OwnedContract {
    assignRewards(params?: TransactionConfig): Promise<TransactionReceipt>;

    // staking rewards
    setAnnualStakingRewardsRate(annual_rate_in_percent_mille: number | BN, annual_cap: number | BN,  params?: TransactionConfig): Promise<TransactionReceipt>;
    getLastRewardAssignmentTime(): Promise<string>;

    // bootstrap rewards
    setGeneralCommitteeAnnualBootstrap(annual_bootstrap: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;
    setCertificationCommitteeAnnualBootstrap(annual_bootstrap: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;

    setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;
}
