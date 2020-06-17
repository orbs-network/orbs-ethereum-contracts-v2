import 'mocha';

import * as _ from "lodash";
import Web3 from "web3";
declare const web3: Web3;

import BN from "bn.js";
import {
    defaultDriverOptions,
    BANNING_LOCK_TIMEOUT,
    Driver,
    expectRejected,
    Participant, ZERO_ADDR
} from "./driver";
import chai from "chai";
chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const expect = chai.expect;
const assert = chai.assert;

import {bn, evmIncreaseTime, fromTokenUnits, minAddress} from "./helpers";
import {ETHEREUM_URL} from "../eth";


describe('committee', async () => {

    // Basic tests: standbys, committee

    it('becomes standby only after ready-to-sync', async () => {
        const d = await Driver.new();

        const stake = 100;
        const v = await d.newParticipant();

        let r = await v.registerAsValidator();
        expect(r).to.not.have.a.standbysChangedEvent();
        expect(r).to.not.have.a.committeeChangedEvent();

        r = await v.stake(stake);
        expect(r).to.not.have.a.standbysChangedEvent();
        expect(r).to.not.have.a.committeeChangedEvent();

        r = await v.notifyReadyToSync();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v.address],
            weights: [bn(stake)]
        });
        expect(r).to.not.have.a.committeeChangedEvent();
    });

    it('joins committee and leaves standbys only after ready-for-committee', async () => {
        const d = await Driver.new();

        const stake = 100;
        const v = await d.newParticipant();

        let r = await v.registerAsValidator();
        expect(r).to.not.have.a.standbysChangedEvent();
        expect(r).to.not.have.a.committeeChangedEvent();

        r = await v.stake(stake);
        expect(r).to.not.have.a.standbysChangedEvent();
        expect(r).to.not.have.a.committeeChangedEvent();

        r = await v.notifyReadyToSync();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v.address],
            weights: [bn(stake)]
        });
        expect(r).to.not.have.a.committeeChangedEvent();

        r = await v.notifyReadyForCommittee();
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [v.address],
            weights: [bn(stake)]
        });
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [],
            weights: []
        });
    });

    it('joins straight to committee on ready-for-committee', async () => {
        const d = await Driver.new();

        const stake = 100;
        const v = await d.newParticipant();

        let r = await v.registerAsValidator();
        expect(r).to.not.have.a.standbysChangedEvent();
        expect(r).to.not.have.a.committeeChangedEvent();

        r = await v.stake(stake);
        expect(r).to.not.have.a.standbysChangedEvent();
        expect(r).to.not.have.a.committeeChangedEvent();

        r = await v.notifyReadyForCommittee();
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [v.address],
            weights: [bn(stake)]
        });
        expect(r).to.not.have.a.standbysChangedEvent();
    });

    it('does not allow more than maxStandbys', async () => {
        const d = await Driver.new();

        const stake = 100;
        const standbys: Participant[] = [];

        for (let i = 0; i < defaultDriverOptions.maxStandbys; i++) {
            const v = await d.newParticipant();
            standbys.push(v);

            await v.registerAsValidator();
            await v.stake(stake);
            let r = await v.notifyReadyToSync();
            expect(r).to.have.a.standbysChangedEvent({
                addrs: standbys.map(s => s.address),
                weights: standbys.map(s => bn(stake))
            });
            expect(r).to.not.have.a.committeeChangedEvent();
        }

        const v = await d.newParticipant();
        await v.registerAsValidator();
        await v.stake(stake - 1);
        let r = await v.notifyReadyToSync();
        expect(r).to.not.have.a.standbysChangedEvent();
        expect(r).to.not.have.a.committeeChangedEvent();
    });

    it('does not allow more than maxCommitteeSize', async () => {
        const d = await Driver.new();

        const stake = 100;
        const committee: Participant[] = [];

        for (let i = 0; i < defaultDriverOptions.maxCommitteeSize; i++) {
            const v = await d.newParticipant();
            committee.push(v);

            await v.registerAsValidator();
            await v.stake(stake);
            let r = await v.notifyReadyForCommittee();
            expect(r).to.have.a.committeeChangedEvent({
                addrs: committee.map(s => s.address),
                weights: committee.map(s => bn(stake))
            });
            expect(r).to.not.have.a.standbysChangedEvent();
        }

        const v = await d.newParticipant();
        await v.registerAsValidator();
        await v.stake(stake - 1);
        let r = await v.notifyReadyForCommittee();
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v.address]
        });
    });

    it('evicts a committee member which explicitly became not-ready-to-sync', async () => {
        const d = await Driver.new();

        const stake = 100;
        const v = await d.newParticipant();

        await v.registerAsValidator();
        await v.stake(stake);
        let r = await v.notifyReadyForCommittee();
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [v.address],
            weights: [bn(stake)]
        });
        expect(r).to.not.have.a.standbysChangedEvent();

        await d.contractRegistry.set("elections", d.contractsOwnerAddress, {from: d.functionalOwner.address}); // hack to make subsequent call
        r = await d.committee.memberNotReadyToSync(v.address, {from: d.contractsOwnerAddress});
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [],
        });
        expect(r).to.not.have.a.standbysChangedEvent();
    });

    it('evicts a committee member which became not-ready-for-committee because it sent ready-to-sync', async () => {
        const d = await Driver.new();

        const stake = 100;
        const v = await d.newParticipant();

        await v.registerAsValidator();
        await v.stake(stake);
        let r = await v.notifyReadyForCommittee();
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [v.address],
            weights: [bn(stake)]
        });
        expect(r).to.not.have.a.standbysChangedEvent();

        r = await v.notifyReadyToSync();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v.address],
            weights: [bn(stake)]
        });
        expect(r).to.have.a.committeeChangedEvent({
            addrs: []
        });
    });

    it('does not allow a non-ready standby to join committee even if was ready previously', async () => {
        const d = await Driver.new({maxCommitteeSize: 1});

        const stake = 100;
        const {v: v1, r: r1} = await d.newValidator(stake, false, false, true); // committee now full
        expect(r1).to.have.a.committeeChangedEvent({
            addrs: [v1.address]
        });

        const {v: v2, r: r2} = await d.newValidator(stake - 1, false, false, true); // a ready standby
        expect(r2).to.have.a.standbysChangedEvent({
            addrs: [v2.address]
        });

        let r = await v2.notifyReadyToSync(); // should now become not ready-for-committee
        expect(r).to.not.have.a.committeeChangedEvent();

        r = await v2.stake(2); // now has more stake than committee member, but not ready so should not enter committee
        expect(r).to.not.have.committeeChangedEvent();
    });

    it('evicts a standby which explicitly became not-ready-to-sync', async () => {
        const d = await Driver.new();

        const stake = 100;
        const v = await d.newParticipant();

        await v.registerAsValidator();
        await v.stake(stake);
        let r = await v.notifyReadyToSync();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v.address],
            weights: [bn(stake)]
        });
        expect(r).to.not.have.a.committeeChangedEvent();

        await d.contractRegistry.set("elections", d.contractsNonOwnerAddress, {from: d.functionalOwner.address}); // hack to make subsequent call
        r = await d.committee.memberNotReadyToSync(v.address, {from: d.contractsNonOwnerAddress});
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [],
        });
        expect(r).to.not.have.a.committeeChangedEvent();
    });

    it('standby can overtake committee member with more stake', async () => {
        const d = await Driver.new();

        const stake = 100;
        const committee: Participant[] = [];

        for (let i = 0; i < defaultDriverOptions.maxCommitteeSize; i++) {
            const v = await d.newParticipant();
            committee.push(v);

            await v.registerAsValidator();
            await v.stake(stake + i);
            let r = await v.notifyReadyForCommittee();
            expect(r).to.have.a.committeeChangedEvent({
                addrs: committee.map(s => s.address),
                weights: committee.map((s, i) => bn(stake + i))
            });
            expect(r).to.not.have.a.standbysChangedEvent();
        }

        const v = await d.newParticipant();
        let r = await v.registerAsValidator();
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.not.have.a.standbysChangedEvent();

        r = await v.stake(stake - 1);
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.not.have.a.standbysChangedEvent();

        r = await v.notifyReadyForCommittee();
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v.address]
        });

        r = await v.stake(stake);
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [committee[0].address],
        });
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [v].concat(committee.slice(1)).map(s => s.address),
        });

    });

    it('non-committee-ready standby with more stake cannot overtake a committee member', async () => {
        const d = await Driver.new();

        const stake = 100;
        const committee: Participant[] = [];

        for (let i = 0; i < defaultDriverOptions.maxCommitteeSize; i++) {
            const v = await d.newParticipant();
            committee.push(v);

            await v.registerAsValidator();
            await v.stake(stake);
            let r = await v.notifyReadyForCommittee();
            expect(r).to.have.a.committeeChangedEvent({
                addrs: committee.map(s => s.address),
                weights: committee.map(s => bn(stake))
            });
            expect(r).to.not.have.a.standbysChangedEvent();
        }

        const v = await d.newParticipant();
        await v.registerAsValidator();
        await v.stake(stake);
        let r = await v.notifyReadyToSync();
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v.address]
        });

        r = await v.stake(stake);
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v.address],
            weights: [bn(2 * stake)]
        });

    });

    it('two non-ready-for-committee with more stake can overtake two ready-for-committee standbys', async () => {
        const maxStandbys = 3;
        const d = await Driver.new({maxStandbys});

        const stake = 100;
        const committee: Participant[] = [];

        for (let i = 0; i < defaultDriverOptions.maxCommitteeSize; i++) {
            const v = await d.newParticipant();
            committee.push(v);

            await v.registerAsValidator();
            await v.stake(stake * 2 + i);
            let r = await v.notifyReadyForCommittee();
            expect(r).to.have.a.committeeChangedEvent({
                addrs: committee.map(s => s.address),
            });
            expect(r).to.not.have.a.standbysChangedEvent();
        }

        const standbys: Participant[] = [];

        for (let i = 0; i < maxStandbys; i++) {
            const v = await d.newParticipant();
            standbys.push(v);

            await v.registerAsValidator();
            await v.stake(i <= 1 ? (stake + i): stake * 2);
            let r = i <= 1 ? await v.notifyReadyForCommittee() : await v.notifyReadyToSync();
            expect(r).to.have.a.standbysChangedEvent({
                addrs: standbys.map(s => s.address),
            });
            expect(r).to.not.have.a.committeeChangedEvent();
        }

        const v1 = await d.newParticipant();
        await v1.registerAsValidator();
        await v1.stake(stake + 4);
        let r = await v1.notifyReadyToSync();
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [standbys[1], standbys[2], v1].map(s => s.address)
        });

        const v2 = await d.newParticipant();
        await v2.registerAsValidator();
        await v2.notifyReadyToSync();
        r = await v2.stake(stake + 3);
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [standbys[2], v1, v2].map(s => s.address)
        });

    });

    it('evicts the lowest staked standby when both standbys and committee are full and a new committee member enters', async () => {
        const maxStandbys = 2;
        const maxCommitteeSize = 2;
        const d = await Driver.new({maxStandbys, maxCommitteeSize});

        const stake = 100;

        const committee: Participant[] = [];
        for (let i = 0; i < maxCommitteeSize; i++) {
            const v = await d.newParticipant();
            committee.push(v);

            await v.registerAsValidator();
            await v.stake(stake + i);
            let r = await v.notifyReadyForCommittee();
            expect(r).to.have.a.committeeChangedEvent({
                addrs: committee.map(s => s.address),
            });
            expect(r).to.not.have.a.standbysChangedEvent();
        }

        const standbys: Participant[] = [];
        for (let i = 0; i < maxStandbys; i++) {
            const v = await d.newParticipant();
            standbys.push(v);

            await v.registerAsValidator();
            await v.stake(stake - 1 - i);
            let r = await v.notifyReadyToSync();
            expect(r).to.have.a.standbysChangedEvent({
                addrs: standbys.map(s => s.address),
            });
            expect(r).to.not.have.a.committeeChangedEvent();
        }

        const v1 = await d.newParticipant();
        await v1.registerAsValidator();
        await v1.stake(stake + defaultDriverOptions.maxCommitteeSize);
        let r = await v1.notifyReadyForCommittee();
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [v1, committee[1]].map(v => v.address)
        });
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [committee[0], standbys[0]].map(s => s.address)
        });

    });

    it('notifies StandbysChanged when a committee member leaves and a standby joins the committee', async () => {
        const maxStandbys = 2;
        const maxCommitteeSize = 2;
        const d = await Driver.new({maxStandbys, maxCommitteeSize});

        const stake = 100;

        const committee: Participant[] = [];
        for (let i = 0; i < maxCommitteeSize; i++) {
            const v = await d.newParticipant();
            committee.push(v);

            await v.registerAsValidator();
            await v.stake(stake + maxStandbys + i);
            let r = await v.notifyReadyForCommittee();
            expect(r).to.have.a.committeeChangedEvent({
                addrs: committee.map(s => s.address),
            });
            expect(r).to.not.have.a.standbysChangedEvent();
        }

        const standbys: Participant[] = [];
        for (let i = 0; i < maxStandbys; i++) {
            const v = await d.newParticipant();
            standbys.push(v);

            await v.registerAsValidator();
            await v.stake(stake + i);
            let r = await v.notifyReadyForCommittee();
            expect(r).to.have.a.standbysChangedEvent({
                addrs: standbys.map(s => s.address),
            });
            expect(r).to.not.have.a.committeeChangedEvent();
        }

        let r = await committee[0].unregisterAsValidator();
        expect(r).to.have.a.committeeChangedEvent({
            addrs: committee.slice(1).concat([standbys[standbys.length - 1]]).map(v => v.address)
        });
        expect(r).to.have.a.standbysChangedEvent({
            addrs: standbys.slice(0, standbys.length - 1).map(v => v.address)
        });
    });

    // Ready-To-Sync timeout related tests

    it('two ready-for-sync with less stake can overtake two timed-out standbys', async () => {
        const maxStandbys = 2;
        const readyToSyncTimeout = 30*24*60*60;
        const d = await Driver.new({maxStandbys, readyToSyncTimeout});

        const stake = 100;

        const standbys: Participant[] = [];
        for (let i = 0; i < maxStandbys; i++) {
            const v = await d.newParticipant();
            standbys.push(v);

            await v.registerAsValidator();
            await v.stake(stake);
            let r = await v.notifyReadyToSync();
            expect(r).to.have.a.standbysChangedEvent({
                addrs: standbys.map(s => s.address),
            });
            expect(r).to.not.have.a.committeeChangedEvent();
        }

        await evmIncreaseTime(d.web3, readyToSyncTimeout);

        const v1 = await d.newParticipant();
        await v1.registerAsValidator();
        await v1.stake(stake - 1);
        let r = await v1.notifyReadyToSync();
        expect(r).to.not.have.a.committeeChangedEvent();

        const v2 = await d.newParticipant();
        await v2.registerAsValidator();
        await v2.notifyReadyToSync();
        r = await v2.stake(stake - 1);
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v1, v2].map(s => s.address)
        });

    });

    it('an out-ranked committee member can become standby even with stale readyToSync', async () => {
        const maxStandbys = 1;
        const maxCommitteeSize = 1;
        const readyToSyncTimeout = 30*24*60*60;
        const d = await Driver.new({maxStandbys, readyToSyncTimeout, maxCommitteeSize});

        const stake = 100;

        const v1 = await d.newParticipant();
        await v1.registerAsValidator();
        await v1.stake(stake);
        let r = await v1.notifyReadyForCommittee();
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [v1.address],
        });
        expect(r).to.not.have.a.standbysChangedEvent();

        await evmIncreaseTime(d.web3, readyToSyncTimeout);

        const v2 = await d.newParticipant();
        await v2.registerAsValidator();
        await v2.stake(stake + 1);
        r = await v2.notifyReadyForCommittee();
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [v2.address],
        });
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v1.address],
        });
    });

    it('a stale readyToSync does not get a validator evicted from committee', async () => {
        const maxStandbys = 1;
        const maxCommitteeSize = 1;
        const readyToSyncTimeout = 30*24*60*60;
        const d = await Driver.new({maxStandbys, readyToSyncTimeout, maxCommitteeSize});

        const stake = 100;

        const v1 = await d.newParticipant();
        await v1.registerAsValidator();
        await v1.stake(stake);
        let r = await v1.notifyReadyForCommittee();
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [v1.address],
        });
        expect(r).to.not.have.a.standbysChangedEvent();

        await evmIncreaseTime(d.web3, readyToSyncTimeout);

        const v2 = await d.newParticipant();
        await v2.registerAsValidator();
        await v2.stake(stake - 1);
        r = await v2.notifyReadyForCommittee();
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v2.address],
        });
    });

    it('stake change does not count as a readyToSync notification', async () => {
        const maxStandbys = 1;
        const readyToSyncTimeout = 30*24*60*60;
        const d = await Driver.new({maxStandbys, readyToSyncTimeout});

        const stake = 100;

        const v1 = await d.newParticipant();
        await v1.registerAsValidator();
        await v1.stake(stake);
        let r = await v1.notifyReadyToSync();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v1.address],
        });
        expect(r).to.not.have.a.committeeChangedEvent();

        await evmIncreaseTime(d.web3, readyToSyncTimeout);

        r = await v1.stake(1);
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.have.a.standbysChangedEvent({ // due to weight change
            addrs: [v1.address],
        });

        // v1 is still timed-out so a new validator with less stake should overtake

        const v2 = await d.newParticipant();
        await v2.registerAsValidator();
        await v2.stake(stake);
        r = await v2.notifyReadyToSync();
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v2.address],
        });
    });

    it('evicts a higher-staked, timed-out standby when both standbys and committee are full and a new committee member enters', async () => {
        const maxStandbys = 2;
        const maxCommitteeSize = 2;
        const readyToSyncTimeout = 30*24*60*60;
        const d = await Driver.new({maxStandbys, maxCommitteeSize, readyToSyncTimeout});

        const stake = 100;

        const committee: Participant[] = [];
        for (let i = 0; i < maxCommitteeSize; i++) {
            const v = await d.newParticipant();
            committee.push(v);

            await v.registerAsValidator();
            await v.stake(stake + i);
            let r = await v.notifyReadyForCommittee();
            expect(r).to.have.a.committeeChangedEvent({
                addrs: committee.map(s => s.address),
            });
            expect(r).to.not.have.a.standbysChangedEvent();
        }

        const standbys: Participant[] = [];
        for (let i = 0; i < maxStandbys; i++) {
            const v = await d.newParticipant();
            standbys.push(v);

            await v.registerAsValidator();
            await v.stake(stake - i);
            let r = await v.notifyReadyToSync();
            expect(r).to.have.a.standbysChangedEvent({
                addrs: standbys.map(s => s.address),
            });
            expect(r).to.not.have.a.committeeChangedEvent();
        }

        await evmIncreaseTime(d.web3, readyToSyncTimeout);
        await standbys[1].notifyReadyToSync();


        // all standbys are not timed-out, except the first which also has more stake
        // A new committee member should cause an eviction of the first standby, despite having more stake than the rest

        const v1 = await d.newParticipant();
        await v1.registerAsValidator();
        await v1.stake(stake + 2);
        let r = await v1.notifyReadyForCommittee();
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [v1, committee[1]].map(v => v.address)
        });
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [committee[0], standbys[1]].map(s => s.address)
        });

    });

    it('sets last ready-to-sync timestamp to now for a validator who left the committee by unstaking and became a standby', async () => {
        const maxStandbys = 1;
        const maxCommitteeSize = 1;
        const readyToSyncTimeout = 30*24*60*60;
        const d = await Driver.new({maxStandbys, maxCommitteeSize, readyToSyncTimeout});

        const stake = 100;
        const {v: v1, r: r1} = await d.newValidator(stake, false, false, true);
        expect(r1).to.have.a.committeeChangedEvent({
            addrs: [v1.address]
        });

        await evmIncreaseTime(d.web3, readyToSyncTimeout + 1); // v1's timestamp is now stale

        const {v: v2, r: r2} = await d.newValidator(stake - 1, false, false, true);
        expect(r2).to.not.have.a.committeeChangedEvent();
        expect(r2).to.have.a.standbysChangedEvent({
            addrs: [v2.address]
        });

        let r = await v1.unstake(2); // now have less stake than v2 hence becoming a standby and v2 joins committee
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [v2.address]
        });
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v1.address]
        });

        // v1's timestamp should be recent, so a now validator with less stake will not overtake it
        const {r: r3} = await d.newValidator(stake - 3, false, true, false);
        expect(r3).to.not.have.a.committeeChangedEvent();
        expect(r3).to.not.have.a.standbysChangedEvent();
    });

    it('sets last ready-to-sync timestamp to now for a validator who left the committee to became a standby by being outranked', async () => {
        const maxStandbys = 1;
        const maxCommitteeSize = 1;
        const readyToSyncTimeout = 30*24*60*60;
        const d = await Driver.new({maxStandbys, maxCommitteeSize, readyToSyncTimeout});

        const stake = 100;
        const {v: v1, r: r1} = await d.newValidator(stake, false, false, true);
        expect(r1).to.have.a.committeeChangedEvent({
            addrs: [v1.address]
        });

        await evmIncreaseTime(d.web3, readyToSyncTimeout + 1); // v1's timestamp is now stale

        const {v: v2, r: r2} = await d.newValidator(stake + 1, false, false, true);
        expect(r2).to.have.a.committeeChangedEvent({
            addrs: [v2.address]
        });
        expect(r2).to.have.a.standbysChangedEvent({
            addrs: [v1.address]
        });

        // v1's timestamp should be recent, so a now validator with less stake will not overtake it
        const {r: r3} = await d.newValidator(stake - 3, false, true, false);
        expect(r3).to.not.have.a.committeeChangedEvent();
        expect(r3).to.not.have.a.standbysChangedEvent();
    });

    it('returns committee and standbys using getters', async () => {
        const maxStandbys = 4;
        const maxCommitteeSize = 4;
        const d = await Driver.new({maxStandbys, maxCommitteeSize});

        const stake = 100;

        const committee: Participant[] = [];
        for (let i = 0; i < maxCommitteeSize; i++) {
            const v = await d.newParticipant();
            committee.push(v);

            await v.registerAsValidator();
            await v.stake(stake*(maxCommitteeSize - i));
            if (i % 2 == 0) {
                await v.becomeCompliant();
            }
            let r = await v.notifyReadyForCommittee();
            expect(r).to.have.a.committeeChangedEvent({
                addrs: committee.map(s => s.address),
            });
            expect(r).to.not.have.a.standbysChangedEvent();
        }

        const standbys: Participant[] = [];
        for (let i = 0; i < maxStandbys; i++) {
            const v = await d.newParticipant();
            standbys.push(v);

            await v.registerAsValidator();
            await v.stake(stake*(maxStandbys - i));
            if (i % 2 == 0) {
                await v.becomeCompliant();
            }
            let r = await v.notifyReadyToSync();
            expect(r).to.have.a.standbysChangedEvent({
                addrs: standbys.map(s => s.address),
            });
            expect(r).to.not.have.a.committeeChangedEvent();
        }

        let r: any = await d.committee.getCommittee();
        expect([r[0], r[1]]).to.deep.equal(
            [
                committee.map(v => v.address),
                committee.map((v, i) => (stake * (maxCommitteeSize - i)).toString()),
            ]
        );

        r = await d.committee.getCommitteeInfo();
        expect([r[0], r[1], r[2], r[3], r[4]]).to.deep.equal(
            [
                committee.map(v => v.address),
                committee.map((v, i) => (stake * (maxCommitteeSize - i)).toString()),
                committee.map(v => v.orbsAddress),
                committee.map((v, i) => i % 2 == 0),
                committee.map(v => v.ip),
            ]
        );

        r = await d.committee.getStandbys();
        expect([r[0], r[1]]).to.deep.equal(
            [
                standbys.map(v => v.address),
                standbys.map((v, i) => (stake * (maxStandbys - i)).toString()),
            ]
        );

        r = await d.committee.getStandbysInfo();
        expect([r[0], r[1], r[2], r[3], r[4]]).to.deep.equal(
            [
                standbys.map(v => v.address),
                standbys.map((v, i) => (stake * (maxStandbys - i)).toString()),
                standbys.map(v => v.orbsAddress),
                committee.map((v, i) => i % 2 == 0),
                standbys.map(v => v.ip),
            ]
        );

        // have a middle committee member leave
        await committee[1].unregisterAsValidator();
        committee.splice(1,1);

        r = await d.committee.getCommittee();
        expect(r[0]).to.deep.equal(committee.map(v => v.address));

        // have a middle standby leave
        await standbys[1].unregisterAsValidator();
        standbys.splice(1,1);

        r = await d.committee.getStandbys();
        expect(r[0]).to.deep.equal(standbys.map(v => v.address));
    });

    it('emit committeeChanged/standbyChanged when committee member/standby change compliance', async () => {
        const d = await Driver.new();

        const stake = 100;
        const {v: committeeMember, r: r1} = await d.newValidator(stake, false, false, true);
        expect(r1).to.have.a.committeeChangedEvent({
            addrs: [committeeMember.address]
        });

        const {v: standby, r: r2} = await d.newValidator(stake - 1, false, true, false);
        expect(r2).to.have.a.standbysChangedEvent({
            addrs: [standby.address]
        });

        let r = await committeeMember.becomeCompliant();
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [committeeMember.address],
            compliance: [true]
        });

        r = await committeeMember.becomeNotCompliant();
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [committeeMember.address],
            compliance: [false]
        });

        r = await standby.becomeCompliant();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [standby.address],
            compliance: [true]
        });

        r = await standby.becomeNotCompliant();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [standby.address],
            compliance: [false]
        });

    });

    it('emit committeeChanged/standbyChanged for new committee member/standby with correct compliance flags', async () => {
        const d = await Driver.new();

        const stake = 100;
        const {v: v1, r: r1} = await d.newValidator(stake, false, false, true);
        expect(r1).to.have.a.committeeChangedEvent({
            addrs: [v1.address],
            compliance: [false]
        });

        const {v: v2, r: r2} = await d.newValidator(stake - 1, true, false, true);
        expect(r2).to.have.a.committeeChangedEvent({
            addrs: [v1.address, v2.address],
            compliance: [false, true]
        });

        const {v: s1, r: r3} = await d.newValidator(stake, false, true, false);
        expect(r3).to.have.a.standbysChangedEvent({
            addrs: [s1.address],
            compliance: [false]
        });

        const {v: s2, r: r4} = await d.newValidator(stake - 1, true, true, false);
        expect(r4).to.have.a.standbysChangedEvent({
            addrs: [s1.address, s2.address],
            compliance: [false, true]
        });

    });

    it('uses address as tie-breaker when stakes are equal', async () => {
        const maxCommitteeSize = 10;
        const maxStandbys = 10;
        const d = await Driver.new({maxCommitteeSize, maxStandbys});

        const stake = 100;

        const validators = _.range(maxCommitteeSize + 1).map(() => d.newParticipant());
        const standby = validators.find(x => x.address == minAddress(validators.map(x => x.address))) as Participant;
        const committee = validators.filter(x => x != standby);
        let r = await standby.becomeValidator(stake, false, false, true);
        for (let i = 0; i < maxCommitteeSize; i++) {
            r = await committee[i].becomeValidator(stake, false, false, true);
        }

        expect(r).to.have.a.standbysChangedEvent({
            addrs: [standby.address],
            weights: [bn(stake)]
        });
    });

    it("sets and gets settings, only functional owner allowed to set", async () => {
        const d = await Driver.new();

        const current = await d.committee.getSettings();
        const readyToSyncTimeout = bn(current[0]);
        const maxCommitteeSize = bn(current[1]);
        const maxStandbys = bn(current[2]);

        const committee: Participant[] = await Promise.all(_.range(maxCommitteeSize.toNumber()).map(async (i) => (await d.newValidator(fromTokenUnits(100 + i), false, false, true)).v));
        const standbys: Participant[] = await Promise.all(_.range(maxCommitteeSize.toNumber() + 1).map(async (i) => (await d.newValidator(fromTokenUnits(100 - i), false, false, true)).v));

        await expectRejected(d.committee.setReadyToSyncTimeout(readyToSyncTimeout.add(bn(1)), {from: d.migrationOwner.address}));
        let r = await d.committee.setReadyToSyncTimeout(readyToSyncTimeout.add(bn(1)), {from: d.functionalOwner.address});
        expect(r).to.have.a.readyToSyncTimeoutChangedEvent({
            newValue: readyToSyncTimeout.add(bn(1)).toString(),
            oldValue: readyToSyncTimeout.toString()
        });

        await expectRejected(d.committee.setMaxCommitteeAndStandbys(maxCommitteeSize.add(bn(1)), maxStandbys, {from: d.migrationOwner.address}));
        r = await d.committee.setMaxCommitteeAndStandbys(maxCommitteeSize.add(bn(1)), maxStandbys, {from: d.functionalOwner.address});
        expect(r).to.have.a.maxCommitteeSizeChangedEvent({
            newValue: maxCommitteeSize.add(bn(1)).toString(),
            oldValue: maxCommitteeSize.toString()
        });
        expect(r).to.have.a.committeeChangedEvent({
            addrs: committee.concat([standbys[0]]).map(v => v.address)
        });
        expect(r).to.have.a.standbysChangedEvent({
            addrs: standbys.slice(1, maxStandbys.toNumber()).map(v => v.address)
        });

        await expectRejected(d.committee.setMaxCommitteeAndStandbys(maxCommitteeSize.add(bn(1)), maxStandbys.add(bn(1)), {from: d.migrationOwner.address}));
        r = await d.committee.setMaxCommitteeAndStandbys(maxCommitteeSize.add(bn(1)), maxStandbys.add(bn(1)), {from: d.functionalOwner.address});
        expect(r).to.have.a.maxStandbysChangedEvent({
            newValue: maxStandbys.add(bn(1)).toString(),
            oldValue: maxStandbys.toString()
        });

        r = await standbys[2].notifyReadyToSync();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: standbys.slice(1).map(v => v.address)
        });

        const afterUpdate = await d.committee.getSettings();
        expect([afterUpdate[0], afterUpdate[1], afterUpdate[2]]).to.deep.eq([
            readyToSyncTimeout.add(bn(1)).toString(),
            maxCommitteeSize.add(bn(1)).toString(),
            maxStandbys.add(bn(1)).toString(),
        ]);
    });

    it("does not allow to set a topology larger than 32, maxCommittee and maxStandby must be larger than 0", async () => {
       const d = await Driver.new();

       await d.committee.setMaxCommitteeAndStandbys(1, 2,{from: d.functionalOwner.address});

       await expectRejected(d.committee.setMaxCommitteeAndStandbys(2, 31, {from: d.functionalOwner.address}));
       await expectRejected(d.committee.setMaxCommitteeAndStandbys(0, 1, {from: d.functionalOwner.address}));
       await expectRejected(d.committee.setMaxCommitteeAndStandbys(1, 0, {from: d.functionalOwner.address}));
       await expectRejected(d.committee.setMaxCommitteeAndStandbys(0, 0, {from: d.functionalOwner.address}));

        await d.committee.setMaxCommitteeAndStandbys(31, 1,{from: d.functionalOwner.address});
    });

    it("allows only elections to notify committee on changes", async () => {
        const d = await Driver.new();

        const {v} = await d.newValidator(fromTokenUnits(10), true, false, true);
        const notElections = d.newParticipant().address;
        const elections = d.newParticipant().address;
        await d.contractRegistry.set("elections", elections, {from: d.functionalOwner.address});

        await expectRejected(d.committee.memberWeightChange(v.address, fromTokenUnits(1), {from: notElections}));
        await d.committee.memberWeightChange(v.address, fromTokenUnits(1), {from: elections});

        await expectRejected(d.committee.memberReadyToSync(v.address, true,{from: notElections}));
        await d.committee.memberReadyToSync(v.address, true, {from: elections});

        await expectRejected(d.committee.memberNotReadyToSync(v.address,{from: notElections}));
        await d.committee.memberNotReadyToSync(v.address, {from: elections});

        await expectRejected(d.committee.memberComplianceChange(v.address,true, {from: notElections}));
        await d.committee.memberComplianceChange(v.address,true,  {from: elections});

        const v2 = d.newParticipant();
        await expectRejected(d.committee.addMember(v2.address, fromTokenUnits(10), true, {from: notElections}));
        await d.committee.addMember(v2.address, fromTokenUnits(10), true, {from: elections});

        await expectRejected(d.committee.removeMember(v2.address, {from: notElections}));
        await d.committee.removeMember(v2.address, {from: elections});
    });

    it("allows committee methods to be called only when active", async () => {
        const d = await Driver.new();

        const {v} = await d.newValidator(fromTokenUnits(10), true, false, true);
        const v2 = d.newParticipant();

        const elections = d.newParticipant().address;
        await d.contractRegistry.set("elections", elections, {from: d.functionalOwner.address});

        await d.committee.lock({from: d.migrationOwner.address});

        await expectRejected(d.committee.memberWeightChange(v.address, fromTokenUnits(1), {from: elections}));
        await expectRejected(d.committee.memberReadyToSync(v.address, true,{from: elections}));
        await expectRejected(d.committee.memberNotReadyToSync(v.address,{from: elections}));
        await expectRejected(d.committee.memberComplianceChange(v.address,true, {from: elections}));
        await expectRejected(d.committee.addMember(v2.address, fromTokenUnits(10), true, {from: elections}));
        await expectRejected(d.committee.removeMember(v2.address, {from: elections}));

        await d.committee.unlock({from: d.migrationOwner.address});

        await d.committee.memberWeightChange(v.address, fromTokenUnits(1), {from: elections});
        await d.committee.memberReadyToSync(v.address, true, {from: elections});
        await d.committee.memberNotReadyToSync(v.address, {from: elections});
        await d.committee.memberComplianceChange(v.address,true,  {from: elections});
        await d.committee.addMember(v2.address, fromTokenUnits(10), true, {from: elections});
        await d.committee.removeMember(v2.address, {from: elections});

    });

    it("validate constructor arguments", async () => {
        const d = await Driver.new();

        await expectRejected(d.web3.deploy('Committee', [0, 1, 1]));
        await expectRejected(d.web3.deploy('Committee', [1, 0, 1]));
        await expectRejected(d.web3.deploy('Committee', [1, 1, 0]));
        await expectRejected(d.web3.deploy('Committee', [30, 3, 1]));
        await d.web3.deploy('Committee', [1, 1, 1]);
    });

    it("validates weight is within range - less than 2^128", async () => {
        const d = await Driver.new();

        const {v} = await d.newValidator(fromTokenUnits(10), true, false, true);

        const elections = d.newParticipant().address;
        await d.contractRegistry.set("elections", elections, {from: d.functionalOwner.address});

        await expectRejected(d.committee.memberWeightChange(v.address, bn(2).pow(bn(128)), {from: elections}));
        await d.committee.memberWeightChange(v.address, bn(2).pow(bn(128)).sub(bn(1)), {from: elections});
    });

    it("validates weight is within range - less than 2^128", async () => {
        const d = await Driver.new();

        const {v} = await d.newValidator(fromTokenUnits(10), true, false, true);

        const elections = d.newParticipant().address;
        await d.contractRegistry.set("elections", elections, {from: d.functionalOwner.address});

        await expectRejected(d.committee.memberWeightChange(v.address, bn(2).pow(bn(128)), {from: elections}));
        await d.committee.memberWeightChange(v.address, bn(2).pow(bn(128)).sub(bn(1)), {from: elections});

        const v2 = await d.newParticipant();

        await expectRejected(d.committee.addMember(v2.address, bn(2).pow(bn(128)), true, {from: elections}));
        await d.committee.addMember(v2.address, bn(2).pow(bn(128)).sub(bn(1)), true, {from: elections});
    });

    it("validates readyToSyncTimeout is positive", async () => {
        const d = await Driver.new();

        await expectRejected(d.committee.setReadyToSyncTimeout(0, {from: d.functionalOwner.address}));
        await d.committee.setReadyToSyncTimeout(1, {from: d.functionalOwner.address});
    });

    it("handles notifications for unregistered validators", async () => {
        const d = await Driver.new();

        const nonRegistered = await d.newParticipant();

        const elections = d.newParticipant().address;
        await d.contractRegistry.set("elections", elections, {from: d.functionalOwner.address});

        let r = await d.committee.memberWeightChange(nonRegistered.address, fromTokenUnits(1), {from: elections});
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.not.have.a.standbysChangedEvent();

        r = await d.committee.memberReadyToSync(nonRegistered.address, true, {from: elections});
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.not.have.a.standbysChangedEvent();

        r = await d.committee.memberNotReadyToSync(nonRegistered.address, {from: elections});
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.not.have.a.standbysChangedEvent();

        r = await d.committee.memberComplianceChange(nonRegistered.address, true, {from: elections});
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.not.have.a.standbysChangedEvent();
    });

    it("handles adding existing member", async () => {
        const d = await Driver.new();

        const {v} = await d.newValidator(fromTokenUnits(10), true, false, true);

        const elections = d.newParticipant().address;
        await d.contractRegistry.set("elections", elections, {from: d.functionalOwner.address});

        const r = await d.committee.addMember(v.address, fromTokenUnits(5), false, {from: elections});
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.not.have.a.standbysChangedEvent();
    });


});
