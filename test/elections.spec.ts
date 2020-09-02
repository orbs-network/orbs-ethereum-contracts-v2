import 'mocha';

import BN from "bn.js";
import {
    defaultDriverOptions,
    BANNING_LOCK_TIMEOUT,
    Driver,
    Participant, ZERO_ADDR
} from "./driver";
import chai from "chai";
chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const expect = chai.expect;
const assert = chai.assert;

import {bn, evmIncreaseTime, expectRejected, fromTokenUnits} from "./helpers";

const baseStake = 100;

describe('elections-high-level-flows', async () => {

    it('emits events on readyForCommittee and readyToSync', async () => {
        const d = await Driver.new();

        const {v} = await d.newGuardian(fromTokenUnits(10), false, false, false);

        let r = await v.readyToSync();
        expect(r).to.have.a.guardianStatusUpdatedEvent({
            addr: v.address,
            readyToSync: true,
            readyForCommittee: false
        });

        r = await v.readyForCommittee();
        expect(r).to.have.a.guardianStatusUpdatedEvent({
            addr: v.address,
            readyToSync: true,
            readyForCommittee: true
        });
    });

    it('allows sending readyForCommittee and readyToSync form both guardian and orbs address', async () => {
        const d = await Driver.new();

        const {v} = await d.newGuardian(fromTokenUnits(10), false, false, false);

        let r = await d.elections.readyToSync({from: v.orbsAddress});
        expect(r).to.have.a.guardianStatusUpdatedEvent({
            addr: v.address,
            readyToSync: true,
            readyForCommittee: false
        });

        r = await d.elections.readyToSync({from: v.address});
        expect(r).to.have.a.guardianStatusUpdatedEvent({
            addr: v.address,
            readyToSync: true,
            readyForCommittee: false
        });

        r = await d.elections.readyForCommittee({from: v.orbsAddress});
        expect(r).to.have.a.guardianStatusUpdatedEvent({
            addr: v.address,
            readyToSync: true,
            readyForCommittee: true
        });

        r = await d.elections.readyForCommittee({from: v.address});
        expect(r).to.have.a.guardianStatusUpdatedEvent({
            addr: v.address,
            readyToSync: true,
            readyForCommittee: true
        });
    });

    it('rejects readyForCommittee and readyToSync from an unregistered guardian', async () => {
        const d = await Driver.new();

        const v = d.newParticipant();

        await expectRejected(d.elections.readyToSync({from: v.address}), /Cannot resolve address/);
        await expectRejected(d.elections.readyForCommittee({from: v.address}), /Cannot resolve address/);
    });

    it('handle delegation requests', async () => {
        const d = await Driver.new();

        const d1 = await d.newParticipant();
        const d2 = await d.newParticipant();

        const r = await d1.delegate(d2);
        expect(r).to.have.a.delegatedEvent({
            from: d1.address,
            to: d2.address
        });
    });

    it('sorts committee by stake', async () => {
        const stake100 = new BN(100);
        const stake200 = new BN(200);
        const stake300 = new BN(300);
        const stake500 = new BN(500);
        const stake1000 = new BN(1000);

        const d = await Driver.new({maxCommitteeSize: 2});

        // First guardian registers
        const guardianStaked100 = d.newParticipant();
        let r = await guardianStaked100.stake(stake100);
        expect(r).to.have.a.stakedEvent();

        await guardianStaked100.registerAsGuardian();
        r = await guardianStaked100.readyToSync();

        r = await guardianStaked100.readyForCommittee();
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: [guardianStaked100.address],
            weights: [stake100],
        });

        const guardianStaked200 = d.newParticipant();
        r = await guardianStaked200.stake(stake200);
        expect(r).to.have.a.stakeChangedEvent({addr: guardianStaked200.address, effective_stake: stake200});

        await guardianStaked200.registerAsGuardian();
        await guardianStaked200.readyToSync();
        r = await guardianStaked200.readyForCommittee();
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: [guardianStaked200.address, guardianStaked100.address],
            weights: [stake200, stake100]
        });

        // A third guardian registers high ranked

        const guardianStaked300 = d.newParticipant();
        r = await guardianStaked300.stake(stake300);
        expect(r).to.have.a.stakedEvent();

        await guardianStaked300.registerAsGuardian();

        r = await guardianStaked300.readyToSync();
        r = await guardianStaked300.readyForCommittee();
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: [guardianStaked300.address, guardianStaked200.address],
            weights: [stake300, stake200]
        });

        r = await d.delegateMoreStake(stake300, guardianStaked200);
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: [guardianStaked200.address, guardianStaked300.address],
            weights: [stake200.add(stake300), stake300]
        });

        r = await d.delegateMoreStake(stake500, guardianStaked100);
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: [guardianStaked100.address, guardianStaked200.address],
            weights: [stake100.add(stake500), stake500]
        });

        // A new guardian registers, stakes and enters the topology

        const inTopologyGuardian = d.newParticipant();
        r = await inTopologyGuardian.stake(stake100);
        expect(r).to.have.a.stakedEvent();
        await inTopologyGuardian.registerAsGuardian();
        r = await inTopologyGuardian.readyToSync();
        r = await inTopologyGuardian.readyForCommittee();
        expect(r).to.not.have.a.committeeSnapshotEvent();

        // The bottom guardian in the topology delegates more stake and switches places with the second to last
        r = await d.delegateMoreStake(201, inTopologyGuardian);

        // A new guardian registers and stakes but does not enter the topology
        const outOfTopologyGuardian = d.newParticipant();
        r = await outOfTopologyGuardian.stake(stake100);
        expect(r).to.have.a.stakedEvent();
        await outOfTopologyGuardian.registerAsGuardian();
        await outOfTopologyGuardian.readyToSync();
        r = await outOfTopologyGuardian.readyForCommittee();
        expect(r).to.not.have.a.committeeSnapshotEvent();

        // A new guardian stakes enough to get to the top
        const guardian = d.newParticipant();
        await guardian.registerAsGuardian();
        await guardian.readyForCommittee();
        r = await guardian.stake(stake1000); // now top of committee
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: [guardian.address, guardianStaked100.address],
            weights: [stake1000, stake100.add(stake500)]
        });
    });

    it('VoteUnready: votes out a committee member', async () => {
        assert(defaultDriverOptions.voteUnreadyThresholdPercentMille < (98 * 1000)); // so each committee member will hold a positive stake
        assert(Math.floor(defaultDriverOptions.voteUnreadyThresholdPercentMille / 2) >= (98 * 1000) - defaultDriverOptions.voteUnreadyThresholdPercentMille); // so the committee list will be ordered by stake

        const stakesPercentage = [
            Math.ceil(defaultDriverOptions.voteUnreadyThresholdPercentMille / 1000 / 2),
            Math.floor(defaultDriverOptions.voteUnreadyThresholdPercentMille / 1000 / 2),
            98 - defaultDriverOptions.voteUnreadyThresholdPercentMille / 1000,
            1,
            1
        ];
        const committeeSize = stakesPercentage.length;
        const thresholdCrossingIndex = 1;

        const d = await Driver.new({maxCommitteeSize: committeeSize,});

        let r;
        const committee: Participant[] = [];
        for (const p of stakesPercentage) {
            const v = d.newParticipant();
            await v.registerAsGuardian();
            await v.readyForCommittee();
            r = await v.stake(baseStake * p);
            committee.push(v);
        }
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: committee.map(v => v.address)
        });

        // A committee member is voted out, rejoins, and voted-out again. This makes sure that once voted-out, the
        // votes are discarded and must be recast to vote-out a guardian again.
        for (let i = 0; i < 2; i++) {
            // Part of the committee votes out, threshold is not yet reached
            const votedOutGuardian = committee[committeeSize - 1];
            for (const v of committee.slice(0, thresholdCrossingIndex)) {
                const r = await d.elections.voteUnready(votedOutGuardian.address, 0xFFFFFFFF, {from: v.orbsAddress});
                expect(r).to.have.a.voteUnreadyCastedEvent({
                    voter: v.address,
                    subject: votedOutGuardian.address
                });
                expect(r).to.not.have.a.guardianVotedUnreadyEvent();
                expect(r).to.not.have.a.committeeSnapshotEvent();
            }

            r = await d.elections.voteUnready(votedOutGuardian.address, 0xFFFFFFFF, {from: committee[thresholdCrossingIndex].orbsAddress}); // Threshold is reached
            expect(r).to.have.a.voteUnreadyCastedEvent({
                voter: committee[thresholdCrossingIndex].address,
                subject: votedOutGuardian.address
            });
            expect(r).to.have.a.guardianVotedUnreadyEvent({
                guardian: votedOutGuardian.address
            });
            expect(r).to.have.a.guardianStatusUpdatedEvent({
                addr: votedOutGuardian.address,
                readyToSync: false,
                readyForCommittee: false
            });
            expect(r).to.have.a.committeeSnapshotEvent({
                addrs: committee.filter(v => v != votedOutGuardian).map(v => v.address)
            });

            // voted-out guardian re-joins by notifying ready-for-committee
            r = await votedOutGuardian.readyForCommittee();
            expect(r).to.have.a.committeeSnapshotEvent({
                addrs: committee.map(v => v.address)
            });
        }
    });

    it('VoteUnready: discards stale votes', async () => {
        assert(defaultDriverOptions.voteUnreadyThresholdPercentMille > (50 * 1000)); // so one out of two equal committee members does not cross the threshold

        const committeeSize = 2;
        const d = await Driver.new({maxCommitteeSize: committeeSize});

        let r;
        const committee: Participant[] = [];
        for (let i = 0; i < committeeSize; i++) {
            const v = d.newParticipant();
            await v.registerAsGuardian();
            await v.readyForCommittee();
            r = await v.stake(100);
            committee.push(v);
        }
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: committee.map(v => v.address)
        });

        const WEEK = 7 * 24 * 60 * 60;
        let expiration = bn((await d.web3.txTimestamp(r)) + WEEK);
        r = await d.elections.voteUnready(committee[1].address, expiration, {from: committee[0].orbsAddress});
        expect(r).to.have.a.voteUnreadyCastedEvent({
            voter: committee[0].address,
            subject: committee[1].address,
            expiration
        });

        // ...*.* TiMe wArP *.*.....
        await evmIncreaseTime(d.web3, WEEK);

        r = await d.elections.voteUnready(committee[1].address, 0xFFFFFFFF, {from: committee[1].orbsAddress}); // this should have crossed the vote-out threshold, but the previous vote had timed out
        expect(r).to.have.a.voteUnreadyCastedEvent({
            voter: committee[1].address,
            subject: committee[1].address,
        });
        expect(r).to.not.have.a.guardianVotedUnreadyEvent();
        expect(r).to.not.have.a.committeeSnapshotEvent();

        expiration = bn((await d.web3.txTimestamp(r)) + WEEK);
        // recast the stale vote-out, threshold should be reached
        r = await d.elections.voteUnready(committee[1].address, expiration, {from: committee[0].orbsAddress});
        expect(r).to.have.a.voteUnreadyCastedEvent({
            voter: committee[0].address,
            subject: committee[1].address,
            expiration
        });
        expect(r).to.have.a.guardianVotedUnreadyEvent({
            guardian: committee[1].address
        });
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: [committee[0].address]
        });
    });

    it('does not allow to notify ready without registration', async () => {
        const d = await Driver.new();

        const V1_STAKE = 100;

        const v = d.newParticipant();
        await v.stake(V1_STAKE);
        await expectRejected(v.readyToSync(), /Cannot resolve address/);
        await expectRejected(v.readyForCommittee(), /Cannot resolve address/);
    });

    it('staking before or after delegating has the same effect', async () => {
        const d = await Driver.new();

        const aGuardian = d.newParticipant();
        let r = await aGuardian.stake(100);

        // stake before delegate
        const delegator1 = d.newParticipant();
        await delegator1.stake(100);
        r = await delegator1.delegate(aGuardian);

        expect(r).to.have.a.stakeChangedEvent({addr: aGuardian.address, effective_stake: new BN(200)});

        // delegate before stake
        const delegator2 = d.newParticipant();
        await delegator2.delegate(aGuardian);
        r = await delegator2.stake(100);

        expect(r).to.have.a.stakeChangedEvent({addr: aGuardian.address, effective_stake: new BN(300)});
    });

    it('does not count delegated stake twice', async () => {
        const d = await Driver.new();

        const v1 = d.newParticipant();
        const v2 = d.newParticipant();

        await v1.stake(100);
        await v2.stake(100); // required due to the delegation cap ratio

        const r = await v1.delegate(v2);
        expect(r).to.have.a.stakeChangedEvent({
            addr: v1.address,
            effective_stake: new BN(0)
        });
        expect(r).to.have.a.stakeChangedEvent({
            addr: v2.address,
            effective_stake: new BN(200)
        });
    });

    it('enforces effective stake limit defined by minSelfStakePercentMille', async () => {
        const d = await Driver.new({maxCommitteeSize: 2, minSelfStakePercentMille: 10000});

        const v1 = d.newParticipant();
        const v2 = d.newParticipant();

        await v1.registerAsGuardian();
        await v1.readyForCommittee();

        await v2.delegate(v1);

        await v1.stake(100);

        let r = await v2.stake(900);
        expect(r).to.have.a.stakeChangedEvent({
            addr: v1.address,
            effective_stake: new BN(1000),
        });

        r = await v2.stake(1);
        expect(r).to.have.a.stakeChangedEvent({
            addr: v1.address,
            effective_stake: new BN(1000),
        });

        r = await v2.unstake(2);
        expect(r).to.have.a.stakeChangedEvent({
            addr: v1.address,
            effective_stake: new BN(999),
        });

        r = await v2.stake(11);
        expect(r).to.have.a.stakeChangedEvent({
            addr: v1.address,
            effective_stake: new BN(1000),
        });
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: [v1.address],
            weights: [new BN(1000)]
        });

        r = await v1.stake(2);
        expect(r).to.have.a.stakeChangedEvent({
            addr: v1.address,
            effective_stake: new BN(1012),
        });
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: [v1.address],
            weights: [new BN(1012)]
        });

        r = await v2.stake(30);
        expect(r).to.have.a.stakeChangedEvent({
            addr: v1.address,
            effective_stake: new BN(1020),
        });
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: [v1.address],
            weights: [new BN(1020)]
        });

        r = await v1.stake(1);
        expect(r).to.have.a.stakeChangedEvent({
            addr: v1.address,
            effective_stake: new BN(1030),
        });
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: [v1.address],
            weights: [new BN(1030)]
        });
    });

    it('guardian with zero self stake can have delegated stake when minSelfStakePercentMille == 0', async () => {
        const d = await Driver.new({maxCommitteeSize: 2, minSelfStakePercentMille: 0});

        const {v} = await d.newGuardian(0, false, false, true);
        const delegator = d.newParticipant();
        await delegator.stake(100);
        let r = await delegator.delegate(v);
        expect(r).to.have.a.stakeChangedEvent({
            addr: v.address,
            effective_stake: bn(100),
        });
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: [v.address],
            weights: [bn(100)],
        });
    });

    it('guardian with zero self stake cannot have delegated stake when minSelfStakePercentMille > 0', async () => {
        const d = await Driver.new({maxCommitteeSize: 2, minSelfStakePercentMille: 1});

        const {v} = await d.newGuardian(0, false, false, true);
        const delegator = d.newParticipant();
        await delegator.stake(100);
        let r = await delegator.delegate(v);
        expect(r).to.have.a.stakeChangedEvent({
            addr: v.address,
            effective_stake: bn(0),
        });
        expect((await d.committee.getCommittee())[0].length).to.eq(0);
    });

    it('ensures guardian who delegated cannot join committee even when owning enough stake', async () => {
        const d = await Driver.new();
        const v1 = d.newParticipant();
        const v2 = d.newParticipant();

        await v1.delegate(v2);
        await v1.stake(baseStake);
        await v1.registerAsGuardian();
        await v1.readyForCommittee();

        await v2.registerAsGuardian();
        await v2.readyForCommittee();
        let r = await v2.stake(baseStake);

        // Make sure v1 does not enter the committee
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: [v2.address],
        });
    });

    it('ensures a non-ready guardian cannot join the committee even when owning enough stake', async () => {
        const d = await Driver.new();
        const v = d.newParticipant();
        await v.stake(baseStake);
        await v.registerAsGuardian();
        let r = await v.readyToSync();
        r = await v.readyForCommittee();
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: [v.address]
        });

        const {r: r2} = await d.newGuardian(baseStake * 2, false, true, false);
        expect(r2).to.not.have.a.committeeSnapshotEvent();
    });

    it('publishes a CommiteeChangedEvent when the commitee becomes empty', async () => {
        const d = await Driver.new();
        const v = d.newParticipant();
        await v.registerAsGuardian();
        await v.stake(baseStake);

        let r = await v.readyForCommittee();
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: [v.address]
        });

        r = await v.unstake(baseStake);
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: []
        });
    });

    it("tracks total governance stakes", async () => {
        const d = await Driver.new();

        async function expectTotalGovernanceStakeToBe(n) {
            expect(await d.delegations.getTotalDelegatedStake()).to.be.bignumber.equal(bn(n));
        }

        const stakeOfA = 11;
        const stakeOfB = 13;
        const stakeOfC = 17;
        const stakeOfABC = stakeOfA + stakeOfB + stakeOfC;

        const a = d.newParticipant("delegating around"); // starts as self delegating
        const b = d.newParticipant("delegating to self - debating the amount");
        const c = d.newParticipant("delegating to a");
        await c.delegate(a);

        await a.stake(stakeOfA);
        await b.stake(stakeOfB);
        await c.stake(stakeOfC);

        await expectTotalGovernanceStakeToBe(stakeOfABC);

        await b.unstake(1);
        await expectTotalGovernanceStakeToBe(stakeOfABC - 1);

        await b.restake();
        await expectTotalGovernanceStakeToBe(stakeOfABC);

        await a.delegate(b); // delegate from self to a self delegating other
        await expectTotalGovernanceStakeToBe(stakeOfA + stakeOfB);

        await a.delegate(c); // delegate from self to a non-self delegating other
        await expectTotalGovernanceStakeToBe(stakeOfB);

        await a.delegate(a); // delegate to self back from a non-self delegating
        await expectTotalGovernanceStakeToBe(stakeOfABC);

        await a.delegate(c);
        await a.delegate(b); // delegate to another self delegating from a non-self delegating other
        await expectTotalGovernanceStakeToBe(stakeOfA + stakeOfB);

        await a.delegate(a); // delegate to self back from a self delegating other
        await expectTotalGovernanceStakeToBe(stakeOfABC);

    });

    it("tracks totalGovernanceStake correctly when assigning rewards", async () => {
        const d = await Driver.new();

        async function expectTotalGovernanceStakeToBe(n) {
            expect(await d.delegations.getTotalDelegatedStake()).to.be.bignumber.equal(bn(n));
        }

        const stakeOfA = 11;
        const stakeOfB = 13;
        const stakeOfC = 17;
        const stakeOfABC = stakeOfA + stakeOfB + stakeOfC;

        const a = d.newParticipant("delegating around"); // starts as self delegating
        const b = d.newParticipant("delegating to self - debating the amount");
        const c = d.newParticipant("delegating to a");
        await c.delegate(a);

        await a.stake(stakeOfA);
        await b.stake(stakeOfB);
        await c.stake(stakeOfC);

        await expectTotalGovernanceStakeToBe(stakeOfABC);

        const rewards = [
            {p: d.newParticipant(), amount: 10, d: a},
            {p: d.newParticipant(), amount: 20, d: a},
            {p: d.newParticipant(), amount: 30, d: b},
            {p: d.newParticipant(), amount: 40, d: b},
            {p: d.newParticipant(), amount: 50, d: b},
            {p: d.newParticipant(), amount: 60, d: c},
            {p: d.newParticipant(), amount: 70, d: c}
        ];
        let totalRewardsForGovernanceStake = 0;
        for (let i = 0; i < rewards.length; i++) {
            await rewards[i].p.delegate(rewards[i].d);
            if (await d.delegations.getDelegation(rewards[i].d.address) == rewards[i].d.address) {
                totalRewardsForGovernanceStake += rewards[i].amount
            }
        }
        const rewardsTotal = rewards.map(i => i.amount).reduce((a, b) => a + b);
        await d.erc20.assign(a.address, rewardsTotal);
        await d.erc20.approve(d.staking.address, rewardsTotal, {from: a.address});
        let r = await d.staking.distributeRewards(rewardsTotal, rewards.map(r => r.p.address), rewards.map(r => r.amount), {from: a.address});

        await expectTotalGovernanceStakeToBe(stakeOfABC + totalRewardsForGovernanceStake);

        expect(r).to.have.a.delegatedStakeChangedEvent({
            addr: a.address,
            selfDelegatedStake: bn(stakeOfA),
            delegatedStake: bn(stakeOfA + stakeOfC + 30),
            delegators: [rewards[0].p.address, rewards[1].p.address],
            delegatorTotalStakes: [bn(rewards[0].amount), bn(rewards[1].amount)]
        });

        expect(r).to.have.a.delegatedStakeChangedEvent({
            addr: b.address,
            selfDelegatedStake: bn(stakeOfB),
            delegatedStake: bn(stakeOfB + 120),
            delegators: [rewards[2].p.address, rewards[3].p.address, rewards[4].p.address],
            delegatorTotalStakes: [bn(rewards[2].amount), bn(rewards[3].amount), bn(rewards[4].amount)]
        });

        expect(r).to.have.a.delegatedStakeChangedEvent({
            addr: c.address,
            selfDelegatedStake: bn(0),
            delegatedStake: bn(130),
            delegators: [rewards[5].p.address, rewards[6].p.address],
            delegatorTotalStakes: [bn(rewards[5].amount), bn(rewards[6].amount)]
        })
    });

    it("VoteOut: does not count delegators voting - because they don't have effective governance stake", async () => {
        const d = await Driver.new();

        let r;
        let {thresholdCrossingIndex, delegatees, delegators, votedOutGuardian} = await voteOutScenario_setupDelegatorsAndGuardians(d);

        // -------------- BANNING VOTES CAST BY DELEGATORS - NO GOV STAKE, NO EFFECT ---------------
        for (const delegator of delegators) {
            r = await d.elections.voteOut(votedOutGuardian.address, {from: delegator.address});
            expect(r).to.have.a.voteOutCastedEvent({
                voter: delegator.address,
                subject: votedOutGuardian.address
            });
            expect(r).to.not.have.a.committeeSnapshotEvent();
            expect(r).to.not.have.a.guardianVotedOutEvent();
        }
    });

    it("VoteOut: bans a guardian only when accumulated votes stake reaches the threshold", async () => {
        const d = await Driver.new();

        let r;
        let {thresholdCrossingIndex, delegatees, delegators, votedOutGuardian} = await voteOutScenario_setupDelegatorsAndGuardians(d);

        // -------------- CAST VOTES UNDER THE THRESHOLD ---------------

        for (let i = 0; i < thresholdCrossingIndex; i++) {
            const p = delegatees[i];
            r = await d.elections.voteOut(votedOutGuardian.address, {from: p.address});
            expect(r).to.have.a.voteOutCastedEvent({
                voter: p.address,
                subject: votedOutGuardian.address
            });
            expect(r).to.not.have.a.committeeSnapshotEvent();
            expect(r).to.not.have.a.guardianVotedOutEvent();
        }

        // -------------- ONE MORE VOTE TO REACH BANNING THRESHOLD ---------------

        r = await d.elections.voteOut(votedOutGuardian.address, {from: delegatees[thresholdCrossingIndex].address}); // threshold is crossed
        expect(r).to.have.a.voteOutCastedEvent({
            voter: delegatees[thresholdCrossingIndex].address,
            subject: votedOutGuardian.address
        });
        expect(r).to.have.a.guardianVotedOutEvent({
            guardian: votedOutGuardian.address
        });
        expect(r).to.have.a.committeeSnapshotEvent({
            addrs: []
        });
    });

    it("VoteOut: vote-out is permanent - cannot be undone by cancelling a vote", async () => {
        const d = await Driver.new();

        let {thresholdCrossingIndex, delegatees, votedOutGuardian} = await voteOutScenario_setupDelegatorsAndGuardians(d);
        await banningScenario_voteUntilThresholdReached(d, thresholdCrossingIndex, delegatees, votedOutGuardian);

        const tipGuardian = delegatees[thresholdCrossingIndex];
        await d.elections.voteOut(ZERO_ADDR, {from: tipGuardian.address});
        await expectRejected(votedOutGuardian.readyForCommittee(), /caller is voted-out/);
    });

    it("VoteOut: update vote weight in response to staking and delegation", async () => {
        const d = await Driver.new();

        await d.newParticipant().stake(bn(100000)); // So we will not reach the vote-out threshold

        const voter = d.newParticipant();
        const subject = d.newParticipant();
        await d.elections.voteOut(subject.address, {from: voter.address});

        const otherVoter = d.newParticipant();
        await otherVoter.stake(100);
        await d.elections.voteOut(subject.address, {from: otherVoter.address});

        expect(await d.elections.getAccumulatedStakesForVoteOut(subject.address)).to.be.bignumber.eq(bn(100));

        // Increase vote weight by staking
        await voter.stake(100);
        expect(await d.elections.getAccumulatedStakesForVoteOut(subject.address)).to.be.bignumber.eq(bn(200));

        // Decrease vote weight by unstaking
        await voter.unstake(30);
        expect(await d.elections.getAccumulatedStakesForVoteOut(subject.address)).to.be.bignumber.eq(bn(170));

        // Increase vote weight by restaking
        await voter.restake();
        expect(await d.elections.getAccumulatedStakesForVoteOut(subject.address)).to.be.bignumber.eq(bn(200));

        // Decrease vote weight by delegating
        await voter.delegate(d.newParticipant());
        expect(await d.elections.getAccumulatedStakesForVoteOut(subject.address)).to.be.bignumber.eq(bn(100));

        // Increase vote weight by self delegation
        await voter.delegate(voter);
        expect(await d.elections.getAccumulatedStakesForVoteOut(subject.address)).to.be.bignumber.eq(bn(200));

        // Increase vote weight by a delegator stake
        const delegator = d.newParticipant();
        await delegator.stake(40);
        await delegator.delegate(voter);
        expect(await d.elections.getAccumulatedStakesForVoteOut(subject.address)).to.be.bignumber.eq(bn(240));

        // Decrease vote weight by loosing a delegation
        await delegator.delegate(delegator);
        expect(await d.elections.getAccumulatedStakesForVoteOut(subject.address)).to.be.bignumber.eq(bn(200));
    });

    it("rejects readyToSync and readyForCommittee for a voted-out guardian", async () => {
        const d = await Driver.new();

        let r;
        let {thresholdCrossingIndex, delegatees, delegators, votedOutGuardian} = await voteOutScenario_setupDelegatorsAndGuardians(d);

        // -------------- CAST VOTES UNDER THE THRESHOLD ---------------

        for (let i = 0; i < thresholdCrossingIndex; i++) {
            const p = delegatees[i];
            r = await d.elections.voteOut(votedOutGuardian.address, {from: p.address});
            expect(r).to.have.a.voteOutCastedEvent({
                voter: p.address,
                subject: votedOutGuardian.address
            });
            expect(r).to.not.have.a.committeeSnapshotEvent();
            expect(r).to.not.have.a.guardianVotedOutEvent();
        }

        // -------------- ONE MORE VOTE TO REACH VOTE-OUT THRESHOLD ---------------

        r = await d.elections.voteOut(votedOutGuardian.address, {from: delegatees[thresholdCrossingIndex].address}); // threshold is crossed
        expect(r).to.have.a.voteOutCastedEvent({
            voter: delegatees[thresholdCrossingIndex].address,
            subject: votedOutGuardian.address
        });
        expect(r).to.have.a.guardianVotedOutEvent({
            guardian: votedOutGuardian.address
        });
        expect(r).to.have.withinContract(d.committee).a.committeeSnapshotEvent({
            addrs: []
        });

        await expectRejected(d.elections.readyToSync({from: votedOutGuardian.address}), /caller is voted-out/);
        await expectRejected(d.elections.readyToSync({from: votedOutGuardian.orbsAddress}), /caller is voted-out/);
        await expectRejected(d.elections.readyForCommittee({from: votedOutGuardian.address}), /caller is voted-out/);
        await expectRejected(d.elections.readyForCommittee({from: votedOutGuardian.orbsAddress}), /caller is voted-out/);
    });

    it("sets and gets settings, only functional owner allowed to set", async () => {
        const d = await Driver.new();

        const current = await d.elections.getSettings();
        const minSelfStakePercentMille = bn(current[0]);
        const voteUnreadyPercentMilleThreshold = bn(current[1]);
        const voteOutPercentMilleThreshold = bn(current[2]);

        await expectRejected(d.elections.setMinSelfStakePercentMille(minSelfStakePercentMille.add(bn(1)), {from: d.migrationManager.address}), /sender is not the functional manager/);
        let r = await d.elections.setMinSelfStakePercentMille(minSelfStakePercentMille.add(bn(1)), {from: d.functionalManager.address});
        expect(r).to.have.a.minSelfStakePercentMilleChangedEvent({
            newValue: minSelfStakePercentMille.add(bn(1)).toString(),
            oldValue: minSelfStakePercentMille.toString()
        });

        await expectRejected(d.elections.setVoteOutPercentMilleThreshold(voteUnreadyPercentMilleThreshold.add(bn(1)), {from: d.migrationManager.address}), /sender is not the functional manager/);
        r = await d.elections.setVoteOutPercentMilleThreshold(voteUnreadyPercentMilleThreshold.add(bn(1)), {from: d.functionalManager.address});
        expect(r).to.have.a.voteOutPercentMilleThresholdChangedEvent({
            newValue: voteUnreadyPercentMilleThreshold.add(bn(1)).toString(),
            oldValue: voteUnreadyPercentMilleThreshold.toString()
        });

        await expectRejected(d.elections.setVoteUnreadyPercentMilleThreshold(voteOutPercentMilleThreshold.add(bn(1)), {from: d.migrationManager.address}), /sender is not the functional manager/);
        r = await d.elections.setVoteUnreadyPercentMilleThreshold(voteOutPercentMilleThreshold.add(bn(1)), {from: d.functionalManager.address});
        expect(r).to.have.a.voteUnreadyPercentMilleThresholdChangedEvent({
            newValue: voteOutPercentMilleThreshold.add(bn(1)).toString(),
            oldValue: voteOutPercentMilleThreshold.toString()
        });

        const afterUpdate = await d.elections.getSettings();
        expect([afterUpdate[0], afterUpdate[1], afterUpdate[2]]).to.deep.eq([
            minSelfStakePercentMille.add(bn(1)).toString(),
            voteUnreadyPercentMilleThreshold.add(bn(1)).toString(),
            voteOutPercentMilleThreshold.add(bn(1)).toString()
        ]);

        expect(await d.elections.getMinSelfStakePercentMille()).to.bignumber.eq(minSelfStakePercentMille.add(bn(1)));
        expect(await d.elections.getVoteUnreadyPercentMilleThreshold()).to.bignumber.eq(voteUnreadyPercentMilleThreshold.add(bn(1)));
        expect(await d.elections.getVoteOutPercentMilleThreshold()).to.bignumber.eq(voteOutPercentMilleThreshold.add(bn(1)));
    })

    it("reverts if casting a vote-unready with expiration in the past", async () => {
        const d = await Driver.new();

        await expectRejected(d.elections.voteUnready(d.newParticipant().address, 100), /vote expiration time must not be in the past/);
    });

});

