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


describe('elections-compliance', async () => {

    it('adds members/standbys to committees according to compliance', async () => {
        const maxCommitteeSize = 10;
        const maxStandbys = 10;
        const d = await Driver.new({maxCommitteeSize, maxStandbys});

        const stake = 100;

        const committee: Participant[] = [];
        const committeeStakes: number[] = [];
        for (let i = 0; i < maxCommitteeSize; i++) {
            const v = await d.newParticipant();
            committee.push(v);

            await v.registerAsValidator();
            if (i % 2 == 0) {
                await v.becomeComplianceType();
            }
            await v.stake(stake + i);
            committeeStakes.push(stake + i);

            let r = await v.notifyReadyForCommittee();
            expect(r).to.have.withinContract(d.committeeGeneral).a.committeeChangedEvent({
                addrs: committee.map(s => s.address),
                orbsAddrs: committee.map(s => s.orbsAddress),
                weights: committeeStakes.map(bn)
            });
            if (i % 2 == 0){
                expect(r).to.have.withinContract(d.committeeCompliance).a.committeeChangedEvent({
                    addrs: committee.filter((v, i) => i % 2 == 0).map(s => s.address),
                    orbsAddrs: committee.filter((v, i) => i % 2 == 0).map(s => s.orbsAddress),
                    weights: committeeStakes.filter((v, i) => i % 2 == 0).map(bn)
                });
            }
            expect(r).to.not.have.a.standbysChangedEvent();
        }

        const standbys: Participant[] = [];
        const standbysStakes: number[] = [];
        for (let i = 0; i < maxStandbys; i++) {
            const v = await d.newParticipant();
            standbys.push(v);

            await v.registerAsValidator();
            if (i % 2 == 0) {
                await v.becomeComplianceType();
            }
            await v.stake(stake - i - 1);
            standbysStakes.push(stake - i - 1);
            let r = await v.notifyReadyForCommittee();
            expect(r).to.have.withinContract(d.committeeGeneral).a.standbysChangedEvent({
                addrs: standbys.map(s => s.address),
                orbsAddrs: standbys.map(s => s.orbsAddress),
                weights: standbysStakes.map(bn)
            });
            if (i % 2 == 0){
                expect(r).to.have.withinContract(d.committeeCompliance).a.standbysChangedEvent({
                    addrs: standbys.filter((v, i) => i % 2 == 0).map(s => s.address),
                    orbsAddrs: standbys.filter((v, i) => i % 2 == 0).map(s => s.orbsAddress),
                    weights: standbysStakes.filter((v, i) => i % 2 == 0).map(bn)
                });
            }
            expect(r).to.not.have.a.committeeChangedEvent();
        }
    });

    it('uses address as tie-breaker when stakes are equal', async () => {
        const maxCommitteeSize = 10;
        const maxStandbys = 10;
        const d = await Driver.new({maxCommitteeSize, maxStandbys});

        const stake = 100;

        const validators = _.range(maxCommitteeSize + 1).map(() => d.newParticipant());
        const standby = validators.find(x => x.address == minAddress(validators.map(x => x.address))) as Participant;
        const committee = validators.filter(x => x != standby);
        for (let i = 0; i < maxCommitteeSize; i++) {
            const v = committee[i];
            await v.registerAsValidator();
            if (i % 2 == 0) {
                await v.becomeComplianceType();
            }
            await v.stake(stake);
            let r = await v.notifyReadyForCommittee();
            const committeeSoFar = committee.slice(0, i + 1);
            expect(r).to.have.withinContract(d.committeeGeneral).a.committeeChangedEvent({
                addrs: committeeSoFar.map(s => s.address),
                orbsAddrs: committeeSoFar.map(s => s.orbsAddress),
                weights: committeeSoFar.map(s => bn(stake))
            });
            if (i % 2 == 0){
                expect(r).to.have.withinContract(d.committeeCompliance).a.committeeChangedEvent({
                    addrs: committeeSoFar.filter((v, i) => i % 2 == 0).map(s => s.address),
                    orbsAddrs: committeeSoFar.filter((v, i) => i % 2 == 0).map(s => s.orbsAddress),
                    weights: committeeSoFar.filter((v, i) => i % 2 == 0).map(() => bn(stake))
                });
            }
            expect(r).to.not.have.a.standbysChangedEvent();
        }

        await standby.registerAsValidator();
        await standby.becomeComplianceType();
        await standby.stake(stake);
        let r = await standby.notifyReadyForCommittee();
        expect(r).to.not.have.committeeChangedEvent();
        expect(r).to.have.withinContract(d.committeeGeneral).a.standbysChangedEvent({
            addrs: [standby.address],
            orbsAddrs: [standby.orbsAddress],
            weights: [bn(stake)]
        });
        expect(r).to.have.withinContract(d.committeeCompliance).a.standbysChangedEvent({
            addrs: [standby.address],
            orbsAddrs: [standby.orbsAddress],
            weights: [bn(stake)]
        });
    });

    it('joins compliance committee on compliance change', async () => {
        const maxCommitteeSize = 10;
        const maxStandbys = 10;
        const d = await Driver.new({maxCommitteeSize, maxStandbys});

        const stake = 100;

        const committee: Participant[] = [];
        for (let i = 0; i < maxCommitteeSize; i++) {
            const v = d.newParticipant();
            committee.push(v);
            await v.registerAsValidator();
            await v.stake(stake);
            let r = await v.notifyReadyForCommittee();
            expect(r).to.have.withinContract(d.committeeGeneral).a.committeeChangedEvent({
                addrs: committee.map(s => s.address),
                orbsAddrs: committee.map(s => s.orbsAddress),
                weights: committee.map(s => bn(stake))
            });
            expect(r).to.not.have.withinContract(d.committeeCompliance).a.committeeChangedEvent();
            expect(r).to.not.have.a.standbysChangedEvent();
        }

        await committee[0].becomeComplianceType();
        let r = await committee[0].notifyReadyForCommittee();
        expect(r).to.have.withinContract(d.committeeCompliance).a.committeeChangedEvent({
            addrs: [committee[0].address],
            orbsAddrs: [committee[0].orbsAddress],
            weights: [bn(stake)]
        });
        expect(r).to.have.withinContract(d.committeeGeneral).a.committeeChangedEvent({
            addrs: committee.map(s => s.address),
            orbsAddrs: committee.map(s => s.orbsAddress),
            weights: committee.map(s => bn(stake))
        });
        expect(r).to.not.have.a.standbysChangedEvent();
    });

    it('leaves compliance committee on compliance change', async () => {
        const maxCommitteeSize = 10;
        const maxStandbys = 10;
        const d = await Driver.new({maxCommitteeSize, maxStandbys});

        const stake = 100;

        const committee: Participant[] = [];
        for (let i = 0; i < maxCommitteeSize; i++) {
            const v = d.newParticipant();
            committee.push(v);
            await v.becomeComplianceType();
            await v.registerAsValidator();
            await v.stake(stake);
            let r = await v.notifyReadyForCommittee();
            expect(r).to.have.withinContract(d.committeeGeneral).a.committeeChangedEvent({
                addrs: committee.map(s => s.address),
                orbsAddrs: committee.map(s => s.orbsAddress),
                weights: committee.map(s => bn(stake))
            });
            expect(r).to.have.withinContract(d.committeeCompliance).a.committeeChangedEvent({
                addrs: committee.map(s => s.address),
                orbsAddrs: committee.map(s => s.orbsAddress),
                weights: committee.map(s => bn(stake))
            });
            expect(r).to.not.have.a.standbysChangedEvent();
        }

        let r = await committee[0].becomeGeneralType();
        expect(r).to.have.withinContract(d.committeeCompliance).a.committeeChangedEvent({
            addrs: committee.slice(1).map(s => s.address),
            orbsAddrs: committee.slice(1).map(s => s.orbsAddress),
            weights: committee.slice(1).map(s => bn(stake))
        });
        expect(r).to.not.have.withinContract(d.committeeGeneral).a.committeeChangedEvent();
        expect(r).to.not.have.a.standbysChangedEvent();
    });

    it('leaves all committees when banned', async () => {
        const d = await Driver.new();

        let {delegatees, bannedValidator, thresholdCrossingIndex} = await banningScenario_setupDelegatorsAndValidators(d);

        await bannedValidator.becomeComplianceType();
        let r = await bannedValidator.notifyReadyForCommittee();
        expect(r).to.have.withinContract(d.committeeCompliance).a.committeeChangedEvent({
            addrs: [bannedValidator.address]
        });

        r = await banningScenario_voteUntilThresholdReached(d, thresholdCrossingIndex, delegatees, bannedValidator);
        expect(r).to.have.withinContract(d.committeeCompliance).a.committeeChangedEvent({
            addrs: []
        });
        expect(r).to.have.withinContract(d.committeeGeneral).a.committeeChangedEvent({
            addrs: []
        });

    })
});
