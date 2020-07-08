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


describe('elections-compliance', async () => {

    it('votes out a compliant committee member when compliant threshold is reached', async () => {
        const voteOutThreshold = 80;
        const maxCommitteeSize = 10;

        const d = await Driver.new({maxCommitteeSize, voteOutThreshold});

        const generalCommittee: Participant[] = [];
        const complianceCommittee: Participant[] = [];
        for (let i = 0; i < maxCommitteeSize; i++) {
            const {v} = await d.newValidator(100, i % 2 == 0, false, true);
            generalCommittee.push(v);
            if (i % 2 == 0) {
                complianceCommittee.push(v);
            }
        }

        let r;
        for (const v of complianceCommittee.slice(1)) {
            r = await d.elections.voteUnready(complianceCommittee[0].address, {from: v.orbsAddress});
        }
        expect(r).to.have.a.validatorVotedUnreadyEvent({
            validator: complianceCommittee[0].address
        });
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: generalCommittee.filter(v => v != complianceCommittee[0]).map(v => v.address)
        });
    });

    it('votes out a compliance committee member from both committees when threshold is reached in general committee but not in compliance committee', async () => {
        const voteOutThreshold = 80;
        const maxCommitteeSize = 10;

        const d = await Driver.new({maxCommitteeSize, voteOutThreshold});

        const generalCommittee: Participant[] = [];
        const complianceCommittee: Participant[] = [];
        for (let i = 0; i < maxCommitteeSize; i++) {
            const {v} = await d.newValidator(i == maxCommitteeSize - 1 ? 100 : 1, i % 2 == 0, false, true);
            if (i % 2 == 0) {
                complianceCommittee.push(v);
            }
            generalCommittee.push(v);
        }

        let r;
        for (const v of generalCommittee.filter((v, i) => i % 2 == 1)) {
            r = await d.elections.voteUnready(complianceCommittee[0].address, {from: v.orbsAddress});
        }
        expect(r).to.have.a.validatorVotedUnreadyEvent({
            validator: complianceCommittee[0].address
        });
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: generalCommittee.slice(1).map(v => v.address)
        });
    });

    it('compliance committee cannot vote out a general committee member', async () => {
        const voteOutThreshold = 80;
        const maxCommitteeSize = 10;

        const d = await Driver.new({maxCommitteeSize, voteOutThreshold});

        const generalCommittee: Participant[] = [];
        const complianceCommittee: Participant[] = [];
        for (let i = 0; i < maxCommitteeSize; i++) {
            const {v} = await d.newValidator(100, i % 2 == 0, false, true);
            if (i % 2 == 0) {
                complianceCommittee.push(v);
            }
            generalCommittee.push(v);
        }

        for (const v of complianceCommittee) {
            let r = await d.elections.voteUnready(generalCommittee[1].address, {from: v.orbsAddress});
            expect(r).to.not.have.a.validatorVotedUnreadyEvent();
            expect(r).to.not.have.a.committeeSnapshotEvent();
        }
    });

});