export async function voteOutScenario_setupDelegatorsAndGuardians(driver: Driver) {
    assert(defaultDriverOptions.voteOutThresholdPercentMille < (98 * 1000)); // so each committee member will hold a positive stake
    assert(Math.floor(defaultDriverOptions.voteOutThresholdPercentMille / 2) >= (98 * 1000) - defaultDriverOptions.voteOutThresholdPercentMille); // so the committee list will be ordered by stake

    // -------------- SETUP ---------------
    const stakesPercentage = [
        Math.ceil(defaultDriverOptions.voteOutThresholdPercentMille / 1000 / 2),
        Math.floor(defaultDriverOptions.voteOutThresholdPercentMille / 1000 / 2),
        98 - defaultDriverOptions.voteOutThresholdPercentMille / 1000,
        1,
    ];
    const thresholdCrossingIndex = 1;
    const delegatees: Participant[] = [];
    const delegators: Participant[] = [];
    let totalStake = 0;
    for (const p of stakesPercentage) {
        // stake holders will not have own stake, only delegated - to test the use of governance stake
        const delegator = driver.newParticipant();

        const newStake = baseStake * p;
        totalStake += newStake;

        await delegator.stake(newStake);
        expect(await driver.delegations.getTotalDelegatedStake()).to.be.bignumber.equal(bn(totalStake));

        const v = driver.newParticipant();
        await delegator.delegate(v);
        expect(await driver.delegations.getTotalDelegatedStake()).to.be.bignumber.equal(bn(totalStake));

        delegatees.push(v);
        delegators.push(delegator);
    }

    const votedOutGuardian = delegatees[delegatees.length - 1];
    await votedOutGuardian.registerAsGuardian();

    await votedOutGuardian.stake(baseStake);
    let r = await votedOutGuardian.readyForCommittee();
    expect(r).to.have.a.committeeSnapshotEvent({
        addrs: [votedOutGuardian.address]
    });

    return {thresholdCrossingIndex, delegatees, delegators, votedOutGuardian};
}

export async function banningScenario_voteUntilThresholdReached(driver: Driver, thresholdCrossingIndex, delegatees, votedOutGuardian) {
    let r;
    for (let i = 0; i <= thresholdCrossingIndex; i++) {
        const p = delegatees[i];
        r = await driver.elections.voteOut(votedOutGuardian.address, {from: p.address});
    }
    expect(r).to.have.a.voteOutCastedEvent({
        voter: delegatees[thresholdCrossingIndex].address,
        subject: votedOutGuardian.address
    });
    expect(r).to.have.a.guardianVotedOutEvent({
        guardian: votedOutGuardian.address
    });
    expect(r).to.have.a.committeeSnapshotEvent({
        addrs: []
    });
    return r;
}
