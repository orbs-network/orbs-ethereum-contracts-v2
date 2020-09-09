import 'mocha';

import * as _ from "lodash";
import Web3 from "web3";
declare const web3: Web3;
import {bn, evmIncreaseTime, expectRejected, fromTokenUnits, minAddress} from "./helpers";
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

describe.only('committee', async () => {

    // Basic tests

    it('joins committee only after ready-for-committee', async () => {
        const d = await Driver.new();

        const stake = 100;
        const v = await d.newParticipant();

        let r = await v.registerAsGuardian();
        expect(r).to.not.have.a.guardianCommitteeChangeEvent();

        r = await v.stake(stake);
        expect(r).to.not.have.a.guardianCommitteeChangeEvent();

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
        expect(r).to.not.have.a.guardianCommitteeChangeEvent();

        r = await v.stake(stake);
        expect(r).to.not.have.a.guardianCommitteeChangeEvent();

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
        expect(r).to.not.have.a.guardianCommitteeChangeEvent();
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
        expect(r2).to.not.have.a.guardianCommitteeChangeEvent();

        let r = await v2.readyToSync(); // should now become not ready-for-committee
        r = await v2.stake(2); // now has more stake than committee member, but not ready so should not enter committee
        expect(r).to.not.have.a.guardianCommitteeChangeEvent();
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
        expect(r).to.not.have.a.guardianCommitteeChangeEvent();

        r = await v.stake(stake - 1);
        expect(r).to.not.have.a.guardianCommitteeChangeEvent();

        r = await v.readyForCommittee();
        expect(r).to.not.have.a.guardianCommitteeChangeEvent();

        r = await v.stake(stake*10);
        expect(r).to.not.have.a.guardianCommitteeChangeEvent();

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
        expect(r).to.not.have.a.guardianCommitteeChangeEvent();
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

        r = await d.committee.getCommitteeInfo();
        expect([r[0], r[1], r[2], r[3], r[4]]).to.deep.equal(
            [
                committee.map(({v}) => v.address),
                committee.map(({stake}) => stake.toString()),
                committee.map(({v}) => v.orbsAddress),
                committee.map(({certified}) => certified),
                committee.map(({v}) => v.ip),
            ]
        );

        // have a middle committee member leave
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

    it("sets and gets settings, only functional manager/registry manager allowed to set", async () => {
        const d = await Driver.new();

        const current = await d.committee.getSettings();
        const maxTimeBetweenRewardAssignments = bn(current[0]);
        const maxCommitteeSize = bn(current[1]);

        const committee: Participant[] = await Promise.all(_.range(maxCommitteeSize.toNumber()).map(async (i) => (await d.newGuardian(fromTokenUnits(100 + i), false, false, true)).v));

        await expectRejected(d.committee.setMaxTimeBetweenRewardAssignments(maxTimeBetweenRewardAssignments.add(bn(1)), {from: d.migrationManager.address}), /sender is not the functional manager/);

        let r = await d.committee.setMaxTimeBetweenRewardAssignments(maxTimeBetweenRewardAssignments.add(bn(1)), {from: d.functionalManager.address});
        expect(r).to.have.a.maxTimeBetweenRewardAssignmentsChangedEvent({
            newValue: maxTimeBetweenRewardAssignments.add(bn(1)).toString(),
            oldValue: maxTimeBetweenRewardAssignments.toString()
        });

        await expectRejected(d.committee.setMaxCommitteeSize(maxCommitteeSize.sub(bn(1)), {from: d.migrationManager.address}), /sender is not the functional manager/);
        r = await d.committee.setMaxCommitteeSize(maxCommitteeSize.sub(bn(1)), {from: d.registryAdmin.address});
        expect(r).to.have.a.maxCommitteeSizeChangedEvent({
            newValue: maxCommitteeSize.sub(bn(1)).toString(),
            oldValue: maxCommitteeSize.toString()
        });

        expect(r).to.have.a.guardianCommitteeChangeEvent({
            addr: committee[0].address,
            inCommittee: false
        });

        const afterUpdate = await d.committee.getSettings();
        expect([afterUpdate[0], afterUpdate[1]]).to.deep.eq([
            maxTimeBetweenRewardAssignments.add(bn(1)).toString(),
            maxCommitteeSize.sub(bn(1)).toString(),
        ]);

        expect(await d.committee.getMaxCommitteeSize()).to.bignumber.eq(maxCommitteeSize.sub(bn(1)))
        expect(await d.committee.getMaxTimeBetweenRewardAssignments()).to.bignumber.eq(maxTimeBetweenRewardAssignments.add(bn(1)))
    });

    it("validates 0 < maxCommitteeSize", async () => {
       const d = await Driver.new();

       await expectRejected(d.committee.setMaxCommitteeSize(0, {from: d.functionalManager.address}), /maxCommitteeSize must be larger than 0/);
    });

    it("allows only elections to notify committee on changes", async () => {
        const d = await Driver.new();

        const {v} = await d.newGuardian(fromTokenUnits(10), true, false, true);
        const notElections = d.newParticipant().address;
        await expectRejected(d.committee.memberWeightChange(v.address, fromTokenUnits(1), {from: notElections}), /caller is not the elections/);
        await expectRejected(d.committee.memberCertificationChange(v.address, true, {from: notElections}), /caller is not the elections/);
        const v2 = d.newParticipant();
        await expectRejected(d.committee.addMember(v2.address, fromTokenUnits(10), true, {from: notElections}), /caller is not the elections/);
        await expectRejected(d.committee.removeMember(v2.address, {from: notElections}), /caller is not the elections/);
    });

    it("allows committee methods to be called only when active", async () => {
        const d = await Driver.new();

        const {v} = await d.newGuardian(fromTokenUnits(10), true, false, true);
        const v2 = d.newParticipant();

        const elections = d.newParticipant().address;
        await d.contractRegistry.setContract("elections", elections, false,{from: d.registryAdmin.address});

        await d.committee.lock({from: d.registryAdmin.address});

        await expectRejected(d.committee.memberWeightChange(v.address, fromTokenUnits(1), {from: elections}), /contract is locked for this operation/);
        await expectRejected(d.committee.memberCertificationChange(v.address, true, {from: elections}), /contract is locked for this operation/);
        await expectRejected(d.committee.addMember(v2.address, fromTokenUnits(10), true, {from: elections}), /contract is locked for this operation/);
        await expectRejected(d.committee.removeMember(v2.address, {from: elections}), /contract is locked for this operation/);

        await d.committee.unlock({from: d.registryAdmin.address});

        await d.committee.memberWeightChange(v.address, fromTokenUnits(1), {from: elections});
        await d.committee.memberCertificationChange(v.address, true, {from: elections});
        await d.committee.addMember(v2.address, fromTokenUnits(10), true, {from: elections});
        await d.committee.removeMember(v2.address, {from: elections});

    });

    it("validate constructor arguments (0 < maxCommitteeSize)", async () => {
        const d = await Driver.new();

        await expectRejected(d.web3.deploy('Committee', [d.contractRegistry.address, d.registryAdmin.address, 0, 1]), /maxCommitteeSize must be larger than 0/);
        await d.web3.deploy('Committee', [d.contractRegistry.address, d.registryAdmin.address, 1, 1]);
    });

    // it("validates weight is within range - less than 2^96", async () => {
    //     const d = await Driver.new();
    //
    //     const {v} = await d.newGuardian(fromTokenUnits(10), true, false, true);
    //
    //     const elections = d.newParticipant().address;
    //     await d.contractRegistry.setContract("elections", elections, false,{from: d.registryAdmin.address});
    //
    //     await expectRejected(d.committee.memberChange(v.address, bn(2).pow(bn(96)), true, {from: elections}), /weight is out of range/);
    //     await d.committee.memberChange(v.address, bn(2).pow(bn(96)).sub(bn(1)), true, {from: elections});
    //
    //     const v2 = await d.newParticipant();
    //
    //     await expectRejected(d.committee.addMember(v2.address, bn(2).pow(bn(96)), true, {from: elections}), /weight is out of range/);
    //     await d.committee.addMember(v2.address, bn(2).pow(bn(96)).sub(bn(1)), true, {from: elections});
    // });

    it("handles notifications for unregistered guardians", async () => {
        const d = await Driver.new();

        const nonRegistered = await d.newParticipant();

        const elections = d.newParticipant().address;
        await d.contractRegistry.setContract("elections", elections, false,{from: d.registryAdmin.address});

        let r = await d.committee.memberWeightChange(nonRegistered.address, fromTokenUnits(1), {from: elections});
        expect(r).to.not.have.a.guardianCommitteeChangeEvent();

        r = await d.committee.memberCertificationChange(nonRegistered.address, true,{from: elections});
        expect(r).to.not.have.a.guardianCommitteeChangeEvent();
    });

    it("handles adding existing member", async () => {
        const d = await Driver.new();

        const {v} = await d.newGuardian(fromTokenUnits(10), true, false, true);

        const elections = d.newParticipant().address;
        await d.contractRegistry.setContract("elections", elections, false,{from: d.registryAdmin.address});

        const r = await d.committee.addMember(v.address, fromTokenUnits(5), false, {from: elections});
        expect(r).to.not.have.a.guardianCommitteeChangeEvent();
    });

    it("emits incremental committee change events", async () => {
        const d = await Driver.new({maxTimeBetweenRewardAssignments: 2*24*60*60});

        let stake = bn(100);

        // evicted => committee
        let {v, r} = await d.newGuardian(stake, false, false, true);
        expect(r).to.have.a.guardianCommitteeChangeEvent({
            addr: v.address,
            weight: stake,
            certification: false,
            inCommittee: true,
        });

        // committee weight change
        r = await v.stake(1);
        stake = stake.add(bn(1));
        expect(r).to.have.a.guardianCommitteeChangeEvent({
            addr: v.address,
            weight: stake,
            certification: false,
            inCommittee: true,
        });

        // committee certification change
        r = await v.becomeCertified();
        expect(r).to.have.a.guardianCommitteeChangeEvent({
            addr: v.address,
            weight: stake,
            certification: true,
            inCommittee: true,
        });

        r = await v.becomeNotCertified();
        expect(r).to.have.a.guardianCommitteeChangeEvent({
            addr: v.address,
            weight: stake,
            certification: false,
            inCommittee: true,
        });

        // committee => evicted
        r = await v.readyToSync();
        expect(r).to.have.a.guardianCommitteeChangeEvent({
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
        expect(r).to.have.a.guardianCommitteeChangeEvent({
            addr: c2.address,
            inCommittee: true,
        });
        expect(r).to.have.a.guardianCommitteeChangeEvent({
            addr: c1.address,
            inCommittee: false,
        });
    });

    it("assigns rewards and emits snapshot event only if enough time has passed", async () => {
        const maxTimeBetweenRewardAssignments = 2 * 24 * 60 * 60;
        const d = await Driver.new({
            maxTimeBetweenRewardAssignments: maxTimeBetweenRewardAssignments,
            maxCommitteeSize: 1,
        });

        let {r: r1, v: c} = await d.newGuardian(bn(1), false, false, true);
        expect(r1).to.have.a.guardianCommitteeChangeEvent({
            addr: c.address,
            inCommittee: true,
            weight: bn(1)
        });
        expect(r1).to.not.have.a.guardianCommitteeChangeEvent();
        expect(r1).to.not.have.a.stakingRewardsAssignedEvent();
        expect(r1).to.not.have.a.feesAssignedEvent();
        expect(r1).to.not.have.a.bootstrapRewardsAssignedEvent();

        let r = await c.stake(1);
        expect(r).to.not.have.a.guardianCommitteeChangeEvent();
        expect(r).to.not.have.a.stakingRewardsAssignedEvent();
        expect(r).to.not.have.a.feesAssignedEvent();
        expect(r).to.not.have.a.bootstrapRewardsAssignedEvent();

        await evmIncreaseTime(d.web3, maxTimeBetweenRewardAssignments);

        r = await c.stake(1);
        expect(r).to.have.a.guardianCommitteeChangeEvent({
            addr: c.address,
            inCommittee: true,
            weight: bn(3)
        });
        await expectCommittee(d,  {
            addrs: [c.address]
        });
        expect(r).to.have.a.stakingRewardsAssignedEvent({
            assignees: [c.address]
        });
        expect(r).to.have.a.feesAssignedEvent({});
        expect(r).to.have.a.bootstrapRewardsAssignedEvent({});

        r = await c.stake(1);
        expect(r).to.have.a.guardianCommitteeChangeEvent({
            addr: c.address,
            inCommittee: true,
            weight: bn(4)
        });
        expect(r).to.not.have.a.guardianCommitteeChangeEvent();
        expect(r).to.not.have.a.stakingRewardsAssignedEvent();
        expect(r).to.not.have.a.feesAssignedEvent();
        expect(r).to.not.have.a.bootstrapRewardsAssignedEvent();
    })
});
