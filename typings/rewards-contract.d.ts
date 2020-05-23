import {TransactionConfig, TransactionReceipt} from "web3-core";
import {Contract} from "../eth";
import * as BN from "bn.js";

export interface RewardsContract extends Contract {
    // staking rewards
    distributeOrbsTokenStakingRewards(totalAmount: (number|BN), fromBlock: (number|BN), toBlock: (number|BN), split: (number|BN), txIndex: (number|BN), to: string[], amounts: (number | BN)[], params?: TransactionConfig): Promise<TransactionReceipt>;
    setAnnualStakingRewardsRate(annual_rate_in_percent_mille: number | BN, annual_cap: number | BN,  params?: TransactionConfig): Promise<TransactionReceipt>;
    topUpStakingRewardsPool(amount: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;
    getStakingRewardBalance(address: string): Promise<string>;

    // bootstrap rewards
    setGeneralCommitteeAnnualBootstrap(annual_bootstrap: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;
    setComplianceCommitteeAnnualBootstrap(annual_bootstrap: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;
    topUpBootstrapPool(amount: number | BN, params?: TransactionConfig): Promise<TransactionReceipt>;

    withdrawBootstrapFunds(params?: TransactionConfig): Promise<TransactionReceipt>;
    getBootstrapBalance(address: string): Promise<string>;

    setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;

    // fees
    withdrawFeeFunds(params?: TransactionConfig): Promise<TransactionReceipt>;
    getFeeBalance(address: string): Promise<string>;
    getLastFeesAssignment(): Promise<string>;

}
