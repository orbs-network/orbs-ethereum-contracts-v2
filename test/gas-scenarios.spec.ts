import 'mocha';
import Web3 from "web3";
import BN from "bn.js";
import * as _ from "lodash";
import {
    CONFORMANCE_TYPE_COMPLIANCE,
    CONFORMANCE_TYPE_GENERAL,
    defaultDriverOptions,
    Driver,
    Participant
} from "./driver";
import chai from "chai";
import {createVC} from "./consumer-macros";
import {bn, evmIncreaseTime} from "./helpers";

declare const web3: Web3;

chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const expect = chai.expect;
const assert = chai.assert;

const BASE_STAKE = 1000000;
const MAX_COMMITTEE = 22;
const MAX_STANDBYS = 5;

async function fullCommitteeAndStandbys(committeeEvenStakes:boolean = false, standbysEvenStakes:boolean = false, numVCs=5): Promise<{d: Driver, committee: Participant[], standbys: Participant[]}> {
    const d = await Driver.new({maxCommitteeSize: MAX_COMMITTEE, maxStandbys: MAX_STANDBYS, maxDelegationRatio: 255});

    const poolAmount = new BN(1000000000);
    await d.erc20.assign(d.accounts[0], poolAmount);
    await d.erc20.approve(d.stakingRewards.address, poolAmount);
    await d.stakingRewards.setAnnualRate(12000, poolAmount);
    await d.stakingRewards.topUpPool(poolAmount);

    const committee: Participant[] = [];
    const standbys: Participant[] = [];

    for (let i = 0; i < MAX_COMMITTEE; i++) {
        const {v, r} = await d.newValidator(BASE_STAKE + 1 + (committeeEvenStakes ? 0 : MAX_COMMITTEE - i - 1), true, false, true);
        committee.push(v);
        expect(r).to.have.withinContract(d.committeeGeneral).a.committeeChangedEvent({
            addrs: committee.map(v => v.address)
        });
        expect(r).to.have.withinContract(d.committeeCompliance).a.committeeChangedEvent({
            addrs: committee.map(v => v.address)
        });
    }

    for (let i = 0; i < MAX_STANDBYS; i++) {
        const {v, r} = await d.newValidator(BASE_STAKE - (standbysEvenStakes ? 0 : i), true, false, true);
        standbys.push(v);
        expect(r).to.have.withinContract(d.committeeGeneral).a.standbysChangedEvent({
            addrs: standbys.map(v => v.address)
        });
        expect(r).to.have.withinContract(d.committeeCompliance).a.standbysChangedEvent({
            addrs: standbys.map(v => v.address)
        });
    }

    const monthlyRate = 1000;
    const subs = await d.newSubscriber('defaultTier', monthlyRate);
    const appOwner = d.newParticipant();

    for (let i = 0; i < numVCs; i++) {
        await createVC(d, CONFORMANCE_TYPE_GENERAL, subs, monthlyRate, appOwner);
        await createVC(d, CONFORMANCE_TYPE_COMPLIANCE, subs, monthlyRate, appOwner);
    }

    return {
        d,
        committee,
        standbys
    }
}


