import BN from "bn.js";
import chai from "chai";
chai.use(require('chai-bn')(BN));

export const ZERO_ADDR = "0x0000000000000000000000000000000000000000";

import { ElectionsContract } from "../typings/elections-contract";
import { DelegationsContract } from "../typings/delegations-contract";
import { ERC20Contract } from "../typings/erc20-contract";
import { StakingContract } from "../typings/staking-contract";
import { MonthlySubscriptionPlanContract } from "../typings/monthly-subscription-plan-contract";
import {ContractRegistryContract} from "../typings/contract-registry-contract";
import { Contracts } from "../typings/contracts";
import {Web3Driver, defaultWeb3Provider, Web3Session} from "../eth";
import Web3 from "web3";
import {GuardiansRegistrationContract} from "../typings/guardian-registration-contract";
import {CertificationContract} from "../typings/certification-contract";
import {TransactionReceipt} from "web3-core";
import {GasRecorder} from "../gas-recorder";
import {stakedEvents} from "./event-parsing";
import {OwnedContract} from "../typings/base-contract";
import {bn} from "./helpers";

export const BANNING_LOCK_TIMEOUT = 7*24*60*60;
export const DEPLOYMENT_SUBSET_MAIN = "main";
export const DEPLOYMENT_SUBSET_CANARY = "canary";

export type DriverOptions = {
    maxCommitteeSize: number;
    minSelfStakePercentMille: number;
    maxTimeBetweenRewardAssignments: number;
    voteUnreadyThreshold: number;
    voteUnreadyTimeout: number;
    voteOutThreshold: number;

    generalCommitteeAnnualBootstrap: number;
    certificationCommitteeAnnualBootstrap: number;
    stakingRewardsAnnualRateInPercentMille: number;
    stakingRewardsAnnualCap: number;
    maxDelegatorsStakingRewardsPercentMille: number;

    stakingRewardsWalletRate: number;
    bootstrapRewardsWalletRate: number;

    subscriptionTier: string;
    subscriptionRate: number;

    genesisRefTimeDelay?: number;

    web3Provider : () => Web3;

    contractRegistryForExistingContractsAddress?: string;
    orbsTokenAddress?: string;
    bootstrapTokenAddress?: string;
    stakingContractAddress?: string;

    contractRegistryAddress?: string;
    delegationsAddress?: string;
    rewardsAddress?: string;
    electionsAddress?: string;
    subscriptionsAddress?: string;
    protocolAddress?: string;
    certificationAddress?: string;
    committeeAddress?: string;
    stakingRewardsWalletAddress?: string;
    bootstrapRewardsWalletAddress?: string;
    guardiansRegistrationAddress?: string;
    generalFeesWalletAddress?: string;
    certifiedFeesWalletAddress?: string;

}
export const defaultDriverOptions: Readonly<DriverOptions> = {
    maxCommitteeSize: 2,
    minSelfStakePercentMille : 0,
    maxTimeBetweenRewardAssignments: 0,
    voteUnreadyThreshold : 80,
    voteUnreadyTimeout : 24 * 60 * 60,
    voteOutThreshold : 80,

    generalCommitteeAnnualBootstrap: 0,
    certificationCommitteeAnnualBootstrap: 0,
    stakingRewardsAnnualRateInPercentMille: 0,
    stakingRewardsAnnualCap: 0,
    maxDelegatorsStakingRewardsPercentMille: 100000,

    stakingRewardsWalletRate: bn(2).pow(bn(94)).sub(bn(1)),
    bootstrapRewardsWalletRate: bn(2).pow(bn(94)).sub(bn(1)),

    subscriptionTier: "test1",
    subscriptionRate: bn(100),

    web3Provider: defaultWeb3Provider,
};

