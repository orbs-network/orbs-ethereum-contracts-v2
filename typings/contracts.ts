import { ContractRegistryContract } from "./contract-registry-contract";
import { ERC20Contract } from "./erc20-contract";
import { ElectionsContract } from "./elections-contract";
import { SubscriptionsContract } from "./subscriptions-contract";
import { ProtocolContract } from "./protocol-contract";
import { StakingContract } from "./staking-contract";
import { MonthlySubscriptionPlanContract } from "./monthly-subscription-plan-contract";
import { GuardiansRegistrationContract } from "./guardian-registration-contract";
import { CommitteeContract } from "./committee-contract";
import { CertificationContract } from "./certification-contract";
import { DelegationContract } from "./delegation-contract";
import {RewardsContract} from "./rewards-contract";
import {ProtocolWalletContract} from "./protocol-wallet-contract";
import {FeesWalletContract} from "./fees-wallet-contract";
import {
    StakingContractHandlerContract
} from "./stake-change-handler-contract";

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
    Certification: CertificationContract;
    GuardiansRegistration: GuardiansRegistrationContract;
    Committee: CommitteeContract;
    Delegation: DelegationContract;
    ProtocolWallet: ProtocolWalletContract;
    FeesWallet: FeesWalletContract;
    StakingContractHandler: StakingContractHandlerContract;
}
