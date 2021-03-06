import {TransactionConfig, TransactionReceipt} from "web3-core";
import * as BN from "bn.js";
import {ManagedContract} from "./base-contract";

export interface StakingRewardsAllocatedEvent {
    allocatedRewards: (string|BN);
    stakingRewardsPerWeight: (string|BN);
}

export interface GuardianStakingRewardsAssignedEvent {
    guardian: string,
    amount: (string|BN),
    totalAwarded: (string|BN),
    stakingRewardsPerWeight: (string|BN),
    delegatorRewardsPerToken: (string|BN),
    stakingRewardsPerWeightDelta: (string|BN),
    delegatorRewardsPerTokenDelta: (string|BN)
}

export interface DelegatorStakingRewardsAssignedEvent {
    delegator: string,
    amount: (string|BN),
    totalAwarded: (string|BN),
    guardian: string,
    delegatorRewardsPerToken: (string|BN),
    delegatorRewardsPerTokenDelta: (string|BN)
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
    claimedDelegatorRewards: number|BN;
    claimedGuardianRewards: number|BN;
    totalClaimedDelegatorRewards: number|BN;
    totalClaimedGuardianRewards: number|BN;
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

export interface StakingRewardsContract extends ManagedContract {
    assignRewards(params?: TransactionConfig): Promise<TransactionReceipt>; // TODO remove
    deactivateRewardDistribution(params?: TransactionConfig): Promise<TransactionReceipt>;

    activateRewardDistribution(startTime: number, params?: TransactionConfig): Promise<TransactionReceipt>;

    // staking rewards
    claimStakingRewards(addr: string, params?: TransactionConfig): Promise<TransactionReceipt>;

    setAnnualStakingRewardsRate(annual_rate_in_percent_mille: number | BN, annual_cap: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;

    setDefaultDelegatorsStakingRewardsPercentMille(defaultDelegatorsStakingRewardsPercentMille: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;

    setMaxDelegatorsStakingRewardsPercentMille(defaultDelegatorsStakingRewardsPercentMille: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;

    setGuardianDelegatorsStakingRewardsPercentMille(delegatorsStakingRewardsPercentMille: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;

    getStakingRewardsBalance(address: string): Promise<{delegatorStakingRewardsBalance: string, guardianStakingRewardsBalance: string}>;

    estimateFutureRewards(address: string, duration: number): Promise<{estimatedDelegatorStakingRewards: string, estimatedGuardianStakingRewards: string}>;

    getLastRewardAssignmentTime(): Promise<string>;

    migrateRewardsBalance(addrs: string[], params?: TransactionConfig): Promise<TransactionReceipt>;

    acceptRewardsBalanceMigration(addrs: string[], guardianAmounts: Array<number | BN>, delegatorAmounts: Array<number | BN>, totalAmount: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;

    getGuardianDelegatorsStakingRewardsPercentMille(guardian: string): Promise<string | BN>;

    getGuardianStakingRewardsData(guardian: string, params?: TransactionConfig): Promise<{
        balance: string,
        claimed: string,
        delegatorRewardsPerToken: string,
        delegatorRewardsPerTokenDelta: string,
        lastStakingRewardsPerWeight: string,
        stakingRewardsPerWeightDelta: string
    }>;

    guardiansStakingRewards(guardian: string, params?: TransactionConfig): Promise<{
        balance: string,
        delegatorRewardsPerToken: string,
        lastStakingRewardsPerWeight: string
    }>;

    getDelegatorStakingRewardsData(delegator: string, params?: TransactionConfig): Promise<{
        balance: string,
        claimed: string,
        lastDelegatorRewardsPerToken: string,
        delegatorRewardsPerTokenDelta: string,
        guardian: string,
    }>;

    delegatorsStakingRewards(delegator: string, params?: TransactionConfig): Promise<{
        balance: string,
        lastDelegatorRewardsPerToken: string
    }>;

    emergencyWithdraw(token: string, params?: TransactionConfig): Promise<TransactionReceipt>;

    setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;

    getStakingRewardsState(): Promise<{
        stakingRewardsPerWeight: string,
        unclaimedStakingRewards: string
    }>;

    stakingRewardsState(): Promise<{
        stakingRewardsPerWeight: string,
        unclaimedStakingRewards: string,
        lastAssigned: string
    }>;

    getSettings(): Promise<{
        annualStakingRewardsCap: string,
        annualStakingRewardsRatePercentMille: string,
        defaultDelegatorsStakingRewardsPercentMille: string,
        maxDelegatorsStakingRewardsPercentMille: string,
        rewardAllocationActive: boolean
    }>;

    isRewardAllocationActive(): Promise<boolean>;

    stakingRewardsContractBalance(): Promise<string>;

    getCurrentStakingRewardsRatePercentMille(): Promise<number>;

    getStakingRewardsWalletAllocatedTokens(): Promise<number>;

    getDefaultDelegatorsStakingRewardsPercentMille(): Promise<number>;
    getMaxDelegatorsStakingRewardsPercentMille(): Promise<number>;
    getAnnualStakingRewardsRatePercentMille(): Promise<number>;
    getAnnualStakingRewardsCap(): Promise<number>;
}
