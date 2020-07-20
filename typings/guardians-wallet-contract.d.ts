import {TransactionConfig, TransactionReceipt} from "web3-core";
import {Contract} from "../eth";
import * as BN from "bn.js";
import {OwnedContract} from "./base-contract";

export interface StakingRewardsDistributedEvent {
    distributer: string,
    fromBlock: string|BN,
    toBlock: string|BN,
    split: string|BN,
    txIndex: string|BN,
    to: string[],
    amounts: (string|BN)[]
}

export interface FeesWithdrawnEvent {
    guardian: string,
    amount: string|BN
}

export interface BootstrapRewardsWithdrawnEvent {
    guardian: string,
    amount: string|BN
}

export interface MaxDelegatorsStakingRewardsChangedEvent {
    maxDelegatorsStakingRewardsPercentMille: string|BN
}

export interface RewardsAssignedEvent {
    assignees: string[],
    stakingRewards: (string|BN)[],
    fees: (string|BN)[],
    bootstrapRewards: (string|BN)[]
}

export interface GuardiansWalletContract extends OwnedContract {
    assignRewardsToGuardians(guardians: string[],
                             stakingRewards: (number|BN)[],
                             stakingRewardsWallet: string,
                             fees: (number|BN)[],
                             feesWallet: string,
                             bootstrapRewards: (number|BN)[],
                             bootstrapRewardsWallet: string,
                             params?: TransactionConfig): Promise<TransactionReceipt>;

    // staking rewards
    distributeStakingRewards(totalAmount: (number|BN), fromBlock: (number|BN), toBlock: (number|BN), split: (number|BN), txIndex: (number|BN), to: string[], amounts: (number | BN)[], params?: TransactionConfig): Promise<TransactionReceipt>;
    setMaxDelegatorsStakingRewards(maxDelegatorsStakingRewardsPercentMille: number | BN,  params?: TransactionConfig): Promise<TransactionReceipt>;
    getStakingRewardBalance(address: string): Promise<string>;

    // bootstrap rewards
    withdrawBootstrapFunds(params?: TransactionConfig): Promise<TransactionReceipt>;
    getBootstrapBalance(address: string): Promise<string>;

    // fees
    withdrawFees(params?: TransactionConfig): Promise<TransactionReceipt>;
    getFeeBalance(address: string): Promise<string>;

    emergencyWithdraw(params?: TransactionConfig): Promise<TransactionReceipt>;

    setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;

}