describe('gas usage scenarios', async () => {
    it("New delegator stake increase, lowest committee member gets to top", async () => {
        const {d, committee} = await fullCommitteeAndStandbys();

        const delegator = d.newParticipant("delegator");
        await delegator.delegate(committee[committee.length - 1]);

        d.resetGasRecording();
        let r = await delegator.stake(BASE_STAKE * 1000);
        expect(r).to.have.a.committeeChangedEvent({
            addrs: committee.map(v => v.address)
        });

        d.logGasUsageSummary("New delegator stake increase, lowest committee member gets to top", [delegator]);
    });

    it("Delegation change, top of committee and bottom standby switch places", async () => {
        const {d, committee, standbys} = await fullCommitteeAndStandbys();

        const delegator = d.newParticipant("delegator");
        await delegator.delegate(committee[0]);
        let r = await delegator.stake(1000 * BASE_STAKE);
        expect(r).to.have.a.committeeChangedEvent({
            addrs: committee.map(v => v.address)
        });

        await committee[0].unstake(BASE_STAKE + committee.length);
        r = await committee[0].stake(BASE_STAKE - standbys.length - 1);
        expect(r).to.have.a.committeeChangedEvent({
            addrs: committee.map(v => v.address)
        });

        d.resetGasRecording();
        r = await delegator.delegate(standbys[standbys.length - 1]);
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [standbys[standbys.length - 1]].concat(committee.slice(1)).map(v => v.address)
        });
        expect(r).to.have.a.standbysChangedEvent({
            addrs: standbys.slice(0, standbys.length - 1).concat([committee[0]]).map(v => v.address)
        });

        d.logGasUsageSummary("Delegation change, top of committee and bottom standby switch places", [delegator]);
    });

    it("New delegator stakes", async () => {
        const {d} = await fullCommitteeAndStandbys();

        const delegator = d.newParticipant("delegator");

        d.resetGasRecording();
        let r = await delegator.stake(1);
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.not.have.a.standbysChangedEvent();

        d.logGasUsageSummary("New delegator stakes", [delegator]);
    });

    it("Delegator stake increase, no change in committee order", async () => {
        const {d, committee} = await fullCommitteeAndStandbys();

        const delegator = d.newParticipant("delegator");
        await delegator.delegate(committee[0]);

        d.resetGasRecording();
        let r = await delegator.stake(1);
        expect(r).to.have.a.committeeChangedEvent({
            addrs: committee.map(v => v.address)
        });
        expect(r).to.not.have.a.standbysChangedEvent();

        d.logGasUsageSummary("Delegator stake increase, no change in committee order", [delegator]);
    });

    it("Standby sends ready-to-sync for first time and gets to top of standbys list", async () => {
        const {d, standbys} = await fullCommitteeAndStandbys();

        const {v} = await d.newValidator(BASE_STAKE + 1, true, false, false);

        d.resetGasRecording();
        let r = await v.notifyReadyToSync();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v].concat(standbys.slice(0, standbys.length - 1)).map(v => v.address)
        });
        expect(r).to.not.have.a.committeeChangedEvent();

        d.logGasUsageSummary("Standby sends ready-to-sync for first time and gets to top of standbys list", [v]);
    });

    it("Standby sends ready-to-sync for second time", async () => {
        const {d, standbys} = await fullCommitteeAndStandbys();

        const {v} = await d.newValidator(BASE_STAKE + 1, true, false, false);

        let r = await v.notifyReadyToSync();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v].concat(standbys.slice(0, standbys.length - 1)).map(v => v.address)
        });
        expect(r).to.not.have.a.committeeChangedEvent();

        d.resetGasRecording();
        await v.notifyReadyToSync();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v].concat(standbys.slice(0, standbys.length - 1)).map(v => v.address)
        });
        expect(r).to.not.have.a.committeeChangedEvent();

        d.logGasUsageSummary("Delegator stake increase, no change in committee order", [v]);
    });

    it("New validator sends ready-for-committee and immediately gets to top", async () => {
        const {d, committee, standbys} = await fullCommitteeAndStandbys();

        const {v} = await d.newValidator(BASE_STAKE + committee.length + 1, true, false, false);

        d.resetGasRecording();
        let r = await v.notifyReadyForCommittee();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [committee[committee.length - 1]].concat(standbys.slice(0, standbys.length - 1)).map(v => v.address)
        });
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [v].concat(committee.slice(0, committee.length - 1)).map(v => v.address)
        });

        d.logGasUsageSummary("Delegator stake increase, no change in committee order", [v]);
    });

    it("Standby sends ready-for-committee and jumps to top of committee", async () => {
        const {d, committee, standbys} = await fullCommitteeAndStandbys();

        const {v} = await d.newValidator(BASE_STAKE + committee.length + 1, true, false, false);

        let r = await v.notifyReadyToSync();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v].concat(standbys.slice(0, standbys.length - 1)).map(v => v.address)
        });
        expect(r).to.not.have.a.committeeChangedEvent();

        d.resetGasRecording();
        r = await v.notifyReadyForCommittee();
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [v].concat(committee.slice(0, committee.length - 1)).map(v => v.address)
        });
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [committee[committee.length - 1]].concat(standbys.slice(0, standbys.length - 1)).map(v => v.address)
        });

        d.logGasUsageSummary("Standby sends ready-for-committee and jumps to top of committee", [v]);
    });

    it("Top committee member unregisters, a standby enters the committee", async () => {
        const {d, committee, standbys} = await fullCommitteeAndStandbys();

        d.resetGasRecording();
        let r = await committee[0].unregisterAsValidator();
        expect(r).to.have.a.committeeChangedEvent({
            addrs: committee.slice(1).concat([standbys[0]]).map(v => v.address)
        });
        expect(r).to.have.a.standbysChangedEvent({
            addrs: standbys.slice(1).map(v => v.address)
        });

        d.logGasUsageSummary("Top committee member unregisters, a standby enters the committee", [committee[0]]);
    });

    it("Auto-voteout is cast, threshold not reached", async () => {
        const {d, committee} = await fullCommitteeAndStandbys();

        d.resetGasRecording();
        let r = await d.elections.voteOut(committee[1].address, {from: committee[0].orbsAddress});
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.not.have.a.standbysChangedEvent();
        expect(r).to.have.a.voteOutEvent({
            voter: committee[0].address,
            against: committee[1].address
        });
        d.logGasUsageSummary("Auto-voteout is cast, threshold not reached", [committee[0]]);
    });

    it("Auto-voteout is cast, threshold is reached and top committee member leaves", async () => {
        const {d, committee, standbys} = await fullCommitteeAndStandbys(true);

        const voters = committee.slice(0, Math.floor(MAX_COMMITTEE * defaultDriverOptions.voteOutThreshold / 100));
        await Promise.all(
            voters.map(v => d.elections.voteOut(committee[0].address, {from: v.orbsAddress}))
        );

        d.resetGasRecording();

        const thresholdVoter = committee[voters.length];
        let r = await d.elections.voteOut(committee[0].address, {from: thresholdVoter.orbsAddress});
        expect(r).to.have.a.voteOutEvent({
            voter: thresholdVoter.address,
            against: committee[0].address
        });
        expect(r).to.have.a.votedOutOfCommitteeEvent({
            addr: committee[0].address
        });

        expect(r).to.have.a.committeeChangedEvent({
            addrs: committee.slice(1).concat([standbys[0]]).map(v => v.address)
        });
        expect(r).to.have.a.standbysChangedEvent({
            addrs: standbys.slice(1).map(v => v.address)
        });

        d.logGasUsageSummary("Auto-voteout is cast, threshold is reached and top committee member leaves", [thresholdVoter]);
    });

    it("Manual-voteout is cast, threshold not reached", async () => {
        const {d, committee} = await fullCommitteeAndStandbys();

        d.resetGasRecording();
        let r = await d.elections.setBanningVotes([committee[1].address], {from: committee[0].address});
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.not.have.a.standbysChangedEvent();
        expect(r).to.have.a.banningVoteEvent({
            voter: committee[0].address,
            against: [committee[1].address]
        });
        d.logGasUsageSummary("Manual-voteout is cast, threshold not reached", [committee[0]]);
    });

    it("Manual-voteout is cast, threshold is reached and top committee member leaves", async () => {
        const {d, committee, standbys} = await fullCommitteeAndStandbys(true);

        const voters = committee.slice(0, Math.floor((MAX_COMMITTEE + MAX_STANDBYS) * defaultDriverOptions.voteOutThreshold / 100));
        await Promise.all(
            voters.map(v => d.elections.setBanningVotes([committee[0].address], {from: v.address}))
        );

        d.resetGasRecording();

        const thresholdVoter = committee[voters.length];
        let r = await d.elections.setBanningVotes([committee[0].address], {from: thresholdVoter.address});
        expect(r).to.have.a.banningVoteEvent({
            voter: thresholdVoter.address,
            against: [committee[0].address]
        });
        expect(r).to.have.a.bannedEvent({
            validator: committee[0].address
        });
        expect(r).to.have.a.committeeChangedEvent({
            addrs: committee.slice(1).concat([standbys[0]]).map(v => v.address)
        });
        expect(r).to.have.a.standbysChangedEvent({
            addrs: standbys.slice(1).map(v => v.address)
        });

        d.logGasUsageSummary("Manual-voteout is cast, threshold is reached and top committee member leaves", [thresholdVoter]);
    });

    const distributeRewardsScenario = async (batchSize: number) => {
        const {d, committee, standbys} = await fullCommitteeAndStandbys(true);

        await evmIncreaseTime(d.web3, 30*24*60*60);
        await d.stakingRewards.assignRewards();

        const v = committee[0];

        const delegator = d.newParticipant();
        await delegator.stake(100);
        await delegator.delegate(v);

        const delegators: Participant[] = await Promise.all(_.range(batchSize).map(async () => {
            const delegator = d.newParticipant();
            await delegator.stake(100);
            await delegator.delegate(v);
            return delegator;
        }));

        const balance = bn(await d.stakingRewards.getRewardBalance(v.address));

        d.resetGasRecording();
        await d.stakingRewards.distributeOrbsTokenRewards(
            delegators.map(delegator => delegator.address),
            delegators.map(() => balance.div(bn(batchSize)))
            , {from: committee[0].address});
        d.logGasUsageSummary(`Distribute rewards - all delegators delegated to same validator (batch size - ${batchSize})`, [committee[0]]);
    };

    it("Distribute rewards - all delegators delegated to same validator (batch size - 1)", async () => {
        await distributeRewardsScenario(1)
    });

    it("Distribute rewards - all delegators delegated to same validator (batch size - 20)", async () => {
        await distributeRewardsScenario(20)
    });

    it("Distribute rewards - all delegators delegated to same validator (batch size - 50)", async () => {
        await distributeRewardsScenario(50)
    });

    it("assigns rewards (1 month, initial balance == 0)", async () => {
        const {d, committee, standbys} = await fullCommitteeAndStandbys(false, false, 100);
        await evmIncreaseTime(d.web3, 30*24*60*60);

        const p = d.newParticipant("reward assigner");
        d.resetGasRecording();
        await d.stakingRewards.assignRewards({from: p.address});
        await d.bootstrapRewards.assignRewards({from: p.address});
        await d.fees.assignFees({from: p.address});

        d.logGasUsageSummary("assigns rewards (1 month, initial balance == 0)", [p]);
    });

    it("assigns rewards (1 month, initial balance > 0)", async () => {
        const {d, committee, standbys} = await fullCommitteeAndStandbys(false, false, 100);
        await evmIncreaseTime(d.web3, 30*24*60*60);

        await d.stakingRewards.assignRewards();
        await d.bootstrapRewards.assignRewards();
        await d.fees.assignFees();

        await evmIncreaseTime(d.web3, 30*24*60*60);

        const p = d.newParticipant("reward assigner");
        d.resetGasRecording();
        await d.stakingRewards.assignRewards({from: p.address});
        await d.bootstrapRewards.assignRewards({from: p.address});
        await d.fees.assignFees({from: p.address});

        d.logGasUsageSummary("assigns rewards (1 month, initial balance > 0)", [p]);
    });


});
