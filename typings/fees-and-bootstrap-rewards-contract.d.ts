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

export interface FeesWithdrawnEvent {
    guardian: string,
    amount: (string|BN),
}

export interface BootstrapRewardsWithdrawnEvent {
    guardian: string,
    amount: string|BN
}

export interface FeesAndBootstrapRewardsBalanceMigratedEvent {
    guardian: string;
    fees: number|BN;
    bootstrapRewards: number|BN;
    toRewardsContract: string;
}

export interface FeesAndBootstrapRewardsBalanceMigrationAcceptedEvent {
    from: string;
    guardian: string;
    bootstrapRewards: number|BN|string;
    fees: number|BN|string;
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

export interface FeesAllocatedEvent {
    allocatedGeneralFees: number|BN|string;
    generalFeesPerMember: number|BN|string;
    allocatedCertifiedFees: number|BN|string;
    certifiedFeesPerMember: number|BN|string;
}

export interface BootstrapRewardsAllocatedEvent {
    allocatedGeneralBootstrapRewards: number|BN|string;
    generalBootstrapRewardsPerMember: number|BN|string;
    allocatedCertifiedBootstrapRewards: number|BN|string;
    certifiedBootstrapRewardsPerMember: number|BN|string;
}

export interface FeesAndBootstrapRewardsContract extends OwnedContract {
    deactivateRewardDistribution(params?: TransactionConfig): Promise<TransactionReceipt>;

    activateRewardDistribution(startTime: number, params?: TransactionConfig): Promise<TransactionReceipt>;

    // bootstrap rewards
    setGeneralCommitteeAnnualBootstrap(annual_bootstrap: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;
    setCertifiedCommitteeAnnualBootstrap(annual_bootstrap: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;

    withdrawBootstrapFunds(guardian: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    getBootstrapBalance(address: string): Promise<string>;

    emergencyWithdraw(token: string, params?: TransactionConfig): Promise<TransactionReceipt>;

    // fees
    withdrawFees(guardian: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    getFeesAndBootstrapBalance(address: string): Promise<{feeBalance: string, bootstrapBalance: string}>;
    getFeesAndBootstrapData(address: string): Promise<{feeBalance: string, lastFeesPerMember:string, bootstrapBalance: string, lastBootstrapPerMember: string}>;

    estimateFutureFeesAndBootstrapRewards(guardian: string, duration: number): Promise<{estimatedFees: number, estimatedBootstrapRewards: number}>;

    emergencyWithdraw(params?: TransactionConfig): Promise<TransactionReceipt>;

    migrateRewardsBalance(addr: string, params?: TransactionConfig): Promise<TransactionReceipt>;

    acceptRewardsBalanceMigration(addr: string, fees: number | BN, bootstrap: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;

    setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;

    getSettings(): Promise<{
        generalCommitteeAnnualBootstrap: string,
        certifiedCommitteeAnnualBootstrap: string,
        rewardAllocationActive: boolean
    }>;

    isRewardAllocationActive(): Promise<boolean>;
}