export const betaDriverOptions: Readonly<DriverOptions> = {
    // Committee
    maxCommitteeSize: 22,
    maxTimeBetweenRewardAssignments: 2*24*60*60,

    // Elections
    minSelfStakePercentMille : 8000,
    voteUnreadyThreshold : 70,
    voteUnreadyTimeout : 7 * 24 * 60 * 60,
    voteOutThreshold : 70,

    // Rewards
    generalCommitteeAnnualBootstrap: bn(12).mul(bn(10).pow(bn(18))),
    certificationCommitteeAnnualBootstrap: bn(6).mul(bn(10).pow(bn(18))),
    stakingRewardsAnnualRateInPercentMille: 12000,
    stakingRewardsAnnualCap: bn(12000).mul(bn(10).pow(bn(18))),
    maxDelegatorsStakingRewardsPercentMille: 66667,

    // Protocol wallets
    stakingRewardsWalletRate: bn(12000 * 1.1).mul(bn(10).pow(bn(18))), // staking rewards for entire committee + 10%
    bootstrapRewardsWalletRate: bn((12 + 6) * 22).mul(bn(10).pow(bn(18))).mul(bn(11)).div(bn(10)), // bootstrap rewards for both certified and general, for entire committee + 10%

    // Subscription plan
    subscriptionTier: "beta1",
    subscriptionRate: bn(100).mul(bn(10).pow(bn(18))),

    orbsTokenAddress: "0xff56Cc6b1E6dEd347aA0B7676C85AB0B3D08B0FA",
    bootstrapTokenAddress: "0x6b175474e89094c44da98b954eedeac495271d0f",
    stakingContractAddress: "0x01D59Af68E2dcb44e04C50e05F62E7043F2656C3",

    web3Provider: defaultWeb3Provider,
};

export type ContractName = 'protocol' | 'committee' | 'elections' | 'delegations' | 'guardiansRegistration' | 'certification' | 'staking' | 'subscriptions' | 'rewards' | 'stakingRewardsWallet' | 'guardianWallet' | 'generalFeesWallet' | 'certifiedFeesWallet';

export type ContractName4Testkit = '_bootstrapToken' | '_erc20' ; // TODO remove when resolving https://github.com/orbs-network/orbs-ethereum-contracts-v2/issues/97

export class Driver {
    private static web3DriversCache = new WeakMap<DriverOptions['web3Provider'], Web3Driver>();
    private participants: Participant[] = [];

    constructor(
        public web3: Web3Driver,
        public session: Web3Session,
        public accounts: string[],
        public elections: Contracts["Elections"],
        public erc20: Contracts["TestingERC20"],
        public bootstrapToken: Contracts["TestingERC20"],
        public staking: Contracts["StakingContract"],
        public delegations: Contracts["Delegations"],
        public subscriptions: Contracts["Subscriptions"],
        public rewards: Contracts["Rewards"],
        public protocol: Contracts["Protocol"],
        public certification: Contracts["Certification"],
        public guardiansRegistration: Contracts['GuardiansRegistration'],
        public committee: Contracts['Committee'],
        public stakingRewardsWallet: Contracts['ProtocolWallet'],
        public bootstrapRewardsWallet: Contracts['ProtocolWallet'],
        public generalFeesWallet: Contracts['FeesWallet'],
        public certifiedFeesWallet: Contracts['FeesWallet'],
        public contractRegistry: Contracts["ContractRegistry"]
    ) {}

    static async new(options: Partial<DriverOptions> = {}): Promise<Driver> {
        const { web3Provider, contractRegistryForExistingContractsAddress } = Object.assign({}, defaultDriverOptions, options);

        const web3 = Driver.web3DriversCache.get(web3Provider) || new Web3Driver(web3Provider);
        Driver.web3DriversCache.set(web3Provider, web3);
        const session = new Web3Session();
        const accounts = await web3.eth.getAccounts();

        if (contractRegistryForExistingContractsAddress) {
            return await this.withExistingContracts(web3, contractRegistryForExistingContractsAddress, session, accounts);
        } else {
            return await this.withFreshContracts(web3, accounts, session, options);
        }
    }

