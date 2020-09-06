import 'mocha';
import Web3 from "web3";
import BN from "bn.js";
import * as _ from "lodash";
import {
    defaultDriverOptions,
    Driver,
    Participant
} from "./driver";
import chai from "chai";
import {createVC} from "./consumer-macros";
import {bn, evmIncreaseTime, fromTokenUnits, toTokenUnits} from "./helpers";
import {feesAssignedEvents, gasReportEvents} from "./event-parsing";

declare const web3: Web3;

chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const expect = chai.expect;
const assert = chai.assert;

const BASE_STAKE = fromTokenUnits(1000000);
const MAX_COMMITTEE = 22;

const t0 = Date.now();
const tlog = (s) => console.log(Math.floor(Date.now()/1000 - t0/1000), s);

async function fullCommittee(committeeEvenStakes:boolean = false, numVCs=5): Promise<{d: Driver, committee: Participant[]}> {
    tlog("Creating driver..");
    const d = await Driver.new({maxCommitteeSize: MAX_COMMITTEE, minSelfStakePercentMille: 0});
    tlog("Driver created");

    const g = d.newParticipant();
    const poolAmount = fromTokenUnits(1000000);
    await g.assignAndApproveOrbs(poolAmount, d.stakingRewardsWallet.address);
    await d.stakingRewardsWallet.topUp(poolAmount, {from: g.address});
    await d.rewards.setAnnualStakingRewardsRate(12000, poolAmount, {from: d.functionalManager.address});
    tlog("Staking pools topped up");

    await g.assignAndApproveExternalToken(poolAmount, d.bootstrapRewardsWallet.address);
    await d.bootstrapRewardsWallet.topUp(poolAmount, {from: g.address});
    await d.rewards.setGeneralCommitteeAnnualBootstrap(fromTokenUnits(12000), {from: d.functionalManager.address});
    await d.rewards.setCertifiedCommitteeAnnualBootstrap(fromTokenUnits(12000), {from: d.functionalManager.address});
    tlog("Bootstrap pools topped up");

    let committee: Participant[] = [];
    for (let i = 0; i < MAX_COMMITTEE; i++) {
        const {v} = await d.newGuardian(BASE_STAKE.add(fromTokenUnits(1 + (committeeEvenStakes ? 0 : i))), true, false, false);
        committee = [v].concat(committee);
        console.log(`committee ${i}`)
    }
    tlog("Committee created");

    await Promise.all(_.shuffle(committee).map(v => v.readyForCommittee()));

    const monthlyRate = fromTokenUnits(1000);
    const subs = await d.newSubscriber('defaultTier', monthlyRate);
    const appOwner = d.newParticipant();

    tlog("Subscriber created");

    for (let i = 0; i < numVCs; i++) {
        await createVC(d, false, subs, monthlyRate, appOwner);
        await createVC(d, true, subs, monthlyRate, appOwner);
    }
    tlog("VCs created - done init");

    return {
        d,
        committee,
    }
}


