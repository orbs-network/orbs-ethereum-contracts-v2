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
    Participant
} from "./driver";
import chai from "chai";
chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const expect = chai.expect;
const assert = chai.assert;

import {bn, evmIncreaseTime} from "./helpers";
import {ETHEREUM_URL} from "../eth";


describe('committee', async () => {

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
        await v.stake(stake);
        let r = await v.notifyReadyForCommittee();
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v.address]
        });
    });

    it('standby can overtake committee member with more stake', async () => {
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
        let r = await v.notifyReadyForCommittee();
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [v.address]
        });

        r = await v.stake(stake);
        expect(r).to.have.a.committeeChangedEvent({
            addrs: [v].concat(committee.slice(0, committee.length - 1)).map(s => s.address),
        });
        expect(r).to.have.a.standbysChangedEvent({
            addrs: [committee[committee.length - 1].address],
        });

    });

    it('non-committe-ready standby cannot overtake committee member with more stake', async () => {
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

    it('non-ready-for-committee with more stake can overtake a ready-for-committee standby', async () => {
        const d = await Driver.new();

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

        for (let i = 0; i < defaultDriverOptions.maxStandbys; i++) {
            const v = await d.newParticipant();
            standbys.push(v);

            await v.registerAsValidator();
            await v.stake(i == 0 ? stake: stake * 2);
            let r = i == 0 ? await v.notifyReadyForCommittee() : await v.notifyReadyToSync();
            expect(r).to.have.a.standbysChangedEvent({
                addrs: standbys.map(s => s.address),
                orbsAddrs: standbys.map(s => s.orbsAddress),
            });
            expect(r).to.not.have.a.committeeChangedEvent();
        }

        const v = await d.newParticipant();
        await v.registerAsValidator();
        await v.stake(1);
        let r = await v.notifyReadyToSync();
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.not.have.a.standbysChangedEvent();

        r = await v.stake(stake);
        expect(r).to.not.have.a.committeeChangedEvent();
        expect(r).to.have.a.standbysChangedEvent({
            addrs: standbys.slice(1, standbys.length).concat([v]).map(v => v.address),
        });

    });

});