    private static async withFreshContracts(web3, accounts, session, options: Partial<DriverOptions> = {}) {
        const {
            maxCommitteeSize,
            minSelfStakePercentMille, voteOutThreshold, voteUnreadyTimeout, voteUnreadyThreshold,
            maxTimeBetweenRewardAssignments,
            generalCommitteeAnnualBootstrap,
            certificationCommitteeAnnualBootstrap,
            stakingRewardsAnnualRateInPercentMille,
            stakingRewardsAnnualCap,
            maxDelegatorsStakingRewardsPercentMille,

            stakingRewardsWalletRate,
            bootstrapRewardsWalletRate,

            subscriptionTier,
            subscriptionRate,

            genesisRefTimeDelay
        } = Object.assign({}, defaultDriverOptions, options);

        const contractRegistry = options.contractRegistryAddress ?
            await web3.getExisting('ContractRegistry', options.contractRegistryAddress, session)
            :
            await web3.deploy('ContractRegistry', [accounts[0]], null, session);

        const delegations = options.delegationsAddress ?
            await web3.getExisting('Delegations', options.delegationsAddress, session)
            :
            await web3.deploy("Delegations", [], null, session);

        const externalToken = options.bootstrapTokenAddress ?
            await web3.getExisting('TestingERC20', options.bootstrapTokenAddress, session)
            :
            await web3.deploy('TestingERC20', [], null, session);

        const erc20 = options.orbsTokenAddress ?
            await web3.getExisting('TestingERC20', options.orbsTokenAddress, session)
            :
            await web3.deploy('TestingERC20', [], null, session);

        const staking = options.stakingContractAddress ?
            await web3.getExisting('StakingContract', options.stakingContractAddress, session)
            :
            await Driver.newStakingContract(web3, delegations.address, erc20.address, session);

        const rewards = options.rewardsAddress ?
            await web3.getExisting('Rewards', options.rewardsAddress, session)
            :
            await web3.deploy('Rewards', [erc20.address, externalToken.address], null, session);

        const elections = options.electionsAddress ?
            await web3.getExisting('Elections', options.electionsAddress, session)
            :
            await web3.deploy("Elections", [minSelfStakePercentMille, voteUnreadyThreshold, voteUnreadyTimeout, voteOutThreshold], null, session);

        const subscriptions = options.subscriptionsAddress ?
            await web3.getExisting('Subscriptions', options.subscriptionsAddress, session)
            :
            await web3.deploy('Subscriptions', [erc20.address], null, session);

        const protocol = options.protocolAddress ?
            await web3.getExisting('Protocol', options.protocolAddress, session)
            :
            await web3.deploy('Protocol', [], null, session);

        const certification = options.certificationAddress ?
            await web3.getExisting('Certification', options.certificationAddress, session)
            :
            await web3.deploy('Certification', [], null, session);

        const committee = options.committeeAddress ?
            await web3.getExisting('Committee', options.committeeAddress, session)
            :
            await web3.deploy('Committee', [maxCommitteeSize, maxTimeBetweenRewardAssignments], null, session);

        const stakingRewardsWallet = options.stakingRewardsWalletAddress ?
            await web3.getExisting('ProtocolWallet', options.stakingRewardsWalletAddress, session)
            :
            await web3.deploy('ProtocolWallet', [erc20.address, rewards.address], null, session);

        const bootstrapRewardsWallet = options.bootstrapRewardsWalletAddress ?
            await web3.getExisting('ProtocolWallet', options.bootstrapRewardsWalletAddress, session)
            :
            await web3.deploy('ProtocolWallet', [externalToken.address, rewards.address], null, session);

        const guardiansRegistration = options.guardiansRegistrationAddress ?
            await web3.getExisting('GuardiansRegistration', options.guardiansRegistrationAddress, session)
            :
            await web3.deploy('GuardiansRegistration', [], null, session);

        const generalFeesWallet = options.generalFeesWalletAddress ?
            await web3.getExisting('FeesWallet', options.generalFeesWalletAddress, session)
            :
            await web3.deploy('FeesWallet', [erc20.address], null, session);

        const certifiedFeesWallet = options.certifiedFeesWalletAddress ?
            await web3.getExisting('FeesWallet', options.certifiedFeesWalletAddress, session)
            :
            await web3.deploy('FeesWallet', [erc20.address], null, session);

        await contractRegistry.set("staking", staking.address);
        await contractRegistry.set("rewards", rewards.address);
        await contractRegistry.set("delegations", delegations.address);
        await contractRegistry.set("elections", elections.address);
        await contractRegistry.set("subscriptions", subscriptions.address);
        await contractRegistry.set("protocol", protocol.address);
        await contractRegistry.set("certification", certification.address);
        await contractRegistry.set("guardiansRegistration", guardiansRegistration.address);
        await contractRegistry.set("committee", committee.address);
        await contractRegistry.set("stakingRewardsWallet", stakingRewardsWallet.address);
        await contractRegistry.set("bootstrapRewardsWallet", bootstrapRewardsWallet.address);
        await contractRegistry.set("generalFeesWallet", generalFeesWallet.address);
        await contractRegistry.set("certifiedFeesWallet", certifiedFeesWallet.address);
        await contractRegistry.set("_bootstrapToken", externalToken.address);
        await contractRegistry.set("_erc20", erc20.address);

        await protocol.setContractRegistry(contractRegistry.address);
        await delegations.setContractRegistry(contractRegistry.address);
        await elections.setContractRegistry(contractRegistry.address);
        await rewards.setContractRegistry(contractRegistry.address);
        await subscriptions.setContractRegistry(contractRegistry.address);
        await certification.setContractRegistry(contractRegistry.address);
        await guardiansRegistration.setContractRegistry(contractRegistry.address);
        await committee.setContractRegistry(contractRegistry.address);
        await generalFeesWallet.setContractRegistry(contractRegistry.address);
        await certifiedFeesWallet.setContractRegistry(contractRegistry.address);

        await protocol.createDeploymentSubset(DEPLOYMENT_SUBSET_MAIN, 1);

        await Promise.all([
            elections,
            delegations,
            subscriptions,
            rewards,
            protocol,
            certification,
            guardiansRegistration,
            committee,
            contractRegistry,
            stakingRewardsWallet,
            bootstrapRewardsWallet,
            generalFeesWallet,
            certifiedFeesWallet
        ].map(async (c: OwnedContract) => {
            await c.transferFunctionalOwnership(accounts[1], {from: accounts[0]});
            await c.claimFunctionalOwnership({from: accounts[1]})
        }));

        // TODO remove when setting in constructor
        await rewards.setMaxDelegatorsStakingRewards(maxDelegatorsStakingRewardsPercentMille, {from: accounts[1]});
        await rewards.setGeneralCommitteeAnnualBootstrap(generalCommitteeAnnualBootstrap, {from: accounts[1]});
        await rewards.setCertificationCommitteeAnnualBootstrap(certificationCommitteeAnnualBootstrap, {from: accounts[1]});
        await rewards.setAnnualStakingRewardsRate(stakingRewardsAnnualRateInPercentMille, stakingRewardsAnnualCap, {from: accounts[1]});

        await stakingRewardsWallet.setMaxAnnualRate(stakingRewardsWalletRate);
        await bootstrapRewardsWallet.setMaxAnnualRate(bootstrapRewardsWalletRate);

        if (genesisRefTimeDelay != null) {
            await subscriptions.setGenesisRefTimeDelay(genesisRefTimeDelay);
        }

        const d = new Driver(web3, session,
            accounts,
            elections,
            erc20,
            externalToken,
            staking,
            delegations,
            subscriptions,
            rewards,
            protocol,
            certification,
            guardiansRegistration,
            committee,
            stakingRewardsWallet,
            bootstrapRewardsWallet,
            generalFeesWallet,
            certifiedFeesWallet,
            contractRegistry
        );

        await d.newSubscriber(subscriptionTier, subscriptionRate);
        d.newParticipant("functionalOwner");

        return d;
    }

