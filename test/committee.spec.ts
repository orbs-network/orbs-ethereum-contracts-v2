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

import {bn, evmIncreaseTime} from "./helpers";
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
            orbsAddrs: [v.orbsAddress],
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
            orbsAddrs: [v.orbsAddress],
            weights: [bn(stake)]
        });
        expect(r).to.not.have.a.committeeChangedEvent();

        r = await v.notifyReadyForCommittee();
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [v.address],
            orbsAddrs: [v.orbsAddress],
            weights: [bn(stake)]
        });
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [],
            orbsAddrs: [],
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
            orbsAddrs: [v.orbsAddress],
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
                orbsAddrs: standbys.map(s => s.orbsAddress),
                weights: standbys.map(s => bn(stake))
            });
            expect(r).to.not.have.a.committeeChangedEvent();
        }

        const v = await d.newParticipant();
        await v.registerAsValidator();
        await v.stake(stake);
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
                orbsAddrs: committee.map(s => s.orbsAddress),
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
            orbsAddrs: [v.orbsAddress],
            weights: [bn(stake)]
        });
        expect(r).to.not.have.a.standbysChangedEvent();

        await d.contractRegistry.set("elections", d.contractsOwner); // hack to make subsequent call
        r = await d.committeeGeneral.memberNotReadyToSync(v.address);
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
            orbsAddrs: [v.orbsAddress],
            weights: [bn(stake)]
        });
        expect(r).to.not.have.a.standbysChangedEvent();

        r = await v.notifyReadyToSync();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v.address],
            orbsAddrs: [v.orbsAddress],
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
            orbsAddrs: [v.orbsAddress],
            weights: [bn(stake)]
        });
        expect(r).to.not.have.a.committeeChangedEvent();

        await d.contractRegistry.set("elections", d.contractsOwner); // hack to make subsequent call
        r = await d.committeeGeneral.memberNotReadyToSync(v.address);
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
                orbsAddrs: committee.map(s => s.orbsAddress),
                weights: committee.map((s, i) => bn(stake + i))
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

        r = await v.stake(stake);
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [v].concat(committee.slice(1)).map(s => s.address),
        });
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [committee[0].address],
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
                orbsAddrs: committee.map(s => s.orbsAddress),
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
            await v.stake(stake * 2);
            let r = await v.notifyReadyForCommittee();
            expect(r).to.have.a.committeeChangedEvent({
                addrs: committee.map(s => s.address),
                orbsAddrs: committee.map(s => s.orbsAddress),
            });
            expect(r).to.not.have.a.standbysChangedEvent();
        }

        const standbys: Participant[] = [];

        for (let i = 0; i < maxStandbys; i++) {
            const v = await d.newParticipant();
            standbys.push(v);

            await v.registerAsValidator();
            await v.stake(i <= 1 ? stake: stake * 2);
            let r = i <= 1 ? await v.notifyReadyForCommittee() : await v.notifyReadyToSync();
            expect(r).to.have.a.standbysChangedEvent({
                addrs: standbys.map(s => s.address),
                orbsAddrs: standbys.map(s => s.orbsAddress),
            });
            expect(r).to.not.have.a.committeeChangedEvent();
        }

        const v1 = await d.newParticipant();
        await v1.registerAsValidator();
        await v1.stake(stake + 2);
        let r = await v1.notifyReadyToSync();
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [standbys[0], standbys[2], v1].map(s => s.address)
        });

        const v2 = await d.newParticipant();
        await v2.registerAsValidator();
        await v2.notifyReadyToSync();
        r = await v2.stake(stake + 1);
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
            await v.stake(stake);
            let r = await v.notifyReadyForCommittee();
            expect(r).to.have.a.committeeChangedEvent({
                addrs: committee.map(s => s.address),
                orbsAddrs: committee.map(s => s.orbsAddress),
            });
            expect(r).to.not.have.a.standbysChangedEvent();
        }

        const standbys: Participant[] = [];
        for (let i = 0; i < maxStandbys; i++) {
            const v = await d.newParticipant();
            standbys.push(v);

            await v.registerAsValidator();
            await v.stake(stake);
            let r = await v.notifyReadyToSync();
            expect(r).to.have.a.standbysChangedEvent({
                addrs: standbys.map(s => s.address),
                orbsAddrs: standbys.map(s => s.orbsAddress),
            });
            expect(r).to.not.have.a.committeeChangedEvent();
        }

        const v1 = await d.newParticipant();
        await v1.registerAsValidator();
        await v1.stake(stake + 1);
        let r = await v1.notifyReadyForCommittee();
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [v1, committee[0]].map(v => v.address)
        });
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [committee[1], standbys[0]].map(s => s.address)
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
                orbsAddrs: committee.map(s => s.orbsAddress),
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
                orbsAddrs: standbys.map(s => s.orbsAddress),
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
                orbsAddrs: standbys.map(s => s.orbsAddress),
            });
            expect(r).to.not.have.a.committeeChangedEvent();
        }

        await evmIncreaseTime(d.web3, readyToSyncTimeout);

        const v1 = await d.newParticipant();
        await v1.registerAsValidator();
        await v1.stake(stake - 1);
        let r = await v1.notifyReadyToSync();
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [standbys[1], v1].map(s => s.address)
        });

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
            orbsAddrs: [v1.orbsAddress],
        });
        expect(r).to.not.have.a.standbysChangedEvent();

        await evmIncreaseTime(d.web3, readyToSyncTimeout);

        const v2 = await d.newParticipant();
        await v2.registerAsValidator();
        await v2.stake(stake + 1);
        r = await v2.notifyReadyForCommittee();
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [v2.address],
            orbsAddrs: [v2.orbsAddress],
        });
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v1.address],
            orbsAddrs: [v1.orbsAddress],
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
            orbsAddrs: [v1.orbsAddress],
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
            orbsAddrs: [v2.orbsAddress],
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
            orbsAddrs: [v1.orbsAddress],
        });
        expect(r).to.not.have.a.committeeChangedEvent();

        await evmIncreaseTime(d.web3, readyToSyncTimeout);

        r = await v1.stake(1);
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.have.a.standbysChangedEvent({ // due to weight change
            addrs: [v1.address],
            orbsAddrs: [v1.orbsAddress],
        });

        // v1 is still timed-out so a new validator with less stake should overtake

        const v2 = await d.newParticipant();
        await v2.registerAsValidator();
        await v2.stake(stake);
        r = await v2.notifyReadyToSync();
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v2.address],
            orbsAddrs: [v2.orbsAddress],
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
            await v.stake(stake);
            let r = await v.notifyReadyForCommittee();
            expect(r).to.have.a.committeeChangedEvent({
                addrs: committee.map(s => s.address),
                orbsAddrs: committee.map(s => s.orbsAddress),
            });
            expect(r).to.not.have.a.standbysChangedEvent();
        }

        const standbys: Participant[] = [];
        for (let i = 0; i < maxStandbys; i++) {
            const v = await d.newParticipant();
            standbys.push(v);

            await v.registerAsValidator();
            await v.stake(stake);
            let r = await v.notifyReadyToSync();
            expect(r).to.have.a.standbysChangedEvent({
                addrs: standbys.map(s => s.address),
                orbsAddrs: standbys.map(s => s.orbsAddress),
            });
            expect(r).to.not.have.a.committeeChangedEvent();
        }

        await evmIncreaseTime(d.web3, readyToSyncTimeout);
        let r = await committee[1].notifyReadyForCommittee(); // so when removed from committee, will remain a standby
        expect(r).to.have.a.committeeChangedEvent({ // no change in committee order
            addrs: committee.map(v => v.address)
        });
        expect(r).to.not.have.a.standbysChangedEvent();

        await standbys[1].notifyReadyToSync();
        r = await standbys[0].stake(1);
        expect(r).to.have.a.standbysChangedEvent({ // no change in standbys order
            addrs: standbys.map(v => v.address)
        });


        // all standbys are not timed-out, except the first which also has more stake
        // A new committee member should cause an eviction of the first standby, despite having more stake than the rest

        const v1 = await d.newParticipant();
        await v1.registerAsValidator();
        await v1.stake(stake + 1);
        r = await v1.notifyReadyForCommittee();
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [v1, committee[0]].map(v => v.address)
        });
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [committee[1], standbys[1]].map(s => s.address)
        });

    });

    // Min-Weight and Min-Committee-Size

    it('joins committee only if has min-weight (min-committee == 0)', async () => {
        const stake = 100;
        const generalCommitteeMinimumWeight = stake;
        const minCommitteeSize = 0;
        const maxCommitteeSize = 2;
        const d = await Driver.new({minCommitteeSize, maxCommitteeSize, generalCommitteeMinimumWeight: generalCommitteeMinimumWeight});

        const standbys: Participant[] = [];
        for (let i = 0; i < maxCommitteeSize; i++) {
            const v = await d.newParticipant();
            standbys.push(v);
            await v.registerAsValidator();
            await v.stake(stake - 1);
            let r = await v.notifyReadyForCommittee();
            expect(r).to.have.a.standbysChangedEvent({
                addrs: standbys.map(s => s.address),
                orbsAddrs: standbys.map(s => s.orbsAddress),
            });
            expect(r).to.not.have.a.committeeChangedEvent();
        }
    });

    it('joins committee if current is smaller than min-committee even with less than min-weight', async () => {
        const stake = 100;
        const generalCommitteeMinimumWeight = stake;
        const minCommitteeSize = 2;
        const maxCommitteeSize = 3;
        const d = await Driver.new({minCommitteeSize, maxCommitteeSize, generalCommitteeMinimumWeight: generalCommitteeMinimumWeight});

        const standbys: Participant[] = [];
        for (let i = 0; i < maxCommitteeSize; i++) {
            const v = await d.newParticipant();
            standbys.push(v);
            await v.registerAsValidator();
            await v.stake(stake - 1 - i);
            let r = await v.notifyReadyForCommittee();
            if (i != maxCommitteeSize - 1) {
                expect(r).to.have.a.committeeChangedEvent({
                    addrs: standbys.map(s => s.address),
                    orbsAddrs: standbys.map(s => s.orbsAddress),
                });
                expect(r).to.not.have.a.standbysChangedEvent();
            } else {
                expect(r).to.not.have.a.committeeChangedEvent();
                expect(r).to.have.a.standbysChangedEvent({
                    addrs: [standbys[maxCommitteeSize - 1].address],
                    orbsAddrs: [standbys[maxCommitteeSize - 1].orbsAddress]
                });
            }
        }
    });

    it('evicts a committee member which unstaked below the min-weight threshold, if member position is above min-committee', async () => {
        const stake = 100;
        const generalCommitteeMinimumWeight = stake;
        const minCommitteeSize = 0;
        const maxCommitteeSize = 2;
        const readyToSyncTimeout = 30*24*60*60;
        const d = await Driver.new({minCommitteeSize, maxCommitteeSize, readyToSyncTimeout, generalCommitteeMinimumWeight: generalCommitteeMinimumWeight});

        const v = await d.newParticipant();
        await v.registerAsValidator();
        await v.stake(stake);
        let r = await v.notifyReadyForCommittee();
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [v.address],
            orbsAddrs: [v.orbsAddress],
        });
        expect(r).to.not.have.a.standbysChangedEvent();

        r = await v.unstake(1);
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v.address],
            orbsAddrs: [v.orbsAddress],
        });
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [],
            orbsAddrs: [],
        });
    });

    it('does not evict a committee member which unstaked below the min-weight threshold if member position is below min-committee', async () => {
        const stake = 100;
        const generalCommitteeMinimumWeight = stake;
        const minCommitteeSize = 1;
        const maxCommitteeSize = 2;
        const d = await Driver.new({minCommitteeSize, maxCommitteeSize, generalCommitteeMinimumWeight: generalCommitteeMinimumWeight});

        const v = await d.newParticipant();
        await v.registerAsValidator();
        await v.stake(stake);
        let r = await v.notifyReadyForCommittee();
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [v.address],
            orbsAddrs: [v.orbsAddress],
        });
        expect(r).to.not.have.a.standbysChangedEvent();

        r = await v.unstake(1);
        expect(r).to.not.have.a.standbysChangedEvent();
        expect(r).to.have.a.committeeChangedEvent({ // due to weight change
            addrs: [v.address],
            orbsAddrs: [v.orbsAddress],
        });
    });

    it('joins committee due to min-weight change', async () => {
        const stake = 100;
        const generalCommitteeMinimumWeight = stake;
        const minCommitteeSize = 0;
        const maxCommitteeSize = 2;
        const d = await Driver.new({minCommitteeSize, maxCommitteeSize, generalCommitteeMinimumWeight: generalCommitteeMinimumWeight});

        const v = await d.newParticipant();
        await v.registerAsValidator();
        await v.stake(stake - 1);
        let r = await v.notifyReadyForCommittee();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v.address],
            orbsAddrs: [v.orbsAddress],
        });
        expect(r).to.not.have.a.committeeChangedEvent();

        await d.contractRegistry.set("elections", d.contractsOwner); // hack to make subsequent call
        r = await d.committeeGeneral.setMinimumWeight(stake - 1, ZERO_ADDR, minCommitteeSize);
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [],
            orbsAddrs: [],
        });
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [v.address],
            orbsAddrs: [v.orbsAddress],
        });
    });

    it('leaves committee due to min-weight change', async () => {
        const stake = 100;
        const generalCommitteeMinimumWeight = stake;
        const minCommitteeSize = 0;
        const maxCommitteeSize = 2;
        const d = await Driver.new({minCommitteeSize, maxCommitteeSize, generalCommitteeMinimumWeight: generalCommitteeMinimumWeight});

        const v = await d.newParticipant();
        await v.registerAsValidator();
        await v.stake(stake);
        let r = await v.notifyReadyForCommittee();
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [v.address],
            orbsAddrs: [v.orbsAddress],
        });
        expect(r).to.not.have.a.standbysChangedEvent();

        await d.contractRegistry.set("elections", d.contractsOwner); // hack to make subsequent call
        r = await d.committeeGeneral.setMinimumWeight(stake + 1, ZERO_ADDR, minCommitteeSize);
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [],
            orbsAddrs: [],
        });
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v.address],
            orbsAddrs: [v.orbsAddress],
        });
    });

    it('does not join committee due to min-weight change if not ready for committee', async () => {
        const stake = 100;
        const generalCommitteeMinimumWeight = stake;
        const minCommitteeSize = 0;
        const maxCommitteeSize = 2;
        const d = await Driver.new({minCommitteeSize, maxCommitteeSize, generalCommitteeMinimumWeight: generalCommitteeMinimumWeight});

        const v = await d.newParticipant();
        await v.registerAsValidator();
        await v.stake(stake - 1);
        let r = await v.notifyReadyToSync();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v.address],
            orbsAddrs: [v.orbsAddress],
        });
        expect(r).to.not.have.a.committeeChangedEvent();

        await d.contractRegistry.set("elections", d.contractsOwner); // hack to make subsequent call
        r = await d.committeeGeneral.setMinimumWeight(stake - 2, ZERO_ADDR, minCommitteeSize);
        expect(r).to.not.have.a.standbysChangedEvent();
        expect(r).to.not.have.a.committeeChangedEvent();
    });

    it('joins committee due to min-committee-size change', async () => {
        const stake = 100;
        const generalCommitteeMinimumWeight = stake;
        const minCommitteeSize = 0;
        const maxCommitteeSize = 2;
        const d = await Driver.new({minCommitteeSize, maxCommitteeSize, generalCommitteeMinimumWeight: generalCommitteeMinimumWeight});

        const v = await d.newParticipant();
        await v.registerAsValidator();
        await v.stake(stake - 1);
        let r = await v.notifyReadyForCommittee();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v.address],
            orbsAddrs: [v.orbsAddress],
        });
        expect(r).to.not.have.a.committeeChangedEvent();

        await d.contractRegistry.set("elections", d.contractsOwner); // hack to make subsequent call
        r = await d.committeeGeneral.setMinimumWeight(stake, ZERO_ADDR, minCommitteeSize + 1);
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [],
            orbsAddrs: [],
        });
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [v.address],
            orbsAddrs: [v.orbsAddress],
        });
    });

    it('leaves committee due to min-committee-size change', async () => {
        const stake = 100;
        const generalCommitteeMinimumWeight = stake;
        const minCommitteeSize = 1;
        const maxCommitteeSize = 2;
        const d = await Driver.new({minCommitteeSize, maxCommitteeSize, generalCommitteeMinimumWeight: generalCommitteeMinimumWeight});

        const v = await d.newParticipant();
        await v.registerAsValidator();
        await v.stake(stake - 1);
        let r = await v.notifyReadyForCommittee();
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [v.address],
            orbsAddrs: [v.orbsAddress],
        });
        expect(r).to.not.have.a.standbysChangedEvent();

        await d.contractRegistry.set("elections", d.contractsOwner); // hack to make subsequent call
        r = await d.committeeGeneral.setMinimumWeight(stake, ZERO_ADDR, minCommitteeSize - 1);
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [],
            orbsAddrs: [],
        });
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v.address],
            orbsAddrs: [v.orbsAddress],
        });
    });

    it('does not join committee due to min-committee-size change if not ready for committee', async () => {
        const stake = 100;
        const generalCommitteeMinimumWeight = 0;
        const minCommitteeSize = 0;
        const maxCommitteeSize = 2;
        const d = await Driver.new({minCommitteeSize, maxCommitteeSize, generalCommitteeMinimumWeight: generalCommitteeMinimumWeight});

        const v = await d.newParticipant();
        await v.registerAsValidator();
        await v.stake(stake);
        let r = await v.notifyReadyToSync();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v.address],
            orbsAddrs: [v.orbsAddress],
        });
        expect(r).to.not.have.a.committeeChangedEvent();

        await d.contractRegistry.set("elections", d.contractsOwner); // hack to make subsequent call
        r = await d.committeeGeneral.setMinimumWeight(0, ZERO_ADDR, minCommitteeSize + 1);
        expect(r).to.not.have.a.standbysChangedEvent();
        expect(r).to.not.have.a.committeeChangedEvent();
    });

    it('allows a validator to overtake a committee member with less stake, even if has less than min weight and joined due to min-committee-size (join committee directly, standbys not full)', async () => {
        const generalCommitteeMinimumWeight = 100;
        const minCommitteeSize = 2;
        const maxCommitteeSize = 4;
        const d = await Driver.new({minCommitteeSize, maxCommitteeSize, generalCommitteeMinimumWeight});

        // Two validators join the committee because of min-committee-size

        let {v: v1, r: r1} = await d.newValidator(generalCommitteeMinimumWeight - 3, false, false, true);
        expect(r1).to.have.a.committeeChangedEvent({
            addrs: [v1.address]
        });

        let {v: v2, r: r2} = await d.newValidator(generalCommitteeMinimumWeight - 2, false, false, true);
        expect(r2).to.have.a.committeeChangedEvent({
            addrs: [v2.address, v1.address]
        });

        // Third validator will overtake the validator with lowest stake which becomes a standby as there are already min-committee-size members

        let {v: v3, r: r3} = await d.newValidator(generalCommitteeMinimumWeight - 1, false, false, true);
        expect(r3).to.have.a.committeeChangedEvent({
            addrs: [v3.address, v2.address]
        });
        expect(r3).to.have.a.standbysChangedEvent({
            addrs: [v1.address]
        });

    });

    it('allows a validator to overtake a committee member with less stake, even if has less than min weight and joined due to min-committee-size (join committee directly, standbys full)', async () => {
        const generalCommitteeMinimumWeight = 100;
        const maxStandbys = 1;
        const minCommitteeSize = 2;
        const maxCommitteeSize = 4;
        const d = await Driver.new({minCommitteeSize, maxCommitteeSize, maxStandbys, generalCommitteeMinimumWeight});

        // Two validators join the committee because of min-committee-size

        let {v: v1, r: r1} = await d.newValidator(generalCommitteeMinimumWeight - 5, false, false, true);
        expect(r1).to.have.a.committeeChangedEvent({
            addrs: [v1.address]
        });

        let {v: v2, r: r2} = await d.newValidator(generalCommitteeMinimumWeight - 4, false, false, true);
        expect(r2).to.have.a.committeeChangedEvent({
            addrs: [v2.address, v1.address]
        });

        // Another becomes standbys, filling the standby list completely
        let {v: v3, r: r3} = await d.newValidator(generalCommitteeMinimumWeight - 1, false, true, false);
        expect(r3).to.not.have.a.committeeChangedEvent();
        expect(r3).to.have.a.standbysChangedEvent({
            addrs: [v3.address]
        });

        // Third validator will overtake the validator with lowest stake which becomes a standby as there are already min-committee-size members

        let {v: v4, r: r4} = await d.newValidator(generalCommitteeMinimumWeight - 3, false, false, true);
        expect(r4).to.have.a.committeeChangedEvent({
            addrs: [v4.address, v2.address]
        });
        expect(r4).to.have.a.standbysChangedEvent({
            addrs: [v3.address]
        });

    });

    it('allows a validator to overtake a committee member with less stake, even if has less than min weight and joined due to min-committee-size (become standby first)', async () => {
        const generalCommitteeMinimumWeight = 100;
        const minCommitteeSize = 2;
        const maxCommitteeSize = 4;
        const d = await Driver.new({minCommitteeSize, maxCommitteeSize, generalCommitteeMinimumWeight});

        // Two validators join the committee because of min-committee-size

        let {v: v1, r: r1} = await d.newValidator(generalCommitteeMinimumWeight - 3, false, false, true);
        expect(r1).to.have.a.committeeChangedEvent({
            addrs: [v1.address]
        });

        let {v: v2, r: r2} = await d.newValidator(generalCommitteeMinimumWeight - 2, false, false, true);
        expect(r2).to.have.a.committeeChangedEvent({
            addrs: [v2.address, v1.address]
        });

        // Third validator will overtake the validator with lowest stake which becomes a standby as there are already min-committee-size members

        let {v: v3, r: r3} = await d.newValidator(generalCommitteeMinimumWeight - 1, false, true, true);
        expect(r3).to.have.a.committeeChangedEvent({
            addrs: [v3.address, v2.address]
        });
        expect(r3).to.have.a.standbysChangedEvent({
            addrs: [v1.address]
        });

    });

    it('returns committee and standbys using getters', async () => {
        const maxStandbys = 2;
        const maxCommitteeSize = 2;
        const d = await Driver.new({maxStandbys, maxCommitteeSize});

        const stake = 100;

        const committee: Participant[] = [];
        for (let i = 0; i < maxCommitteeSize; i++) {
            const v = await d.newParticipant();
            committee.push(v);

            await v.registerAsValidator();
            await v.stake(stake*(maxCommitteeSize - i));
            let r = await v.notifyReadyForCommittee();
            expect(r).to.have.a.committeeChangedEvent({
                addrs: committee.map(s => s.address),
                orbsAddrs: committee.map(s => s.orbsAddress),
            });
            expect(r).to.not.have.a.standbysChangedEvent();
        }

        const standbys: Participant[] = [];
        for (let i = 0; i < maxStandbys; i++) {
            const v = await d.newParticipant();
            standbys.push(v);

            await v.registerAsValidator();
            await v.stake(stake*(maxStandbys - i));
            let r = await v.notifyReadyToSync();
            expect(r).to.have.a.standbysChangedEvent({
                addrs: standbys.map(s => s.address),
                orbsAddrs: standbys.map(s => s.orbsAddress),
            });
            expect(r).to.not.have.a.committeeChangedEvent();
        }

        let r: any = await d.committeeGeneral.getCommittee();
        expect([r[0], r[1]]).to.deep.equal(
            [
                committee.map(v => v.address),
                committee.map((v, i) => (stake * (maxCommitteeSize - i)).toString()),
            ]
        );

        r = await d.committeeGeneral.getCommitteeInfo();
        expect([r[0], r[1], r[2], r[3]]).to.deep.equal(
            [
                committee.map(v => v.address),
                committee.map((v, i) => (stake * (maxCommitteeSize - i)).toString()),
                committee.map(v => v.orbsAddress),
                committee.map(v => v.ip),
            ]
        );

        r = await d.committeeGeneral.getStandbys();
        expect([r[0], r[1]]).to.deep.equal(
            [
                standbys.map(v => v.address),
                standbys.map((v, i) => (stake * (maxStandbys - i)).toString()),
            ]
        );

        r = await d.committeeGeneral.getStandbysInfo();
        expect([r[0], r[1], r[2], r[3]]).to.deep.equal(
            [
                standbys.map(v => v.address),
                standbys.map((v, i) => (stake * (maxStandbys - i)).toString()),
                standbys.map(v => v.orbsAddress),
                standbys.map(v => v.ip),
            ]
        );

    });

    it('returns address of committee member with lowest stake', async () => {
        const maxStandbys = 2;
        const maxCommitteeSize = 2;
        const d = await Driver.new({maxStandbys, maxCommitteeSize});

        const stake = 100;

        const committee: Participant[] = [];
        for (let i = 0; i < maxCommitteeSize; i++) {
            const v = await d.newParticipant();
            committee.push(v);

            await v.registerAsValidator();
            await v.stake(stake*(maxStandbys + maxCommitteeSize - i));
            let r = await v.notifyReadyForCommittee();
            expect(r).to.have.a.committeeChangedEvent({
                addrs: committee.map(s => s.address),
                orbsAddrs: committee.map(s => s.orbsAddress),
            });
            expect(r).to.not.have.a.standbysChangedEvent();
        }

        const standbys: Participant[] = [];
        for (let i = 0; i < maxStandbys; i++) {
            const v = await d.newParticipant();
            standbys.push(v);

            await v.registerAsValidator();
            await v.stake(stake*(maxStandbys - i));
            let r = await v.notifyReadyToSync();
            expect(r).to.have.a.standbysChangedEvent({
                addrs: standbys.map(s => s.address),
                orbsAddrs: standbys.map(s => s.orbsAddress),
            });
            expect(r).to.not.have.a.committeeChangedEvent();
        }

        expect(await d.committeeGeneral.getLowestCommitteeMember()).to.equal(committee[maxCommitteeSize - 1].address);

    });

});
