import { ContractRegistryContract } from "./contract-registry-contract";
import { ERC20Contract } from "./erc20-contract";
import { RewardsContract } from "./rewards-contract";
import { ElectionsContract } from "./elections-contract";
import { SubscriptionsContract } from "./subscriptions-contract";
import { ProtocolContract } from "./protocol-contract";
import { StakingContract } from "./staking-contract";
import { MonthlySubscriptionPlanContract } from "./monthly-subscription-plan-contract";
import { Contract } from "../eth";
import {ComplianceContract} from "./compliance-contract";

/**
 * Dictionary type
 * Maps contract name to API
 */
export type Contracts = {
    ContractRegistry: ContractRegistryContract & Contract;
    TestingERC20: ERC20Contract & Contract;
    Rewards: RewardsContract & Contract;
    Elections: ElectionsContract & Contract;
    Subscriptions: SubscriptionsContract & Contract;
    Protocol: ProtocolContract & Contract;
    StakingContract: StakingContract & Contract;
    MonthlySubscriptionPlan: MonthlySubscriptionPlanContract & Contract;
    Compliance: ComplianceContract & Contract;
}
