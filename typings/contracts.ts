import { ContractRegistryContract } from "./contract-registry-contract";
import { ERC20Contract } from "./erc20-contract";
import { StakingRewardsContract } from "./staking-rewards-contract";
import { BootstrapRewardsContract } from "./bootstrap-rewards-contract";
import { FeesContract } from "./fees-contract";
import { ElectionsContract } from "./elections-contract";
import { SubscriptionsContract } from "./subscriptions-contract";
import { ProtocolContract } from "./protocol-contract";
import { StakingContract } from "./staking-contract";
import { MonthlySubscriptionPlanContract } from "./monthly-subscription-plan-contract";
import { Contract } from "../eth";

/**
 * Dictionary type
 * Maps contract name to API
 */
export type Contracts = {
    ContractRegistry: ContractRegistryContract & Contract;
    TestingERC20: ERC20Contract & Contract;
    StakingRewards: StakingRewardsContract & Contract;
    BootstrapRewards: BootstrapRewardsContract & Contract;
    Fees: FeesContract & Contract;
    Elections: ElectionsContract & Contract;
    Subscriptions: SubscriptionsContract & Contract;
    Protocol: ProtocolContract & Contract;
    StakingContract: StakingContract & Contract;
    MonthlySubscriptionPlan: MonthlySubscriptionPlanContract & Contract;
}
