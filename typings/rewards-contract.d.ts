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
    delegatorsStakingRewardsPercentMille: string|BN
}

export interface StakingRewardsBalanceMigratedEvent {
    from: string;
    delegatorBalance: number|BN;
    guardianBalance: number|BN;
    toRewardsContract: string;
}

export interface StakingRewardsMigrationAcceptedEvent {
    migrator: string;
    to: string;
    delegatorBalance: number|BN;
    guardianBalance: number|BN;
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

export interface RewardsContract extends OwnedContract {
    assignRewards(params?: TransactionConfig): Promise<TransactionReceipt>; // TODO remove
    deactivate(params?: TransactionConfig): Promise<TransactionReceipt>;
    activate(startTime: number, params?: TransactionConfig): Promise<TransactionReceipt>;

    // staking rewards
    claimStakingRewards(addr: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    setAnnualStakingRewardsRate(annual_rate_in_percent_mille: number | BN, annual_cap: number | BN,  params?: TransactionConfig): Promise<TransactionReceipt>;
    setDefaultDelegatorsStakingRewardsPercentMille(defaultDelegatorsStakingRewardsPercentMille: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;
    getStakingRewardsBalance(address: string): Promise<string>;
    getLastRewardAssignmentTime(): Promise<string>;
    migrateStakingRewardsBalance(guardian: string,  params?: TransactionConfig): Promise<TransactionReceipt>;
    acceptStakingRewardsMigration(guardian: string, delegatorAmount: number|BN, guardianAmount: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;

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

    getSettings(): Promise<any>;
}