describe('gas usage scenarios', async () => {
    it("New delegator stake increase, lowest committee member gets to top", async () => {
        const {d, committee} = await fullCommittee();

        const delegator = d.newParticipant("delegator");
        await delegator.delegate(committee[committee.length - 1]);

        await evmIncreaseTime(d.web3, 30*24*60*60);
        await d.rewards.assignRewards();
        await evmIncreaseTime(d.web3, 30*24*60*60);

        d.resetGasRecording();
        let r = await delegator.stake(BASE_STAKE.mul(bn(1000)));
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: committee.map(v => v.address)
        });

        // const ge = gasReportEvents(r);
        // ge.forEach(e => console.log(JSON.stringify(e)));

        d.logGasUsageSummary("New delegator stake increase, lowest committee member gets to top", [delegator]);
    });

    it("New delegator stake increase, lowest committee jumps one rank higher. No reward distribution.", async () => {
        const {d, committee} = await fullCommittee();

        await d.committee.setMaxTimeBetweenRewardAssignments(24*60*60, {from: d.functionalManager.address});

        const delegator = d.newParticipant("delegator");
        await delegator.delegate(committee[committee.length - 1]);

        d.resetGasRecording();
        let r = await delegator.stake(bn(1));
        expect(r).to.have.a.guardianCommitteeChangeEvent({
            addr: committee[committee.length - 1].address
        });
        expect(r).to.not.have.a.committeeSnapshotEvent();
        expect(r).to.not.have.a.bootstrapRewardsAssignedEvent();

        // const ge = gasReportEvents(r);
        // ge.forEach(e => console.log(JSON.stringify(e)));

        d.logGasUsageSummary("New delegator stake increase, lowest committee jumps one rank higher. No reward distribution.", [delegator]);
    });

    it("Delegation change, top of committee and bottom committee switch places", async () => {
        const {d, committee} = await fullCommittee();

        const delegator = d.newParticipant("delegator");
        await delegator.delegate(committee[0]);
        let r = await delegator.stake(BASE_STAKE.mul(bn(1000)));
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: committee.map(v => v.address)
        });

        d.resetGasRecording();
        r = await delegator.delegate(committee[committee.length - 1]);
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: committee.map(c => c.address)
        });

        d.logGasUsageSummary("Delegation change, top of committee and bottom committee switch places", [delegator]);
    });

    it("New delegator stakes", async () => {
        const {d} = await fullCommittee();

        const delegator = d.newParticipant("delegator");

        d.resetGasRecording();
        let r = await delegator.stake(1);
        expect(r).to.not.have.a.committeeSnapshotEvent();

        d.logGasUsageSummary("New delegator stakes", [delegator]);
    });

    it("Delegator stake increase, no change in committee order", async () => {
        const {d, committee} = await fullCommittee();

        const delegator = d.newParticipant("delegator");
        await delegator.delegate(committee[0]);

        d.resetGasRecording();
        let r = await delegator.stake(1);
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: committee.map(v => v.address)
        });

        d.logGasUsageSummary("Delegator stake increase, no change in committee order", [delegator]);
    });

    it("Guardian sends ready-to-sync for first time", async () => {
        const {d} = await fullCommittee();

        const {v} = await d.newGuardian(BASE_STAKE.add(fromTokenUnits(1)), true, false, false);

        d.resetGasRecording();
        await v.readyToSync();
        d.logGasUsageSummary("Guardian sends ready-to-sync for first time", [v]);
    });

    it("Guardian sends ready-to-sync for second time", async () => {
        const {d} = await fullCommittee();

        const {v} = await d.newGuardian(BASE_STAKE.add(fromTokenUnits(1)), true, false, false);

        await v.readyToSync();

        d.resetGasRecording();
        await v.readyToSync();
        d.logGasUsageSummary("Guardian sends ready-to-sync for second time", [v]);
    });

    it("New guardian sends ready-for-committee and immediately gets to top", async () => {
        const {d, committee} = await fullCommittee();

        const {v} = await d.newGuardian(BASE_STAKE.add(fromTokenUnits(committee.length + 1)), true, false, false);

        d.resetGasRecording();
        let r = await v.readyForCommittee();
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: [v].concat(committee.slice(0, committee.length - 1)).map(v => v.address)
        });

        d.logGasUsageSummary("Delegator stake increase, no change in committee order", [v]);
    });

    it("Ready-to-sync guardian sends ready-for-committee and jumps to top of committee", async () => {
        const {d, committee} = await fullCommittee();

        const {v} = await d.newGuardian(BASE_STAKE.add(fromTokenUnits(committee.length + 1)), true, false, false);

        let r = await v.readyToSync();
        expect(r).to.not.have.a.committeeSnapshotEvent();

        d.resetGasRecording();
        r = await v.readyForCommittee();
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: [v].concat(committee.slice(0, committee.length - 1)).map(v => v.address)
        });

        d.logGasUsageSummary("Ready-to-sync guardian sends ready-for-committee and jumps to top of committee", [v]);
    });

    it("Top committee member unregisters", async () => {
        const {d, committee} = await fullCommittee();

        d.resetGasRecording();
        let r = await committee[0].unregisterAsGuardian();
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: committee.slice(1).map(v => v.address)
        });

        d.logGasUsageSummary("Top committee member unregisters", [committee[0]]);
    });

    it("Auto-voteout is cast, threshold not reached", async () => {
        const {d, committee} = await fullCommittee();

        d.resetGasRecording();
        let r = await d.elections.voteUnready(committee[1].address, 0xFFFFFFFF,{from: committee[0].orbsAddress});
        expect(r).to.not.have.a.committeeSnapshotEvent();
        expect(r).to.have.a.voteUnreadyCastedEvent({
            voter: committee[0].address,
            subject: committee[1].address
        });
        d.logGasUsageSummary("Auto-voteout is cast, threshold not reached", [committee[0]]);
    });

    it("Auto-voteout is cast, threshold is reached and top committee member leaves", async () => {
        const {d, committee} = await fullCommittee(true);

        const voters = committee.slice(0, Math.floor(MAX_COMMITTEE * defaultDriverOptions.voteUnreadyThresholdPercentMille / (100 * 1000)));
        await Promise.all(
            voters.map(v => d.elections.voteUnready(committee[0].address, 0xFFFFFFFF,{from: v.orbsAddress}))
        );

        d.resetGasRecording();

        const thresholdVoter = committee[voters.length];
        let r = await d.elections.voteUnready(committee[0].address, 0xFFFFFFFF, {from: thresholdVoter.orbsAddress});
        expect(r).to.have.a.voteUnreadyCastedEvent({
            voter: thresholdVoter.address,
            subject: committee[0].address
        });
        expect(r).to.have.a.guardianVotedUnreadyEvent({
            guardian: committee[0].address
        });

        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: committee.slice(1).map(v => v.address)
        });

        d.logGasUsageSummary("Auto-voteout is cast, threshold is reached and top committee member leaves", [thresholdVoter]);
    });

    it("Manual-voteout is cast, threshold not reached", async () => {
        const {d, committee} = await fullCommittee();

        d.resetGasRecording();
        let r = await d.elections.voteOut(committee[1].address, {from: committee[0].address});
        expect(r).to.not.have.a.committeeSnapshotEvent();
        expect(r).to.have.a.voteOutCastedEvent({
            voter: committee[0].address,
            subject: committee[1].address
        });
        d.logGasUsageSummary("Manual-voteout is cast, threshold not reached", [committee[0]]);
    });

    it("Manual-voteout is cast, threshold is reached and top committee member leaves", async () => {
        const {d, committee} = await fullCommittee(true);

        const voters = committee.slice(0, Math.floor(MAX_COMMITTEE * defaultDriverOptions.voteUnreadyThresholdPercentMille / (100 * 1000)));
        await Promise.all(
            voters.map(v => d.elections.voteOut(committee[0].address, {from: v.address}))
        );

        d.resetGasRecording();

        const thresholdVoter = committee[voters.length];
        let r = await d.elections.voteOut(committee[0].address, {from: thresholdVoter.address});
        expect(r).to.have.a.voteOutCastedEvent({
            voter: thresholdVoter.address,
            subject: committee[0].address
        });
        expect(r).to.have.a.guardianVotedOutEvent({
            guardian: committee[0].address
        });
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: committee.slice(1).map(v => v.address)
        });

        d.logGasUsageSummary("Manual-voteout is cast, threshold is reached and top committee member leaves", [thresholdVoter]);
    });

    const distributeRewardsScenario = async (batchSize: number) => {
        const {d, committee} = await fullCommittee(true);

        await evmIncreaseTime(d.web3, 30*24*60*60);
        let r = await d.rewards.assignRewards();
        console.log(feesAssignedEvents(r));

        await d.committee.setMaxTimeBetweenRewardAssignments(24*60*60, {from: d.functionalManager.address});

        const v = committee[0];

        const delegator = d.newParticipant();
        await delegator.stake(100);
        await delegator.delegate(v);

        const delegators: Participant[] =await Promise.all(_.range(batchSize).map(async i => {
            const delegator = i == 0 ? v : d.newParticipant();
            await delegator.stake(100);
            await delegator.delegate(committee[i % committee.length]);
            return delegator;
        }));

        const balance = bn(await d.rewards.getStakingRewardBalance(v.address));

        d.resetGasRecording();
        await d.rewards.distributeStakingRewards(
            balance.div(bn(batchSize)).mul(bn(batchSize)),
            0,
            100,
            1,
            0,
            delegators.map(delegator => delegator.address),
            delegators.map(() => balance.div(bn(batchSize)))
            , {from: v.address});

        d.logGasUsageSummary(`Distribute rewards - all delegators delegated to same guardian (batch size - ${batchSize})`, [committee[0]]);
    };

    it("Distribute rewards - all delegators delegated to same guardian (batch size - 1)", async () => {
        await distributeRewardsScenario(1)
    });

    it("Distribute rewards - all delegators delegated to same guardian (batch size - 50)", async () => {
        await distributeRewardsScenario(50)
    });

    it("assigns rewards (1 month, initial balance == 0)", async () => {
        const {d, committee} = await fullCommittee(false, 100);
        await evmIncreaseTime(d.web3, 30*24*60*60);

        const p = d.newParticipant("reward assigner");
        d.resetGasRecording();
        await d.rewards.assignRewards({from: p.address});
        d.logGasUsageSummary("assigns rewards (1 month, initial balance == 0)", [p]);
    });

    it("assigns rewards (1 month, initial balance > 0)", async () => {
        const {d, committee} = await fullCommittee(false, 5);
        await evmIncreaseTime(d.web3, 30*24*60*60);

        await d.rewards.assignRewards();

        await evmIncreaseTime(d.web3, 30*24*60*60);

        const p = d.newParticipant("reward assigner");
        d.resetGasRecording();
        await d.rewards.assignRewards({from: p.address});

        d.logGasUsageSummary("assigns rewards (1 month, initial balance > 0)", [p]);
    });

    it("imports 50 delegations, unregistered guardians", async () => {
        const d = await Driver.new();

        await d.stakingContractHandler.setNotifyDelegations(false, {from: d.migrationManager.address});

        const delegate = d.newParticipant();
        const delegations = _.range(50).map(() => d.newParticipant());
        await Promise.all(delegations.map(d => d.stake(100)));

        await d.stakingContractHandler.setNotifyDelegations(true, {from: d.migrationManager.address});

        d.resetGasRecording();
        let r = await d.delegations.importDelegations(
            delegations.map(d => d.address),
            delegate.address,
            false
        , {from: d.migrationManager.address});
        expect(r).to.have.a.delegationsImportedEvent({
            from: delegations.map(d => d.address),
            to: delegate.address
        });

        d.logGasUsageSummary("import 50 delegations, unregistered guardians", [d.migrationManager]);
    });

});
