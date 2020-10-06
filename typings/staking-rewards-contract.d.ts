import {TransactionConfig, TransactionReceipt} from "web3-core";
import * as BN from "bn.js";
import {OwnedContract} from "./base-contract";

export interface GuardianStakingRewardAssignedEvent {
    guardian: string,
    amount: (string|BN),
    delegatorRewardsPerToken: (string|BN)
}

export interface StakingRewardAssignedEvent {
    addr: string,
    amount: (string|BN),
}

export interface DefaultDelegatorsStakingRewardsChangedEvent {
    defaultDelegatorsStakingRewardsPercentMille: string|BN
}

export interface MaxDelegatorsStakingRewardsChangedEvent {
    maxDelegatorsStakingRewardsPercentMille: string|BN
}

export interface StakingRewardsBalanceMigratedEvent {
    addr: string;
    guardianStakingRewards: number|BN;
    delegatorStakingRewards: number|BN;
    toRewardsContract: string;
}

export interface StakingRewardsBalanceMigrationAcceptedEvent {
    from: string;
    addr: string;
    guardianStakingRewards: number|BN|string;
    delegatorStakingRewards: number|BN|string;
}

export interface StakingRewardsClaimedEvent {
    addr: string;
    amount: number|BN;
}

export interface AnnualStakingRewardsRateChangedEvent {
    annualRateInPercentMille: number|BN;
    annualCap: number|BN;
}

export interface RewardDistributionDeactivatedEvent {}

export interface RewardDistributionActivatedEvent {
    startTime: number|BN
}

export interface GuardianDelegatorsStakingRewardsPercentMilleUpdatedEvent {
    guardian: string,
    delegatorsStakingRewardsPercentMille: number|BN
}

export interface StakingRewardsContract extends OwnedContract {
    assignRewards(params?: TransactionConfig): Promise<TransactionReceipt>; // TODO remove
    deactivateRewardDistribution(params?: TransactionConfig): Promise<TransactionReceipt>;

    activateRewardDistribution(startTime: number, params?: TransactionConfig): Promise<TransactionReceipt>;

    // staking rewards
    claimStakingRewards(addr: string, params?: TransactionConfig): Promise<TransactionReceipt>;

    setAnnualStakingRewardsRate(annual_rate_in_percent_mille: number | BN, annual_cap: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;

    setDefaultDelegatorsStakingRewardsPercentMille(defaultDelegatorsStakingRewardsPercentMille: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;

    setMaxDelegatorsStakingRewardsPercentMille(defaultDelegatorsStakingRewardsPercentMille: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;

    setGuardianDelegatorsStakingRewardsPercentMille(delegatorsStakingRewardsPercentMille: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;

    getStakingRewardsBalance(address: string): Promise<string>;

    getLastRewardAssignmentTime(): Promise<string>;

    migrateRewardsBalance(addr: string, params?: TransactionConfig): Promise<TransactionReceipt>;

    acceptRewardsBalanceMigration(addr: string, guardianAmount: number | BN, delegatorAmount: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;

    getGuardianDelegatorsStakingRewardsPercentMille(guardian: string): Promise<string | BN>;

    getGuardianStakingRewardsData(guardian: string, params?: TransactionConfig): Promise<{
        balance: string,
        delegatorRewardsPerToken: string,
        lastStakingRewardsPerWeight: string
    }>;

    getDelegatorStakingRewardsData(delegator: string, params?: TransactionConfig): Promise<{
        balance: string,
        lastDelegatorRewardsPerToken: string
    }>;

    emergencyWithdraw(params?: TransactionConfig): Promise<TransactionReceipt>;

    setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;

    getStakingRewardsState(): Promise<{
        stakingRewardsPerWeight: string,
        unclaimedStakingRewards: string
    }>;

    getSettings(): Promise<{
        annualStakingRewardsCap: string,
        annualStakingRewardsRatePercentMille: string,
        defaultDelegatorsStakingRewardsPercentMille: string,
        maxDelegatorsStakingRewardsPercentMille: string,
        rewardAllocationActive: boolean
    }>;
}
