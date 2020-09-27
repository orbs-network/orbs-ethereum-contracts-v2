import {TransactionConfig, TransactionReceipt} from "web3-core";
import * as BN from "bn.js";
import {OwnedContract} from "./base-contract";

export interface FeesAssignedEvent {
    guardian: string,
    amount: (string|BN),
}

export interface BootstrapRewardsAssignedEvent {
    guardian: string,
    amount: (string|BN),
}

export interface GuardianStakingRewardAssignedEvent {
    guardian: string,
    amount: (string|BN),
    delegatorRewardsPerToken: (string|BN)
}

export interface StakingRewardAssignedEvent {
    addr: string,
    amount: (string|BN),
}

export interface FeesWithdrawnEvent {
    guardian: string,
    amount: (string|BN),
}

export interface BootstrapRewardsWithdrawnEvent {
    guardian: string,
    amount: string|BN
}

export interface DefaultDelegatorsStakingRewardsChangedEvent {
    defaultDelegatorsStakingRewardsPercentMille: string|BN
}

export interface MaxDelegatorsStakingRewardsChangedEvent {
    maxDelegatorsStakingRewardsPercentMille: string|BN
}

export interface RewardsBalanceMigratedEvent {
    from: string;
    guardianStakingRewards: number|BN;
    delegatorStakingRewards: number|BN;
    bootstrapRewards: number|BN;
    fees: number|BN;
    toRewardsContract: string;
}

export interface RewardsBalanceMigrationAcceptedEvent {
    from: string;
    to: string;
    guardianStakingRewards: number|BN|string;
    delegatorStakingRewards: number|BN|string;
    bootstrapRewards: number|BN|string;
    fees: number|BN|string;
}

export interface StakingRewardsClaimedEvent {
    addr: string;
    amount: number|BN;
}

export interface AnnualStakingRewardsRateChangedEvent {
    annualRateInPercentMille: number|BN;
    annualCap: number|BN;
}

export interface GeneralCommitteeAnnualBootstrapChangedEvent {
    generalCommitteeAnnualBootstrap: number|BN;
}

export interface CertifiedCommitteeAnnualBootstrapChangedEvent {
    certifiedCommitteeAnnualBootstrap: number|BN;
}

export interface RewardDistributionDeactivatedEvent {}

export interface RewardDistributionActivatedEvent {
    startTime: number|BN
}

export interface GuardianDelegatorsStakingRewardsPercentMilleUpdatedEvent {
    guardian: string,
    delegatorsStakingRewardsPercentMille: number|BN
}

export interface RewardsContract extends OwnedContract {
    assignRewards(params?: TransactionConfig): Promise<TransactionReceipt>; // TODO remove
    deactivate(params?: TransactionConfig): Promise<TransactionReceipt>;
    activate(startTime: number, params?: TransactionConfig): Promise<TransactionReceipt>;

    // staking rewards
    claimStakingRewards(addr: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    setAnnualStakingRewardsRate(annual_rate_in_percent_mille: number | BN, annual_cap: number | BN,  params?: TransactionConfig): Promise<TransactionReceipt>;
    setDefaultDelegatorsStakingRewardsPercentMille(defaultDelegatorsStakingRewardsPercentMille: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;
    setMaxDelegatorsStakingRewardsPercentMille(defaultDelegatorsStakingRewardsPercentMille: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;
    setGuardianDelegatorsStakingRewardsPercentMille(delegatorsStakingRewardsPercentMille: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;
    getStakingRewardsBalance(address: string): Promise<string>;
    getLastRewardAssignmentTime(): Promise<string>;
    migrateRewardsBalance(addr: string,  params?: TransactionConfig): Promise<TransactionReceipt>;
    acceptRewardsBalanceMigration(addr: string, guardianAmount: number|BN, delegatorAmount: number|BN, fees: number|BN, bootstrap: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
    getGuardianDelegatorsStakingRewardsPercentMille(guardian: string): Promise<string|BN>;

    // bootstrap rewards
    setGeneralCommitteeAnnualBootstrap(annual_bootstrap: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;
    setCertifiedCommitteeAnnualBootstrap(annual_bootstrap: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;

    withdrawBootstrapFunds(guardian: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    getBootstrapBalance(address: string): Promise<string>;

    emergencyWithdraw(params?: TransactionConfig): Promise<TransactionReceipt>;

    // fees
    withdrawFees(guardian: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    getFeeBalance(address: string): Promise<string>;

    emergencyWithdraw(params?: TransactionConfig): Promise<TransactionReceipt>;

    setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;

    getGeneralCommitteeAnnualBootstrap(): Promise<string>;
    getCertifiedCommitteeAnnualBootstrap(): Promise<string>;
    getDefaultDelegatorsStakingRewardsPercentMille(): Promise<string>;
    getAnnualStakingRewardsRatePercentMille(): Promise<string>;
    getAnnualStakingRewardsCap(): Promise<string>;

    getSettings(): Promise<{
        generalCommitteeAnnualBootstrap: string,
        certifiedCommitteeAnnualBootstrap: string,
        annualStakingRewardsCap: string,
        annualStakingRewardsRatePercentMille: string,
        defaultDelegatorsStakingRewardsPercentMille: string,
        maxDelegatorsStakingRewardsPercentMille: string,
        active: boolean
    }>;
}
