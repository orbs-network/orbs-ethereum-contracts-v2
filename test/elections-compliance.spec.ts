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

import {bn, evmIncreaseTime, minAddress} from "./helpers";
import {ETHEREUM_URL} from "../eth";
import {
    banningScenario_setupDelegatorsAndValidators,
    banningScenario_voteUntilThresholdReached
} from "./elections.spec";


// describe('elections-compliance', async () => {
//
//     it('adds members/standbys to committees according to compliance', async () => {
//         const maxCommitteeSize = 10;
//         const maxStandbys = 10;
//         const d = await Driver.new({maxCommitteeSize, maxStandbys});
//
//         const stake = 100;
//
//         const committee: Participant[] = [];
//         for (let i = 0; i < maxCommitteeSize; i++) {
//             const {v, r} = await d.newValidator(stake + i, i % 2 == 0, false, true);
//             committee.push(v);
//             expect(r).to.have.withinContract(d.committee).a.committeeChangedEvent({
//                 addrs: committee.map(s => s.address),
//             });
//             if (i % 2 == 0){
//                 expect(r).to.have.withinContract(d.committeeCompliance).a.committeeChangedEvent({
//                     addrs: committee.filter((v, i) => i % 2 == 0).map(s => s.address),
//                 });
//             }
//             expect(r).to.not.have.a.standbysChangedEvent();
//         }
//
//         const standbys: Participant[] = [];
//         for (let i = 0; i < maxStandbys; i++) {
//             const {v, r} = await d.newValidator(stake - i - 1, i % 2 == 0, false, true);
//             standbys.push(v);
//
//             expect(r).to.have.withinContract(d.committee).a.standbysChangedEvent({
//                 addrs: standbys.map(s => s.address),
//             });
//             if (i % 2 == 0){
//                 expect(r).to.have.withinContract(d.committeeCompliance).a.standbysChangedEvent({
//                     addrs: standbys.filter((v, i) => i % 2 == 0).map(s => s.address),
//                 });
//             }
//             expect(r).to.not.have.a.committeeChangedEvent();
//         }
//     });
//
//     it('uses address as tie-breaker when stakes are equal', async () => {
//         const maxCommitteeSize = 10;
//         const maxStandbys = 10;
//         const d = await Driver.new({maxCommitteeSize, maxStandbys});
//
//         const stake = 100;
//
//         const validators = _.range(maxCommitteeSize + 1).map(() => d.newParticipant());
//         const standby = validators.find(x => x.address == minAddress(validators.map(x => x.address))) as Participant;
//         const committee = validators.filter(x => x != standby);
//         for (let i = 0; i < maxCommitteeSize; i++) {
//             const v = committee[i];
//             let r = await v.becomeValidator(stake, i % 2 == 0, false, true);
//             const committeeSoFar = committee.slice(0, i + 1);
//             expect(r).to.have.withinContract(d.committee).a.committeeChangedEvent({
//                 addrs: committeeSoFar.map(s => s.address),
//             });
//             if (i % 2 == 0){
//                 expect(r).to.have.withinContract(d.committeeCompliance).a.committeeChangedEvent({
//                     addrs: committeeSoFar.filter((v, i) => i % 2 == 0).map(s => s.address),
//                 });
//             }
//             expect(r).to.not.have.a.standbysChangedEvent();
//         }
//
//         let r = await standby.becomeValidator(stake, true, false, true);
//         expect(r).to.not.have.committeeChangedEvent();
//         expect(r).to.have.withinContract(d.committee).a.standbysChangedEvent({
//             addrs: [standby.address],
//             orbsAddrs: [standby.orbsAddress],
//             weights: [bn(stake)]
//         });
//         expect(r).to.have.withinContract(d.committeeCompliance).a.standbysChangedEvent({
//             addrs: [standby.address],
//             orbsAddrs: [standby.orbsAddress],
//             weights: [bn(stake)]
//         });
//     });
//
//     it('joins compliance committee on compliance change', async () => {
//         const maxCommitteeSize = 10;
//         const maxStandbys = 10;
//         const d = await Driver.new({maxCommitteeSize, maxStandbys});
//
//         const stake = 100;
//
//         const committee: Participant[] = [];
//         for (let i = 0; i < maxCommitteeSize; i++) {
//             const {v, r} = await d.newValidator(stake, false, false, true);
//             committee.push(v);
//             expect(r).to.have.withinContract(d.committee).a.committeeChangedEvent({
//                 addrs: committee.map(s => s.address),
//             });
//             expect(r).to.not.have.withinContract(d.committeeCompliance).a.committeeChangedEvent();
//             expect(r).to.not.have.a.standbysChangedEvent();
//         }
//
//         await committee[0].becomeCompliant();
//         let r = await committee[0].notifyReadyForCommittee();
//         expect(r).to.have.withinContract(d.committeeCompliance).a.committeeChangedEvent({
//             addrs: [committee[0].address],
//         });
//         expect(r).to.have.withinContract(d.committee).a.committeeChangedEvent({
//             addrs: committee.map(s => s.address),
//         });
//         expect(r).to.not.have.a.standbysChangedEvent();
//     });
//
//     it('leaves compliance committee on compliance change', async () => {
//         const maxCommitteeSize = 10;
//         const maxStandbys = 10;
//         const d = await Driver.new({maxCommitteeSize, maxStandbys});
//
//         const stake = 100;
//
//         const committee: Participant[] = [];
//         for (let i = 0; i < maxCommitteeSize; i++) {
//             const {v, r} = await d.newValidator(stake, true, false, true);
//             committee.push(v);
//             expect(r).to.have.withinContract(d.committee).a.committeeChangedEvent({
//                 addrs: committee.map(s => s.address),
//             });
//             expect(r).to.have.withinContract(d.committeeCompliance).a.committeeChangedEvent({
//                 addrs: committee.map(s => s.address),
//             });
//             expect(r).to.not.have.a.standbysChangedEvent();
//         }
//
//         let r = await committee[0].becomeNotCompliant();
//         expect(r).to.have.withinContract(d.committeeCompliance).a.committeeChangedEvent({
//             addrs: committee.slice(1).map(s => s.address),
//         });
//         expect(r).to.not.have.withinContract(d.committee).a.committeeChangedEvent();
//         expect(r).to.not.have.a.standbysChangedEvent();
//     });
//
//     it('leaves all committees when banned', async () => {
//         const d = await Driver.new();
//
//         let {delegatees, bannedValidator, thresholdCrossingIndex} = await banningScenario_setupDelegatorsAndValidators(d);
//
//         await bannedValidator.becomeCompliant();
//         let r = await bannedValidator.notifyReadyForCommittee();
//         expect(r).to.have.withinContract(d.committeeCompliance).a.committeeChangedEvent({
//             addrs: [bannedValidator.address]
//         });
//
//         r = await banningScenario_voteUntilThresholdReached(d, thresholdCrossingIndex, delegatees, bannedValidator);
//         expect(r).to.have.withinContract(d.committeeCompliance).a.committeeChangedEvent({
//             addrs: []
//         });
//         expect(r).to.have.withinContract(d.committee).a.committeeChangedEvent({
//             addrs: []
//         });
//
//     });
//
//     it('can join all committees when unbanned', async () => {
//         const d = await Driver.new();
//
//         let {delegatees, bannedValidator, thresholdCrossingIndex} = await banningScenario_setupDelegatorsAndValidators(d);
//
//         await bannedValidator.becomeCompliant();
//         let r = await bannedValidator.notifyReadyForCommittee();
//         expect(r).to.have.withinContract(d.committeeCompliance).a.committeeChangedEvent({
//             addrs: [bannedValidator.address]
//         });
//
//         r = await banningScenario_voteUntilThresholdReached(d, thresholdCrossingIndex, delegatees, bannedValidator);
//         expect(r).to.have.withinContract(d.committeeCompliance).a.committeeChangedEvent({
//             addrs: []
//         });
//         expect(r).to.have.withinContract(d.committee).a.committeeChangedEvent({
//             addrs: []
//         });
//
//         r = await d.elections.setBanningVotes([], {from: delegatees[thresholdCrossingIndex].address});
//         expect(r).to.have.a.unbannedEvent({
//            validator: bannedValidator.address
//         });
//
//         r = await bannedValidator.notifyReadyForCommittee();
//         expect(r).to.have.withinContract(d.committee).a.committeeChangedEvent({
//             addrs: [bannedValidator.address]
//         });
//         expect(r).to.have.withinContract(d.committee).a.committeeChangedEvent({
//             addrs: [bannedValidator.address]
//         });
//     });
//
//     it('votes out a compliance committee member from both committees when threshold is reached in compliance committee', async () => {
//         const voteOutThreshold = 80;
//         const maxCommitteeSize = 10;
//
//         const d = await Driver.new({maxCommitteeSize, voteOutThreshold});
//
//         const generalCommittee: Participant[] = [];
//         const complianceCommittee: Participant[] = [];
//         for (let i = 0; i < maxCommitteeSize; i++) {
//             const {v} = await d.newValidator(100, i % 2 == 0, false, true);
//             generalCommittee.push(v);
//             if (i % 2 == 0) {
//                 complianceCommittee.push(v);
//             }
//         }
//
//         let r;
//         for (const v of complianceCommittee.slice(1)) {
//             r = await d.elections.voteOut(complianceCommittee[0].address, {from: v.orbsAddress});
//         }
//         expect(r).to.have.a.votedOutOfCommitteeEvent({
//             addr: complianceCommittee[0].address
//         });
//         expect(r).to.have.withinContract(d.committeeCompliance).a.committeeChangedEvent({
//             addrs: complianceCommittee.slice(1).map(v => v.address)
//         });
//         expect(r).to.have.withinContract(d.committee).a.committeeChangedEvent({
//             addrs: generalCommittee.slice(1).map(v => v.address)
//         });
//         expect(r).to.not.have.a.standbysChangedEvent();
//     });
//
//     it('votes out a compliance committee member from both committees when threshold is reached in general committee but not in compliance committee', async () => {
//         const voteOutThreshold = 80;
//         const maxCommitteeSize = 10;
//
//         const d = await Driver.new({maxCommitteeSize, voteOutThreshold});
//
//         const generalCommittee: Participant[] = [];
//         const complianceCommittee: Participant[] = [];
//         for (let i = 0; i < maxCommitteeSize; i++) {
//             const {v} = await d.newValidator(i == maxCommitteeSize - 1 ? 100 : 1, i % 2 == 0, false, true);
//             if (i % 2 == 0) {
//                 complianceCommittee.push(v);
//             }
//             generalCommittee.push(v);
//         }
//
//         let r;
//         for (const v of generalCommittee.filter((v, i) => i % 2 == 1)) {
//             r = await d.elections.voteOut(complianceCommittee[0].address, {from: v.orbsAddress});
//         }
//         expect(r).to.have.a.votedOutOfCommitteeEvent({
//             addr: complianceCommittee[0].address
//         });
//         expect(r).to.have.withinContract(d.committeeCompliance).a.committeeChangedEvent({
//             addrs: complianceCommittee.slice(1).map(v => v.address)
//         });
//         expect(r).to.have.withinContract(d.committee).a.committeeChangedEvent({
//             addrs: generalCommittee.slice(1).map(v => v.address)
//         });
//         expect(r).to.not.have.a.standbysChangedEvent();
//     });
//
//     it('compliance committee cannot vote out a general committee member', async () => {
//         const voteOutThreshold = 80;
//         const maxCommitteeSize = 10;
//
//         const d = await Driver.new({maxCommitteeSize, voteOutThreshold});
//
//         const generalCommittee: Participant[] = [];
//         const complianceCommittee: Participant[] = [];
//         for (let i = 0; i < maxCommitteeSize; i++) {
//             const {v} = await d.newValidator(100, i % 2 == 0, false, true);
//             if (i % 2 == 0) {
//                 complianceCommittee.push(v);
//             }
//             generalCommittee.push(v);
//         }
//
//         for (const v of complianceCommittee) {
//             let r = await d.elections.voteOut(generalCommittee[1].address, {from: v.orbsAddress});
//             expect(r).to.not.have.a.votedOutOfCommitteeEvent();
//             expect(r).to.not.have.a.committeeChangedEvent();
//             expect(r).to.not.have.a.standbysChangedEvent();
//         }
//     });
//
// });
