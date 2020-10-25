import 'mocha';

import * as _ from "lodash";
import Web3 from "web3";
declare const web3: Web3;
import {bn, evmIncreaseTime, expectRejected, fromMilliOrbs, minAddress} from "./helpers";
import {chaiEventMatchersPlugin, expectCommittee} from "./matchers";

import BN from "bn.js";
import {
    defaultDriverOptions,
    Driver,
    Participant,
} from "./driver";
import chai from "chai";
chai.use(require('chai-bn')(BN));
chai.use(chaiEventMatchersPlugin);

const expect = chai.expect;
const assert = chai.assert;

describe('committee', async () => {

    // Basic tests

    it('joins committee only after ready-for-committee', async () => {
        const d = await Driver.new();

        const stake = 100;
        const v = await d.newParticipant();

        let r = await v.registerAsGuardian();
        expect(r).to.not.have.a.committeeChangeEvent();

        r = await v.stake(stake);
        expect(r).to.not.have.a.committeeChangeEvent();

        r = await v.readyToSync();
        r = await v.readyForCommittee();
        await expectCommittee(d,  {
            addrs: [v.address],
            weights: [bn(stake)]
        });
    });

    it('joins straight to committee on ready-for-committee', async () => {
        const d = await Driver.new();

        const stake = 100;
        const v = await d.newParticipant();

        let r = await v.registerAsGuardian();
        expect(r).to.not.have.a.committeeChangeEvent();

        r = await v.stake(stake);
        expect(r).to.not.have.a.committeeChangeEvent();

        r = await v.readyForCommittee();
        await expectCommittee(d,  {
            addrs: [v.address],
            weights: [bn(stake)]
        });
    });

    it('does not allow more than maxCommitteeSize', async () => {
        const d = await Driver.new();

        const stake = 100;
        const committee: Participant[] = [];

        for (let i = 0; i < defaultDriverOptions.maxCommitteeSize; i++) {
            const v = await d.newParticipant();
            committee.push(v);

            await v.registerAsGuardian();
            await v.stake(stake);
            let r = await v.readyForCommittee();
            await expectCommittee(d,  {
                addrs: committee.map(s => s.address),
                weights: committee.map(s => bn(stake))
            });
        }

        const v = await d.newParticipant();
        await v.registerAsGuardian();
        await v.stake(stake - 1);
        let r = await v.readyForCommittee();
        expect(r).to.not.have.a.committeeChangeEvent();
    });

    it('evicts a committee member which explicitly became removed', async () => {
        const d = await Driver.new();

        const stake = 100;
        const v = await d.newParticipant();

        await v.registerAsGuardian();
        await v.stake(stake);
        let r = await v.readyForCommittee();
        await expectCommittee(d,  {
            addrs: [v.address],
            weights: [bn(stake)]
        });

        await d.contractRegistry.setContract("elections", d.contractsOwnerAddress, false,{from: d.registryAdmin.address}); // hack to make subsequent call
        r = await d.committee.removeMember(v.address, {from: d.contractsOwnerAddress});
        await expectCommittee(d,  {addrs: []});
    });

    it('evicts a committee member which became not-ready-for-committee because it sent ready-to-sync', async () => {
        const d = await Driver.new();

        const stake = 100;
        const v = await d.newParticipant();

        await v.registerAsGuardian();
        await v.stake(stake);
        let r = await v.readyForCommittee();
        await expectCommittee(d,  {
            addrs: [v.address],
            weights: [bn(stake)]
        });

        r = await v.readyToSync();
        await expectCommittee(d,  {addrs: []});
    });

    it('does not allow a non-ready guardian to join committee even if was ready previously', async () => {
        const d = await Driver.new({maxCommitteeSize: 1});

        const stake = 100;
        const {v: v1, r: r1} = await d.newGuardian(stake, false, false, true); // committee now full
        await expectCommittee(d,{addrs: [v1.address]});

        const {v: v2, r: r2} = await d.newGuardian(stake - 1, false, false, true); // a ready member
        expect(r2).to.not.have.a.committeeChangeEvent();

        let r = await v2.readyToSync(); // should now become not ready-for-committee
        r = await v2.stake(2); // now has more stake than committee member, but not ready so should not enter committee
        expect(r).to.not.have.a.committeeChangeEvent();
    });

    it('guardian can overtake committee member with more stake', async () => {
        const d = await Driver.new();

        const stake = 100;
        const committee: Participant[] = [];

        for (let i = 0; i < defaultDriverOptions.maxCommitteeSize; i++) {
            const v = await d.newParticipant();
            committee.push(v);

            await v.registerAsGuardian();
            await v.stake(stake + i);
            let r = await v.readyForCommittee();
            await expectCommittee(d,  {
                addrs: committee.map(s => s.address),
                weights: committee.map((s, i) => bn(stake + i))
            });
        }

        const v = await d.newParticipant();
        let r = await v.registerAsGuardian();
        expect(r).to.not.have.a.committeeChangeEvent();

        r = await v.stake(stake - 1);
        expect(r).to.not.have.a.committeeChangeEvent();

        r = await v.readyForCommittee();
        expect(r).to.not.have.a.committeeChangeEvent();

        r = await v.stake(stake*10);
        expect(r).to.not.have.a.committeeChangeEvent();

        r = await v.readyForCommittee();
        await expectCommittee(d,  {
            addrs: [v].concat(committee.slice(1)).map(s => s.address),
        });

    });

    it('non-committee-ready guardian with more stake cannot overtake a committee member', async () => {
        const d = await Driver.new();

        const stake = 100;
        const committee: Participant[] = [];

        for (let i = 0; i < defaultDriverOptions.maxCommitteeSize; i++) {
            const v = await d.newParticipant();
            committee.push(v);

            await v.registerAsGuardian();
            await v.stake(stake);
            let r = await v.readyForCommittee();
            await expectCommittee(d,  {
                addrs: committee.map(s => s.address),
                weights: committee.map(s => bn(stake))
            });
        }

        const v = await d.newParticipant();
        await v.registerAsGuardian();
        await v.stake(stake);
        await v.readyToSync();
        let r = await v.stake(stake);
        expect(r).to.not.have.a.committeeChangeEvent();
    });

    it('returns committee using getters', async () => {
        const maxCommitteeSize = 4;
        const d = await Driver.new({maxCommitteeSize});

        const stake = 100;

        const committee: any[] = [];

        for (let i = 0; i < maxCommitteeSize; i++) {
            const curStake = stake*(maxCommitteeSize - i);
            const certified = i % 2 == 0;

            const v = await d.newParticipant();
            await v.registerAsGuardian();
            await v.stake(curStake);
            if (certified) {
                await v.becomeCertified();
            }
            committee.push({
                v,
                stake: curStake,
                certified
            });

            let r = await v.readyForCommittee();
            await expectCommittee(d,  {
                addrs: committee.map(({v}) => v.address),
            });
        }

        let r: any = await d.committee.getCommittee();
        expect([r[0], r[1]]).to.deep.equal(
            [
                committee.map(({v}) => v.address),
                committee.map(({stake}) => stake.toString()),
            ]
        );

        await committee[1].v.unregisterAsGuardian();
        committee.splice(1,1);

        [committee[1], committee[2]] = [committee[2], committee[1]]; // TODO order is incidental but consistent, better matchers can be used

        r = await d.committee.getCommittee();
        expect(r[0]).to.deep.equal(committee.map(({v}) => v.address));
    });

    it('emit committeeChanged when committee member change certification', async () => {
        const d = await Driver.new();

        const stake = 100;
        const {v: committeeMember, r: r1} = await d.newGuardian(stake, false, false, true);
        await expectCommittee(d,{
            addrs: [committeeMember.address]
        });

        let r = await committeeMember.becomeCertified();
        await expectCommittee(d,  {
            addrs: [committeeMember.address],
            certification: [true]
        });

        r = await committeeMember.becomeNotCertified();
        await expectCommittee(d,  {
            addrs: [committeeMember.address],
            certification: [false]
        });
    });

    it('emit committeeChanged for new committee member with correct certification flags', async () => {
        const d = await Driver.new();

        const stake = 100;
        const {v: v1, r: r1} = await d.newGuardian(stake, false, false, true);
        await expectCommittee(d,{
            addrs: [v1.address],
            certification: [false]
        });

        const {v: v2, r: r2} = await d.newGuardian(stake - 1, true, false, true);
        await expectCommittee(d, {
            addrs: [v1.address, v2.address],
            certification: [false, true]
        });

    });

    it('uses address as tie-breaker when stakes are equal', async () => {
        const maxCommitteeSize = 10;
        const d = await Driver.new({maxCommitteeSize});

        const stake = 100;

        const guardians = _.range(maxCommitteeSize + 1).map(() => d.newParticipant());
        const excluded = guardians.find(x => x.address == minAddress(guardians.map(x => x.address))) as Participant;
        const committee = guardians.filter(x => x != excluded);
        let r = await excluded.becomeGuardian(stake, false, false, true);
        for (let i = 0; i < maxCommitteeSize; i++) {
            r = await committee[i].becomeGuardian(stake, false, false, true);
        }

        await expectCommittee(d,  {
            addrs: committee.map(v => v.address)
        });
    });

    it("sets and gets maxCommitteeSize, only functional manager/registry manager allowed to set", async () => {
        const d = await Driver.new();

        const maxCommitteeSize = bn(await d.committee.getMaxCommitteeSize());

        const committee: Participant[] = await Promise.all(_.range(maxCommitteeSize.toNumber()).map(async (i) => (await d.newGuardian(fromMilliOrbs(100 + i), false, false, true)).v));

        await expectRejected(d.committee.setMaxCommitteeSize(maxCommitteeSize.sub(bn(1)), {from: d.migrationManager.address}), /sender is not the functional manager/);
        let r = await d.committee.setMaxCommitteeSize(maxCommitteeSize.sub(bn(1)), {from: d.registryAdmin.address});
        expect(r).to.have.a.maxCommitteeSizeChangedEvent({
            newValue: maxCommitteeSize.sub(bn(1)).toString(),
            oldValue: maxCommitteeSize.toString()
        });

        expect(r).to.have.a.committeeChangeEvent({
            addr: committee[0].address,
            inCommittee: false
        });

        expect(await d.committee.getMaxCommitteeSize()).to.bignumber.eq(maxCommitteeSize.sub(bn(1)))
    });

    it("allows only elections to notify committee on changes", async () => {
        const d = await Driver.new();

        const {v} = await d.newGuardian(fromMilliOrbs(10), true, false, true);
        const notElections = d.newParticipant().address;
        await expectRejected(d.committee.memberWeightChange(v.address, fromMilliOrbs(1), {from: notElections}), /caller is not the elections/);
        await expectRejected(d.committee.memberCertificationChange(v.address, true, {from: notElections}), /caller is not the elections/);
        const v2 = d.newParticipant();
        await expectRejected(d.committee.addMember(v2.address, fromMilliOrbs(10), true, {from: notElections}), /caller is not the elections/);
        await expectRejected(d.committee.removeMember(v2.address, {from: notElections}), /caller is not the elections/);
    });

    it("allows committee methods to be called only when active", async () => {
        const d = await Driver.new();

        const {v} = await d.newGuardian(fromMilliOrbs(10), true, false, true);
        const v2 = d.newParticipant();

        const elections = d.newParticipant().address;
        await d.contractRegistry.setContract("elections", elections, false,{from: d.registryAdmin.address});

        await d.committee.lock({from: d.registryAdmin.address});

        await expectRejected(d.committee.memberWeightChange(v.address, fromMilliOrbs(1), {from: elections}), /contract is locked for this operation/);
        await expectRejected(d.committee.memberCertificationChange(v.address, true, {from: elections}), /contract is locked for this operation/);
        await expectRejected(d.committee.addMember(v2.address, fromMilliOrbs(10), true, {from: elections}), /contract is locked for this operation/);
        await expectRejected(d.committee.removeMember(v2.address, {from: elections}), /contract is locked for this operation/);

        await d.committee.unlock({from: d.registryAdmin.address});

        await d.committee.memberWeightChange(v.address, fromMilliOrbs(1), {from: elections});
        await d.committee.memberCertificationChange(v.address, true, {from: elections});
        await d.committee.addMember(v2.address, fromMilliOrbs(10), true, {from: elections});
        await d.committee.removeMember(v2.address, {from: elections});

    });

    it("handles notifications for unregistered guardians", async () => {
        const d = await Driver.new();

        const nonRegistered = await d.newParticipant();

        const elections = d.newParticipant().address;
        await d.contractRegistry.setContract("elections", elections, false,{from: d.registryAdmin.address});

        let r = await d.committee.memberWeightChange(nonRegistered.address, fromMilliOrbs(1), {from: elections});
        expect(r).to.not.have.a.committeeChangeEvent();

        r = await d.committee.memberCertificationChange(nonRegistered.address, true,{from: elections});
        expect(r).to.not.have.a.committeeChangeEvent();
    });

    it("handles adding existing member", async () => {
        const d = await Driver.new();

        const {v} = await d.newGuardian(fromMilliOrbs(10), true, false, true);

        const elections = d.newParticipant().address;
        await d.contractRegistry.setContract("elections", elections, false,{from: d.registryAdmin.address});

        const r = await d.committee.addMember(v.address, fromMilliOrbs(5), false, {from: elections});
        expect(r).to.not.have.a.committeeChangeEvent();
    });

    it("emits incremental committee change events", async () => {
        const d = await Driver.new({maxTimeBetweenRewardAssignments: 2*24*60*60});

        let stake = bn(100);

        // evicted => committee
        let {v, r} = await d.newGuardian(stake, false, false, true);
        expect(r).to.have.a.committeeChangeEvent({
            addr: v.address,
            weight: stake,
            certification: false,
            inCommittee: true,
        });

        // committee weight change
        r = await v.stake(1);
        stake = stake.add(bn(1));
        expect(r).to.have.a.committeeChangeEvent({
            addr: v.address,
            weight: stake,
            certification: false,
            inCommittee: true,
        });

        // committee certification change
        r = await v.becomeCertified();
        expect(r).to.have.a.committeeChangeEvent({
            addr: v.address,
            weight: stake,
            certification: true,
            inCommittee: true,
        });

        r = await v.becomeNotCertified();
        expect(r).to.have.a.committeeChangeEvent({
            addr: v.address,
            weight: stake,
            certification: false,
            inCommittee: true,
        });

        // committee => evicted
        r = await v.readyToSync();
        expect(r).to.have.a.committeeChangeEvent({
            addr: v.address,
            weight: stake,
            certification: false,
            inCommittee: false,
        });
    });

    it("emits increments committee change events for two changed members - a new committee member and an evicted committee member", async () => {
        const d = await Driver.new({
            maxTimeBetweenRewardAssignments: 2 * 24 * 60 * 60,
            maxCommitteeSize: 1,
        });

        const {v: c1} = await d.newGuardian(bn(2), false, false, true);
        const {r, v: c2} = await d.newGuardian(bn(3), false, false, true);
        expect(r).to.have.a.committeeChangeEvent({
            addr: c2.address,
            inCommittee: true,
        });
        expect(r).to.have.a.committeeChangeEvent({
            addr: c1.address,
            inCommittee: false,
        });
    });

    it("emits committee snapshot", async () => {
        const d = await Driver.new();

        const {v: v1} = await d.newGuardian(fromMilliOrbs(10), false, false, true);
        const {v: v2} = await d.newGuardian(fromMilliOrbs(20), true, false, true);

        const addrs = [v1.address, v2.address];
        const weights = [fromMilliOrbs(10), fromMilliOrbs(20)];
        const certification = [false, true];

        const r = await d.committee.emitCommitteeSnapshot();
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs,
            weights,
            certification
        });
        expect(r).to.have.a.committeeChangeEvent({
            addr: v1.address,
            weight: fromMilliOrbs(10),
            certification: false
        });
        expect(r).to.have.a.committeeChangeEvent({
            addr: v2.address,
            weight: fromMilliOrbs(20),
            certification: true
        });
    });

    it('migrates members from previous committee contract', async () => {
        const d = await Driver.new();

        const {v: v1} = await d.newGuardian(1000, false, false, true);
        const {v: v2} = await d.newGuardian(2000, true, false, true);
        const newCommittee = await d.web3.deploy('Committee', [d.contractRegistry.address, d.registryAdmin.address, defaultDriverOptions.maxCommitteeSize]);

        const r = await newCommittee.importMembers(d.committee.address, {from: d.initializationAdmin.address});
        expect(r).to.have.a.committeeChangeEvent({
            addr: v1.address,
            weight: bn(1000),
            certification: false
        });
        expect(r).to.have.a.committeeChangeEvent({
            addr: v2.address,
            weight: bn(2000),
            certification: true
        });
    })
});
