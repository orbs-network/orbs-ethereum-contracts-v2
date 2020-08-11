import 'mocha';

import Web3 from "web3";
declare const web3: Web3;

import BN from "bn.js";
import {
    Driver,
    Participant
} from "./driver";
import chai from "chai";
chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const expect = chai.expect;


describe('elections-certification', async () => {

    it('votes out a certified committee member when certified threshold is reached', async () => {
        const voteUnreadyThreshold = 80;
        const maxCommitteeSize = 10;

        const d = await Driver.new({maxCommitteeSize, voteUnreadyThreshold});

        const generalCommittee: Participant[] = [];
        const certificationCommittee: Participant[] = [];
        for (let i = 0; i < maxCommitteeSize; i++) {
            const {v} = await d.newGuardian(100, i % 2 == 0, false, true);
            generalCommittee.push(v);
            if (i % 2 == 0) {
                certificationCommittee.push(v);
            }
        }

        let r;
        for (const v of certificationCommittee.slice(1)) {
            r = await d.elections.voteUnready(certificationCommittee[0].address, {from: v.orbsAddress});
        }
        expect(r).to.have.a.guardianVotedUnreadyEvent({
            guardian: certificationCommittee[0].address
        });
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: generalCommittee.filter(v => v != certificationCommittee[0]).map(v => v.address)
        });
    });

    it('votes out a certification committee member from both committees when threshold is reached in general committee but not in certification committee', async () => {
        const voteUnreadyThreshold = 80;
        const maxCommitteeSize = 10;

        const d = await Driver.new({maxCommitteeSize, voteUnreadyThreshold});

        const generalCommittee: Participant[] = [];
        const certificationCommittee: Participant[] = [];
        for (let i = 0; i < maxCommitteeSize; i++) {
            const {v} = await d.newGuardian(i == maxCommitteeSize - 1 ? 100 : 1, i % 2 == 0, false, true);
            if (i % 2 == 0) {
                certificationCommittee.push(v);
            }
            generalCommittee.push(v);
        }

        let r;
        for (const v of generalCommittee.filter((v, i) => i % 2 == 1)) {
            r = await d.elections.voteUnready(certificationCommittee[0].address, {from: v.orbsAddress});
        }
        expect(r).to.have.a.guardianVotedUnreadyEvent({
            guardian: certificationCommittee[0].address
        });
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: generalCommittee.slice(1).map(v => v.address)
        });
    });

    it('certification committee cannot vote out a general committee member', async () => {
        const voteUnreadyThreshold = 80;
        const maxCommitteeSize = 10;

        const d = await Driver.new({maxCommitteeSize, voteUnreadyThreshold});

        const generalCommittee: Participant[] = [];
        const certificationCommittee: Participant[] = [];
        for (let i = 0; i < maxCommitteeSize; i++) {
            const {v} = await d.newGuardian(100, i % 2 == 0, false, true);
            if (i % 2 == 0) {
                certificationCommittee.push(v);
            }
            generalCommittee.push(v);
        }

        for (const v of certificationCommittee) {
            let r = await d.elections.voteUnready(generalCommittee[1].address, {from: v.orbsAddress});
            expect(r).to.not.have.a.guardianVotedUnreadyEvent();
            expect(r).to.not.have.a.committeeSnapshotEvent();
        }
    });

});