    private static async withExistingContracts(web3, preExistingContractRegistryAddress, session, accounts) {
        const contractRegistry = await web3.getExisting('ContractRegistry', preExistingContractRegistryAddress, session);

        const rewards = await web3.getExisting('Rewards', await contractRegistry.get('rewards'), session);
        const externalToken = await web3.getExisting('TestingERC20', await contractRegistry.get('_bootstrapToken'), session);
        const erc20 = await web3.getExisting('TestingERC20', await contractRegistry.get('_erc20'), session);
        const delegations = await web3.getExisting('Delegations', await contractRegistry.get('delegations'), session);
        const elections = await web3.getExisting('Elections', await contractRegistry.get('elections'), session);
        const staking = await web3.getExisting('StakingContract', await contractRegistry.get('staking'), session);
        const subscriptions = await web3.getExisting('Subscriptions', await contractRegistry.get('subscriptions'), session);
        const protocol = await web3.getExisting('Protocol', await contractRegistry.get('protocol'), session);
        const certification = await web3.getExisting('Certification', await contractRegistry.get('certification'), session);
        const committee = await web3.getExisting('Committee', await contractRegistry.get('committee'), session);
        const guardiansRegistration = await web3.getExisting('GuardiansRegistration', await contractRegistry.get('guardiansRegistration'), session);
        const stakingRewardsWallet = await web3.getExisting('ProtocolWallet', await contractRegistry.get('stakingRewardsWallet'), session);
        const bootstrapRewardsWallet = await web3.getExisting('ProtocolWallet', await contractRegistry.get('bootstrapRewardsWallet'), session);
        const generalFeesWallet = await web3.getExisting('FeesWallet', await contractRegistry.get('generalFeesWallet'), session);
        const certifiedFeesWallet = await web3.getExisting('FeesWallet', await contractRegistry.get('certifiedFeesWallet'), session);

        return new Driver(web3, session,
            accounts,
            elections,
            erc20,
            externalToken,
            staking,
            delegations,
            subscriptions,
            rewards,
            protocol,
            certification,
            guardiansRegistration,
            committee,
            stakingRewardsWallet,
            bootstrapRewardsWallet,
            generalFeesWallet,
            certifiedFeesWallet,
            contractRegistry
        );
    }

