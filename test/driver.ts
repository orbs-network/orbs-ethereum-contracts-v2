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
import {ValidatorsRegistrationContract} from "../typings/validator-registration-contract";
import {ComplianceContract} from "../typings/compliance-contract";
import {TransactionReceipt} from "web3-core";
import {GasRecorder} from "../gas-recorder";
import {stakedEvents} from "./event-parsing";

export const BANNING_LOCK_TIMEOUT = 7*24*60*60;
export const DEPLOYMENT_SUBSET_MAIN = "main";
export const DEPLOYMENT_SUBSET_CANARY = "canary";

export type DriverOptions = {
    minCommitteeSize: number,
    maxCommitteeSize: number;
    generalCommitteeMinimumWeight: number,
    maxStandbys: number;
    maxDelegationRatio: number;
    voteOutThreshold: number;
    voteOutTimeout: number;
    readyToSyncTimeout: number;
    banningThreshold: number;
    web3Provider : () => Web3;
}
export const defaultDriverOptions: Readonly<DriverOptions> = {
    minCommitteeSize: 0,
    maxCommitteeSize: 2,
    generalCommitteeMinimumWeight: 0,
    maxStandbys : 2,
    maxDelegationRatio : 10,
    voteOutThreshold : 80,
    voteOutTimeout : 24 * 60 * 60,
    readyToSyncTimeout: 7*24*60*60,
    banningThreshold : 80,
    web3Provider: defaultWeb3Provider,
};

export class Driver {
    private static web3DriversCache = new WeakMap<DriverOptions['web3Provider'], Web3Driver>();
    private participants: Participant[] = [];

    constructor(
        public web3: Web3Driver,
        public session: Web3Session,
        public accounts: string[],
        public elections: Contracts["Elections"],
        public erc20: Contracts["TestingERC20"],
        public externalToken: Contracts["TestingERC20"],
        public staking: Contracts["StakingContract"],
        public delegations: Contracts["Delegations"],
        public subscriptions: Contracts["Subscriptions"],
        public bootstrapRewards: Contracts["BootstrapRewards"],
        public stakingRewards: Contracts["StakingRewards"],
        public fees: Contracts["Fees"],
        public rewards: Contracts["Rewards"],
        public protocol: Contracts["Protocol"],
        public compliance: Contracts["Compliance"],
        public validatorsRegistration: Contracts['ValidatorsRegistration'],
        public committeeGeneral: Contracts['Committee'],
        public committeeCompliance: Contracts['Committee'],
        public contractRegistry: Contracts["ContractRegistry"],
    ) {}

