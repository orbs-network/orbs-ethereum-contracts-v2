import 'mocha';

import Web3 from "web3";
declare const web3: Web3;

import BN from "bn.js";
import {
    Driver,
    Participant
} from "./driver";
import chai from "chai";
import {bn} from "./helpers";
chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const expect = chai.expect;


describe('elections-certification', async () => {

    it('votes out a certified committee member when certified threshold is reached', async () => {
        const voteUnreadyThresholdPercentMille = 80 * 1000;
        const maxCommitteeSize = 10;

        const d = await Driver.new({maxCommitteeSize, voteUnreadyThresholdPercentMille});

        const generalCommittee: Participant[] = [];
        const certifiedCommittee: Participant[] = [];
        const committeeData: any = {};
        for (let i = 0; i < maxCommitteeSize; i++) {
            const {v} = await d.newGuardian(100, i % 2 == 0, false, true);
            generalCommittee.push(v);
            if (i % 2 == 0) {
                certifiedCommittee.push(v);
            }
            committeeData[v.address] = {
                v,
                stake: bn(100),
                certified: i % 2 == 0
            }
        }

        let r;
        for (const v of certifiedCommittee.slice(1)) {
            r = await d.elections.voteUnready(certifiedCommittee[0].address, 0xFFFFFFFF, {from: v.orbsAddress});
        }
        expect(r).to.have.a.guardianVotedUnreadyEvent({
            guardian: certifiedCommittee[0].address
        });
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: generalCommittee.filter(v => v != certifiedCommittee[0]).map(v => v.address)
        });

        const status = await d.elections.getVoteUnreadyStatus(certifiedCommittee[0].address);
        expect(status.committee.length).to.eq(generalCommittee.length - 1);
        for (let i = 0; i < status.committee.length; i++) {
            const data = committeeData[status.committee[i]];
            expect(status.weights[i]).to.bignumber.eq(data.stake);
            expect(status.votes[i]).to.be.false;
            expect(status.certification[i]).to.eq(data.certified);
            expect(status.subjectInCommittee).to.be.false;
            expect(status.subjectInCertifiedCommittee).to.be.false;
        }

    });

    it('votes out a certification committee member from both committees when threshold is reached in general committee but not in certification committee', async () => {
        const voteUnreadyThresholdPercentMille = 80 * 1000;
        const maxCommitteeSize = 10;

        const d = await Driver.new({maxCommitteeSize, voteUnreadyThresholdPercentMille});

        const generalCommittee: Participant[] = [];
        const certifiedCommittee: Participant[] = [];
        for (let i = 0; i < maxCommitteeSize; i++) {
            const {v} = await d.newGuardian(i == maxCommitteeSize - 1 ? 100 : 1, i % 2 == 0, false, true);
            if (i % 2 == 0) {
                certifiedCommittee.push(v);
            }
            generalCommittee.push(v);
        }

        let r;
        for (const v of generalCommittee.filter((v, i) => i % 2 == 1)) {
            r = await d.elections.voteUnready(certifiedCommittee[0].address, 0xFFFFFFFF, {from: v.orbsAddress});
        }
        expect(r).to.have.a.guardianVotedUnreadyEvent({
            guardian: certifiedCommittee[0].address
        });
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: generalCommittee.slice(1).map(v => v.address)
        });
    });

    it('certification committee cannot vote out a general committee member', async () => {
        const voteUnreadyThresholdPercentMille = 80 * 1000;
        const maxCommitteeSize = 10;

        const d = await Driver.new({maxCommitteeSize, voteUnreadyThresholdPercentMille});

        const generalCommittee: Participant[] = [];
        const certifiedCommittee: Participant[] = [];
        for (let i = 0; i < maxCommitteeSize; i++) {
            const {v} = await d.newGuardian(100, i % 2 == 0, false, true);
            if (i % 2 == 0) {
                certifiedCommittee.push(v);
            }
            generalCommittee.push(v);
        }

        for (const v of certifiedCommittee) {
            let r = await d.elections.voteUnready(generalCommittee[1].address, 0xFFFFFFFF, {from: v.orbsAddress});
            expect(r).to.not.have.a.guardianVotedUnreadyEvent();
            expect(r).to.not.have.a.committeeSnapshotEvent();
        }
    });

});