    async newStakingContract(delegationsAddr: string, erc20Addr: string): Promise<StakingContract> {
        return await Driver.newStakingContract(this.web3, delegationsAddr, erc20Addr, this.session);
    }

    static async newStakingContract(web3: Web3Driver, delegationsAddr: string, erc20Addr: string, session?: Web3Session): Promise<StakingContract> {
        const accounts = await web3.eth.getAccounts();
        const staking = await web3.deploy("StakingContract", [1 /* _cooldownPeriodInSec */, accounts[0] /* _migrationManager */, "0x0000000000000000000000000000000000000001" /* _emergencyManager */, erc20Addr /* _token */], null, session);
        await staking.setStakeChangeNotifier(delegationsAddr, {from: accounts[0]});
        return staking;
    }

    get contractsOwnerAddress() {
        return this.accounts[0];
    }

    get contractsNonOwnerAddress() {
        return this.accounts[2];
    }

    get migrationOwner(): Participant {
        return new Participant("migration-owner", "migration-owner-website", "migration-owner-contact", this.accounts[0], this.accounts[0], this);
    }

    get functionalOwner(): Participant {
        return new Participant("functional-owner", "functional-owner-website", "functional-owner-contact", this.accounts[1], this.accounts[1], this);
    }

    subscribers: any[] = [];

    async newSubscriber(tier: string, monthlyRate:number|BN): Promise<MonthlySubscriptionPlanContract> {
        const subscriber = await this.web3.deploy('MonthlySubscriptionPlan', [this.erc20.address, tier, monthlyRate], null, this.session);
        await subscriber.setContractRegistry(this.contractRegistry.address);
        await subscriber.transferFunctionalOwnership(this.functionalOwner.address);
        await subscriber.claimFunctionalOwnership({from: this.functionalOwner.address});
        await this.subscriptions.addSubscriber(subscriber.address, {from: this.functionalOwner.address});
        this.subscribers.push(subscriber);
        return subscriber;
    }

    newParticipant(name?: string): Participant { // consumes two addresses from accounts for each participant - ethereum address and an orbs address
        name = name || `Guardian${this.participants.length}`;
        const RESERVED_ACCOUNTS = 3;
        const v = new Participant(
            name,
            `${name}-website`,
            `${name}-contact`,
            this.accounts[RESERVED_ACCOUNTS + this.participants.length*2],
            this.accounts[RESERVED_ACCOUNTS + this.participants.length*2+1],
            this);
        this.participants.push(v);
        return v;
    }

    async newGuardian(stake: number|BN, certification: boolean, signalReadyToSync: boolean, signalReadyForCommittee: boolean): Promise<{v: Participant, r: TransactionReceipt}> {
        const v = await this.newParticipant();
        const r = await v.becomeGuardian(stake, certification, signalReadyToSync, signalReadyForCommittee);
        return {v, r}
    }