    static async new(options: Partial<DriverOptions> = {}): Promise<Driver> {
        const {
            minCommitteeSize, maxCommitteeSize, generalCommitteeMinimumWeight, maxStandbys,
            maxDelegationRatio, voteOutThreshold, voteOutTimeout, banningThreshold, web3Provider,
            readyToSyncTimeout
        } = Object.assign({}, defaultDriverOptions, options);
        const web3 = Driver.web3DriversCache.get(web3Provider) || new Web3Driver(web3Provider);
        Driver.web3DriversCache.set(web3Provider, web3);
        const session = new Web3Session();
        const accounts = await web3.eth.getAccounts();

        const contractRegistry = await web3.deploy( 'ContractRegistry',[accounts[0]], null, session);
        const externalToken = await web3.deploy( 'TestingERC20', [], null, session);
        const erc20 = await web3.deploy( 'TestingERC20', [], null, session);
        const bootstrapRewards = await web3.deploy( 'BootstrapRewards', [externalToken.address, accounts[0]], null, session);
        const stakingRewards = await web3.deploy( 'StakingRewards', [erc20.address, accounts[0]], null, session);
        const fees = await web3.deploy( 'Fees', [erc20.address], null, session);
        const rewards = await web3.deploy( 'Rewards', [erc20.address, externalToken.address, accounts[0]], null, session);
        const delegations = await web3.deploy( "Delegations", [], null, session);
        const elections = await web3.deploy( "Elections", [minCommitteeSize, maxDelegationRatio, voteOutThreshold, voteOutTimeout, banningThreshold], null, session);
        const staking = await Driver.newStakingContract(web3, delegations.address, erc20.address, session);
        const subscriptions = await web3.deploy( 'Subscriptions', [erc20.address] , null, session);
        const protocol = await web3.deploy('Protocol', [], null, session);
        const compliance = await web3.deploy('Compliance', [], null, session);
        const committeeGeneral = await web3.deploy('Committee', [minCommitteeSize, maxCommitteeSize, generalCommitteeMinimumWeight, maxStandbys, readyToSyncTimeout], null, session);
        const committeeCompliance = await web3.deploy('Committee', [minCommitteeSize, maxCommitteeSize, 0, maxStandbys, readyToSyncTimeout], null, session);
        const validatorsRegistration = await web3.deploy('ValidatorsRegistration', [], null, session);

        await contractRegistry.set("staking", staking.address);
        // await contractRegistry.set("bootstrapRewards", bootstrapRewards.address);
        // await contractRegistry.set("stakingRewards", stakingRewards.address);
        // await contractRegistry.set("fees", fees.address);
        await contractRegistry.set("rewards", rewards.address);
        await contractRegistry.set("delegations", delegations.address);
        await contractRegistry.set("elections", elections.address);
        await contractRegistry.set("subscriptions", subscriptions.address);
        await contractRegistry.set("protocol", protocol.address);
        await contractRegistry.set("compliance", compliance.address);
        await contractRegistry.set("validatorsRegistration", validatorsRegistration.address);
        await contractRegistry.set("committee-general", committeeGeneral.address);
        await contractRegistry.set("committee-compliance", committeeCompliance.address);

        await delegations.setContractRegistry(contractRegistry.address);
        await elections.setContractRegistry(contractRegistry.address);
        await bootstrapRewards.setContractRegistry(contractRegistry.address);
        await rewards.setContractRegistry(contractRegistry.address);
        await stakingRewards.setContractRegistry(contractRegistry.address);
        await fees.setContractRegistry(contractRegistry.address);
        await subscriptions.setContractRegistry(contractRegistry.address);
        await compliance.setContractRegistry(contractRegistry.address);
        await validatorsRegistration.setContractRegistry(contractRegistry.address);
        await committeeGeneral.setContractRegistry(contractRegistry.address);
        await committeeCompliance.setContractRegistry(contractRegistry.address);

        await protocol.createDeploymentSubset(DEPLOYMENT_SUBSET_MAIN, 1);

        return new Driver(web3, session,
            accounts,
            elections,
            erc20,
            externalToken,
            staking,
            delegations,
            subscriptions,
            bootstrapRewards,
            stakingRewards,
            fees,
            rewards,
            protocol,
            compliance,
            validatorsRegistration,
            committeeGeneral,
            committeeCompliance,
            contractRegistry
        );
    }

