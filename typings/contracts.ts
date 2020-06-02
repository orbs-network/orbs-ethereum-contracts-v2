import { ContractRegistryContract } from "./contract-registry-contract";
import { ERC20Contract } from "./erc20-contract";
import { ElectionsContract } from "./elections-contract";
import { SubscriptionsContract } from "./subscriptions-contract";
import { ProtocolContract } from "./protocol-contract";
import { StakingContract } from "./staking-contract";
import { MonthlySubscriptionPlanContract } from "./monthly-subscription-plan-contract";
import { Contract } from "../eth";
import { ValidatorsRegistrationContract } from "./validator-registration-contract";
import { CommitteeContract } from "./committee-contract";
import { ComplianceContract } from "./compliance-contract";
import { DelegationsContract } from "./delegations-contract";
import {RewardsContract} from "./rewards-contract";

/**
 * Dictionary type
 * Maps contract name to API
 */
export type Contracts = {
    ContractRegistry: ContractRegistryContract;
    TestingERC20: ERC20Contract;
    Rewards: RewardsContract;
    Elections: ElectionsContract;
    Subscriptions: SubscriptionsContract;
    Protocol: ProtocolContract;
    StakingContract: StakingContract;
    MonthlySubscriptionPlan: MonthlySubscriptionPlanContract;
    Compliance: ComplianceContract;
    ValidatorsRegistration: ValidatorsRegistrationContract;
    Committee: CommitteeContract;
    Delegations: DelegationsContract;
}
