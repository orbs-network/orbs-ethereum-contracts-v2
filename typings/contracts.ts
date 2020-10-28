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
import { DelegationsContract } from "./delegations-contract";
import {ProtocolWalletContract} from "./protocol-wallet-contract";
import {FeesWalletContract} from "./fees-wallet-contract";
import {
    StakingContractHandlerContract
} from "./stake-change-handler-contract";
import {StakingRewardsContract} from "./staking-rewards-contract";
import {FeesAndBootstrapRewardsContract} from "./fees-and-bootstrap-rewards-contract";

/**
 * Dictionary type
 * Maps contract name to API
 */
export type Contracts = {
    ContractRegistry: ContractRegistryContract;
    TestingERC20: ERC20Contract;
    StakingRewards: StakingRewardsContract;
    FeesAndBootstrapRewards: FeesAndBootstrapRewardsContract;
    Elections: ElectionsContract;
    Subscriptions: SubscriptionsContract;
    Protocol: ProtocolContract;
    StakingContract: StakingContract;
    MonthlySubscriptionPlan: MonthlySubscriptionPlanContract;
    Certification: CertificationContract;
    GuardiansRegistration: GuardiansRegistrationContract;
    Committee: CommitteeContract;
    Delegations: DelegationsContract;
    ProtocolWallet: ProtocolWalletContract;
    FeesWallet: FeesWalletContract;
    StakingContractHandler: StakingContractHandlerContract;
}

export type ContractName = keyof Contracts;
