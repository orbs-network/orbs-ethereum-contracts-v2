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
    maxDelegationRatio: number;
    maxTimeBetweenRewardAssignments: number;
    voteOutThreshold: number;
    voteOutTimeout: number;
    banningThreshold: number;
    web3Provider : () => Web3;
    contractRegistryAddress?: string;
}
export const defaultDriverOptions: Readonly<DriverOptions> = {
    maxCommitteeSize: 2,
    maxDelegationRatio : 10,
    maxTimeBetweenRewardAssignments: 0,
    voteOutThreshold : 80,
    voteOutTimeout : 24 * 60 * 60,
    banningThreshold : 80,
    web3Provider: defaultWeb3Provider,
};

export type ContractName = 'protocol' | 'committee' | 'elections' | 'delegations' | 'guardiansRegistration' | 'certification' | 'staking' | 'subscriptions' | 'rewards' | 'stakingRewardsWallet';

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
        public guardiansWallet: Contracts['GuardiansWallet'],
        public contractRegistry: Contracts["ContractRegistry"]
    ) {}

    static async new(options: Partial<DriverOptions> = {}): Promise<Driver> {
        const { web3Provider, contractRegistryAddress } = Object.assign({}, defaultDriverOptions, options);

        const web3 = Driver.web3DriversCache.get(web3Provider) || new Web3Driver(web3Provider);
        Driver.web3DriversCache.set(web3Provider, web3);
        const session = new Web3Session();
        const accounts = await web3.eth.getAccounts();

        if (contractRegistryAddress) {
            return await this.withExistingContracts(web3, contractRegistryAddress, session, accounts);
        } else {
            return await this.withFreshContracts(web3, accounts, session, options);
        }
    }

    private static async withFreshContracts(web3, accounts, session, options: Partial<DriverOptions> = {}) {
        const {
            maxCommitteeSize,
            maxDelegationRatio, voteOutThreshold, voteOutTimeout, banningThreshold,
            maxTimeBetweenRewardAssignments
        } = Object.assign({}, defaultDriverOptions, options);
        const contractRegistry = await web3.deploy('ContractRegistry', [accounts[0]], null, session);
        const externalToken = await web3.deploy('TestingERC20', [], null, session);
        const erc20 = await web3.deploy('TestingERC20', [], null, session);
        const rewards = await web3.deploy('Rewards', [erc20.address, externalToken.address], null, session);
        const delegations = await web3.deploy("Delegations", [], null, session);
        const elections = await web3.deploy("Elections", [maxDelegationRatio, voteOutThreshold, voteOutTimeout, banningThreshold], null, session);
        const staking = await Driver.newStakingContract(web3, delegations.address, erc20.address, session);
        const subscriptions = await web3.deploy('Subscriptions', [erc20.address], null, session);
        const protocol = await web3.deploy('Protocol', [], null, session);
        const certification = await web3.deploy('Certification', [], null, session);
        const committee = await web3.deploy('Committee', [maxCommitteeSize, maxTimeBetweenRewardAssignments], null, session);
        const stakingRewardsWallet = await web3.deploy('ProtocolWallet', [erc20.address, rewards.address], null, session);
        const bootstrapRewardsWallet = await web3.deploy('ProtocolWallet', [externalToken.address, rewards.address], null, session);
        const guardiansRegistration = await web3.deploy('GuardiansRegistration', [], null, session);
        const guardiansWallet = await web3.deploy('GuardiansWallet', [erc20.address, erc20.address, externalToken.address, 100000], null, session);

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
        await contractRegistry.set("guardiansWallet", guardiansWallet.address);
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
        await guardiansWallet.setContractRegistry(contractRegistry.address);

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
            guardiansWallet
        ].map(async (c: OwnedContract) => {
            await c.transferFunctionalOwnership(accounts[1], {from: accounts[0]});
            await c.claimFunctionalOwnership({from: accounts[1]})
        }));

        await stakingRewardsWallet.setMaxAnnualRate(bn(2).pow(bn(94)).sub(bn(1)));
        await bootstrapRewardsWallet.setMaxAnnualRate(bn(2).pow(bn(94)).sub(bn(1)));

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
            guardiansWallet,
            contractRegistry
        );
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
        const guardiansWallet = await web3.getExisting('GuardiansWallet', await contractRegistry.get('guardiansWallet'), session);

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
            guardiansWallet,
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

    async newSubscriber(tier: string, monthlyRate:number|BN): Promise<MonthlySubscriptionPlanContract> {
        const subscriber = await this.web3.deploy('MonthlySubscriptionPlan', [this.erc20.address, tier, monthlyRate], null, this.session);
        await subscriber.setContractRegistry(this.contractRegistry.address);
        await subscriber.transferFunctionalOwnership(this.functionalOwner.address);
        await subscriber.claimFunctionalOwnership({from: this.functionalOwner.address});
        await this.subscriptions.addSubscriber(subscriber.address, {from: this.functionalOwner.address});
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
        await this.registerAsGuardian();
        if (certified) {
            await this.becomeCertified();
        }
        let r = await this.stake(stake);
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

export async function expectRejected(promise: Promise<any>, msg?: string) {
    try {
        await promise;
    } catch (err) {
        // TODO verify correct error
        return
    }
    throw new Error(msg || "expected promise to reject")
}

