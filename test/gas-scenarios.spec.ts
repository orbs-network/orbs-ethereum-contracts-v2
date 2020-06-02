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
import {bn, evmIncreaseTime, fromTokenUnits} from "./helpers";
import {gasReportEvents} from "./event-parsing";

declare const web3: Web3;

chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const expect = chai.expect;
const assert = chai.assert;

const BASE_STAKE = fromTokenUnits(1000000);
const MAX_COMMITTEE = 22;
const MAX_STANDBYS = 5;

const t0 = Date.now();
const tlog = (s) => console.log(Math.floor(Date.now()/1000 - t0/1000), s);

async function fullCommitteeAndStandbys(committeeEvenStakes:boolean = false, standbysEvenStakes:boolean = false, numVCs=5): Promise<{d: Driver, committee: Participant[], standbys: Participant[]}> {
    tlog("Creating driver..");
    const d = await Driver.new({maxCommitteeSize: MAX_COMMITTEE, maxStandbys: MAX_STANDBYS, maxDelegationRatio: 255});
    tlog("Driver created");

    const poolAmount = fromTokenUnits(1000000);
    await d.erc20.assign(d.accounts[0], poolAmount);
    await d.erc20.approve(d.rewards.address, poolAmount);
    await d.rewards.setAnnualStakingRewardsRate(12000, poolAmount);
    await d.rewards.topUpStakingRewardsPool(poolAmount);
    tlog("Staking pools topped up");

    await d.externalToken.assign(d.accounts[0], poolAmount);
    await d.externalToken.approve(d.rewards.address, poolAmount);
    await d.rewards.setGeneralCommitteeAnnualBootstrap(fromTokenUnits(12000));
    await d.rewards.setComplianceCommitteeAnnualBootstrap(fromTokenUnits(12000));
    await d.rewards.topUpBootstrapPool(poolAmount);
    tlog("Bootstrap pools topped up");

    let standbys: Participant[] = [];
    for (let i = MAX_STANDBYS - 1; i >= 0; i--) {
        const {v} = await d.newValidator(BASE_STAKE.sub(fromTokenUnits(standbysEvenStakes ? 0 : i)), false, false, false);
        standbys = [v].concat(standbys);
        console.log(`standby ${i}`)
    }
    tlog("Standbys created");

    let committee: Participant[] = [];
    for (let i = 0; i < MAX_COMMITTEE; i++) {
        const {v} = await d.newValidator(BASE_STAKE.add(fromTokenUnits(1 + (committeeEvenStakes ? 0 : i))), false, false, false);
        committee = [v].concat(committee);
        console.log(`committee ${i}`)
    }
    tlog("Committee created");

    await Promise.all(_.shuffle(committee.concat(standbys)).map(v => v.notifyReadyForCommittee()));

    const monthlyRate = 1000;
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
        standbys
    }
}


describe('gas usage scenarios', async () => {
    it("New delegator stake increase, lowest committee member gets to top", async () => {
        const {d, committee} = await fullCommitteeAndStandbys();

        const delegator = d.newParticipant("delegator");
        await delegator.delegate(committee[committee.length - 1]);

        await evmIncreaseTime(d.web3, 30*24*60*60);
        await d.rewards.assignRewards();
        await evmIncreaseTime(d.web3, 30*24*60*60);

        d.resetGasRecording();
        let r = await delegator.stake(BASE_STAKE.mul(bn(1000)));
        expect(r).to.have.a.committeeChangedEvent({
            addrs: committee.map(v => v.address)
        });

        // const ge = gasReportEvents(r);
        // ge.forEach(e => console.log(JSON.stringify(e)));

        d.logGasUsageSummary("New delegator stake increase, lowest committee member gets to top", [delegator]);
    });

    it("Delegation change, top of committee and bottom standby switch places", async () => {
        const {d, committee, standbys} = await fullCommitteeAndStandbys();

        const delegator = d.newParticipant("delegator");
        await delegator.delegate(committee[0]);
        let r = await delegator.stake(BASE_STAKE.mul(bn(1000)));
        expect(r).to.have.a.committeeChangedEvent({
            addrs: committee.map(v => v.address)
        });

        await committee[0].unstake(BASE_STAKE.add(bn(committee.length)));
        r = await committee[0].stake(BASE_STAKE.sub(bn(standbys.length + 1)));
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

        const {v} = await d.newValidator(BASE_STAKE.add(bn(1)), true, false, false);

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

        const {v} = await d.newValidator(BASE_STAKE.add(bn(1)), true, false, false);

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

        const {v} = await d.newValidator(BASE_STAKE.add(bn(committee.length + 1)), true, false, false);

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

        const {v} = await d.newValidator(BASE_STAKE.add(bn(committee.length + 1)), true, false, false);

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
        await d.rewards.assignRewards();

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

        const balance = bn(await d.rewards.getStakingRewardBalance(v.address));

        d.resetGasRecording();
        await d.rewards.distributeOrbsTokenStakingRewards(
            balance.div(bn(batchSize)).mul(bn(batchSize)),
            0,
            100,
            1,
            0,
            delegators.map(delegator => delegator.address),
            delegators.map(() => balance.div(bn(batchSize)))
            , {from: committee[0].address});

        d.logGasUsageSummary(`Distribute rewards - all delegators delegated to same validator (batch size - ${batchSize})`, [committee[0]]);
    };

    it("Distribute rewards - all delegators delegated to same validator (batch size - 1)", async () => {
        await distributeRewardsScenario(1)
    });

    it("Distribute rewards - all delegators delegated to same validator (batch size - 50)", async () => {
        await distributeRewardsScenario(50)
    });

    it("Distribute rewards - all delegators delegated to same validator (batch size - 200)", async () => {
        await distributeRewardsScenario(200)
    });

    it("assigns rewards (1 month, initial balance == 0)", async () => {
        const {d, committee, standbys} = await fullCommitteeAndStandbys(false, false, 100);
        await evmIncreaseTime(d.web3, 30*24*60*60);

        const p = d.newParticipant("reward assigner");
        d.resetGasRecording();
        await d.rewards.assignRewards({from: p.address});
        d.logGasUsageSummary("assigns rewards (1 month, initial balance == 0)", [p]);
    });

    it("assigns rewards (1 month, initial balance > 0)", async () => {
        const {d, committee, standbys} = await fullCommitteeAndStandbys(false, false, 5);
        await evmIncreaseTime(d.web3, 30*24*60*60);

        await d.rewards.assignRewards();

        await evmIncreaseTime(d.web3, 30*24*60*60);

        const p = d.newParticipant("reward assigner");
        d.resetGasRecording();
        await d.rewards.assignRewards({from: p.address});

        d.logGasUsageSummary("assigns rewards (1 month, initial balance > 0)", [p]);
    });

});