    async newContractRegistry(governorAddr: string): Promise<ContractRegistryContract> {
        return await this.web3.deploy('ContractRegistry', [governorAddr],{from: this.accounts[0]}, this.session) as ContractRegistryContract;
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

    get contractsOwner() {
        return this.accounts[0];
    }

    get contractsNonOwner() {
        return this.accounts[1];
    }

    get rewardsGovernor(): Participant {
        return new Participant("rewards-governor", "rewards-governor-website", "rewards-governor-contact", this.accounts[0], this.accounts[0], this);
    }

    async newSubscriber(tier: string, monthlyRate:number|BN): Promise<MonthlySubscriptionPlanContract> {
        const subscriber = await this.web3.deploy('MonthlySubscriptionPlan', [this.erc20.address, tier, monthlyRate], null, this.session);
        await subscriber.setContractRegistry(this.contractRegistry.address);
        await this.subscriptions.addSubscriber(subscriber.address);
        return subscriber;
    }

    newParticipant(name?: string): Participant { // consumes two addresses from accounts for each participant - ethereum address and an orbs address
        name = name || `Validator${this.participants.length}`;
        const RESERVED_ACCOUNTS = 2;
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

    async newValidator(stake: number, compliance: boolean, signalReadyToSync: boolean, signalReadyForCommittee: boolean): Promise<{v: Participant, r: TransactionReceipt}> {
        const v = await this.newParticipant();
        const r = await v.becomeValidator(stake, compliance, signalReadyToSync, signalReadyForCommittee);
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
    // TODO Consider implementing validator methods in a child class.
    public ip: string;
    private erc20: ERC20Contract;
    private externalToken: ERC20Contract;
    private staking: StakingContract;
    private elections: ElectionsContract;
    private delegations: DelegationsContract;
    private validatorsRegistration: ValidatorsRegistrationContract;
    private compliance: ComplianceContract;
    private gasRecorder: GasRecorder;

    constructor(public name: string,
                public website: string,
                public contact: string,
                public address: string,
                public orbsAddress: string,
                driver: Driver) {
        this.name = name;
        this.ip = address.substring(0, 10).toLowerCase(); // random IP using the 4 first bytes from address string TODO simplify
        this.erc20 = driver.erc20;
        this.externalToken = driver.externalToken;
        this.staking = driver.staking;
        this.elections = driver.elections;
        this.delegations = driver.delegations;
        this.validatorsRegistration = driver.validatorsRegistration;
        this.compliance = driver.compliance;
        this.gasRecorder = driver.session.gasRecorder;
    }

    async stake(amount: number|BN, staking?: StakingContract) {
        staking = staking || this.staking;
        await this.assignAndApproveOrbs(amount, staking.address);
        return staking.stake(amount, {from: this.address});
    }

    private async assignAndApprove(amount: number|BN, to: string, token: ERC20Contract) {
        await token.assign(this.address, amount);
        await token.approve(to, amount, {from: this.address});
    }

    async assignAndApproveOrbs(amount: number|BN, to: string) {
        return this.assignAndApprove(amount, to, this.erc20);
    }

    async assignAndApproveExternalToken(amount: number|BN, to: string) {
        return this.assignAndApprove(amount, to, this.externalToken);
    }

    async unstake(amount: number|BN) {
        return this.staking.unstake(amount, {from: this.address});
    }

    async delegate(to: Participant) {
        return this.delegations.delegate(to.address, {from: this.address});
    }

    async registerAsValidator() {
        return await this.validatorsRegistration.registerValidator(this.ip, this.orbsAddress, this.name, this.website, this.contact, {from: this.address});
    }

    async notifyReadyForCommittee() {
        return await this.elections.notifyReadyForCommittee({from: this.orbsAddress});
    }

    async notifyReadyToSync() {
        return await this.elections.notifyReadyToSync({from: this.orbsAddress});
    }

    async becomeCompliant() {
        return await this.compliance.setValidatorCompliance(this.address, true);
    }

    async becomeNotCompliant() {
        return await this.compliance.setValidatorCompliance(this.address, false);
    }

    async becomeValidator(stake: number, compliant: boolean, signalReadyToSync: boolean, signalReadyForCommittee: boolean): Promise<TransactionReceipt> {
        await this.registerAsValidator();
        if (compliant) {
            await this.becomeCompliant();
        }
        let r = await this.stake(stake);
        if (signalReadyToSync) {
            r = await this.notifyReadyToSync();
        }
        if (signalReadyForCommittee) {
            r = await this.notifyReadyForCommittee();
        }
        return r;
    }

    async unregisterAsValidator() {
        return await this.validatorsRegistration.unregisterValidator({from: this.address});
    }

    gasUsed(): number {
        return this.gasRecorder.gasUsedBy(this.address) + this.gasRecorder.gasUsedBy(this.orbsAddress);
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