    async delegateMoreStake(amount:number|BN, delegatee: Participant) {
        const delegator = this.newParticipant();
        await delegator.stake(new BN(amount));
        return await delegator.delegate(delegatee);
    }

    logGasUsageSummary(scenarioName: string, participants?: Participant[]) {
        const logTitle = (t: string) => {
            console.log(t);
            console.log('-'.repeat(t.length));
        };
        logTitle(`GAS USAGE SUMMARY - SCENARIO "${scenarioName}":`);

        if (!participants) console.log(`Root Account (${this.accounts[0]}): ${this.session.gasRecorder.gasUsedBy(this.accounts[0])}`);
        if (!participants) console.log(`Accounts[1] (${this.accounts[1]}): ${this.session.gasRecorder.gasUsedBy(this.accounts[1])}`);
        if (!participants) console.log(`Accounts[2] (${this.accounts[2]}): ${this.session.gasRecorder.gasUsedBy(this.accounts[2])}`);
        for (const p of (participants || this.participants)) {
            console.log(`${p.name} (${p.address};${p.orbsAddress}): ${p.gasUsed()}`);
        }
    }

    resetGasRecording() {
        this.session.gasRecorder.reset();
    }
}

export class Participant {
    // TODO Consider implementing guardian methods in a child class.
    public ip: string;
    private driver: Driver;

    constructor(public name: string,
                public website: string,
                public contact: string,
                public address: string,
                public orbsAddress: string,
                driver: Driver) {
        this.name = name;
        this.ip = address.substring(0, 10).toLowerCase(); // random IP using the 4 first bytes from address string TODO simplify
        this.driver = driver;
    }

    async stake(amount: number|BN, staking?: StakingContract) : Promise<TransactionReceipt> {
        staking = staking || this.driver.staking;
        await this.assignAndApproveOrbs(amount, staking.address);
        return staking.stake(amount, {from: this.address});
    }

    private async assignAndApprove(amount: number|BN, to: string, token: ERC20Contract) {
        await token.assign(this.address, amount);
        await token.approve(to, amount, {from: this.address});
    }

    async assignAndApproveOrbs(amount: number|BN, to: string) {
        return this.assignAndApprove(amount, to, this.driver.erc20);
    }

    async assignAndApproveExternalToken(amount: number|BN, to: string) {
        return this.assignAndApprove(amount, to, this.driver.bootstrapToken);
    }

    async unstake(amount: number|BN) {
        return this.driver.staking.unstake(amount, {from: this.address});
    }

    async restake() {
        return this.driver.staking.restake({from: this.address});
    }

    async delegate(to: Participant) {
        return this.driver.delegations.delegate(to.address, {from: this.address});
    }

    async registerAsGuardian() {
        return await this.driver.guardiansRegistration.registerGuardian(this.ip, this.orbsAddress, this.name, this.website, this.contact, {from: this.address});
    }

    async readyForCommittee() {
        return await this.driver.elections.readyForCommittee({from: this.orbsAddress});
    }

    async readyToSync() {
        return await this.driver.elections.readyToSync({from: this.orbsAddress});
    }

    async becomeCertified() {
        return await this.driver.certification.setGuardianCertification(this.address, true, {from: this.driver.functionalOwner.address});
    }

    async becomeNotCertified() {
        return await this.driver.certification.setGuardianCertification(this.address, false, {from: this.driver.functionalOwner.address});
    }

    async becomeGuardian(stake: number|BN, certified: boolean, signalReadyToSync: boolean, signalReadyForCommittee: boolean): Promise<TransactionReceipt> {
        let r = await this.registerAsGuardian();
        if (certified) {
            r = await this.becomeCertified();
        }
        if (bn(stake).gt(bn(0))) {
            r = await this.stake(stake);
        }
        if (signalReadyToSync) {
            r = await this.readyToSync();
        }
        if (signalReadyForCommittee) {
            r = await this.readyForCommittee();
        }
        return r;
    }

    async unregisterAsGuardian() {
        return await this.driver.guardiansRegistration.unregisterGuardian({from: this.address});
    }

    gasUsed(): number {
        return this.driver.session.gasRecorder.gasUsedBy(this.address) + this.driver.session.gasRecorder.gasUsedBy(this.orbsAddress);
    }

}
