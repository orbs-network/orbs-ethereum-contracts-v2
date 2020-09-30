import 'mocha';

import BN from "bn.js";
import {
    Driver,
} from "./driver";
import chai from "chai";
import {bn, contractId, expectRejected} from "./helpers";
import {TransactionReceipt} from "web3-core";
import {chaiEventMatchersPlugin, expectCommittee} from "./matchers";

chai.use(require('chai-bn')(BN));
chai.use(chaiEventMatchersPlugin);

const expect = chai.expect;
const assert = chai.assert;

describe('delegations-contract', async () => {

    it('should only accept stake notifications from the staking contract handler', async () => {
        const d = await Driver.new();

        const rogueStakingContractHandler = await d.newStakingContract(d.delegations.address, d.erc20.address);

        const participant = d.newParticipant();

        await expectRejected(participant.stake(5, rogueStakingContractHandler), /caller is not the staking contract/);
        await participant.stake(5);
        await d.contractRegistry.setContract("stakingContractHandler", rogueStakingContractHandler.address, false, {from: d.registryAdmin.address});
        await participant.stake(5, rogueStakingContractHandler)

        // TODO - to check stakeChangeBatch use a mock staking contract that would satisfy the interface but would allow sending stakeChangeBatch when there are no rewards to distribue
    });

    it('selfDelegatedStake toggles to zero if delegating to another', async () => {
        const d = await Driver.new();

        const p1 = d.newParticipant();
        let r = await p1.stake(100);
        expect(r).to.have.a.delegatedStakeChangedEvent({
            addr: p1.address,
            selfDelegatedStake: bn(100),
            delegatedStake: bn(100),
            delegators: [p1.address],
            delegatorTotalStakes: [bn(100)]
        });

        const p2 = d.newParticipant();
        r = await p1.delegate(p2);
        expect(r).to.have.a.delegatedStakeChangedEvent({
            addr: p1.address,
            selfDelegatedStake: bn(0),
            delegatedStake: bn(0),
            delegators: [p1.address],
            delegatorTotalStakes: [bn(0)]
        });
        expect(r).to.have.a.delegatedStakeChangedEvent({
            addr: p2.address,
            selfDelegatedStake: bn(0),
            delegatedStake: bn(100),
            delegators: [p1.address],
            delegatorTotalStakes: [bn(100)]
        });

        r = await p1.delegate(p1);
        expect(r).to.have.a.delegatedStakeChangedEvent({
            addr: p1.address,
            selfDelegatedStake: bn(100),
            delegatedStake: bn(100),
            delegators: [p1.address],
            delegatorTotalStakes: [bn(100)]
        });
    });

    it('emits DelegatedStakeChanged and Delegated on delegation changes', async () => {
        const d = await Driver.new();

        const p1 = d.newParticipant();
        let r = await p1.stake(100);
        expect(r).to.have.a.delegatedStakeChangedEvent({
            addr: p1.address,
            selfDelegatedStake: bn(100),
            delegatedStake: bn(100),
            delegators: [p1.address],
            delegatorTotalStakes: [bn(100)]
        });

        const p2 = d.newParticipant();
        r = await p2.delegate(p1);
        expect(r).to.have.a.delegatedEvent({
            from: p2.address,
            to: p1.address
        });
        expect(r).to.not.have.a.delegatedStakeChangedEvent();

        r = await p2.stake(100);
        expect(r).to.have.a.delegatedStakeChangedEvent({
            addr: p1.address,
            selfDelegatedStake: bn(100),
            delegatedStake: bn(200),
            delegators: [p2.address],
            delegatorTotalStakes: [bn(100)]
        });

        r = await p2.stake(11);
        expect(r).to.have.a.delegatedStakeChangedEvent({
            addr: p1.address,
            selfDelegatedStake: bn(100),
            delegatedStake: bn(211),
            delegators: [p2.address],
            delegatorTotalStakes: [bn(111)]
        });

        const p3 = d.newParticipant();
        await p3.stake(100);
        r = await p3.delegate(p1);
        expect(r).to.have.a.delegatedEvent({
            from: p3.address,
            to: p1.address
        });
        expect(r).to.have.a.delegatedStakeChangedEvent({
            addr: p3.address,
            selfDelegatedStake: bn(0),
            delegatedStake: bn(0),
            delegators: [p3.address],
            delegatorTotalStakes: [bn(0)]
        });
        expect(r).to.have.a.delegatedStakeChangedEvent({
            addr: p1.address,
            selfDelegatedStake: bn(100),
            delegatedStake: bn(311),
            delegators: [p3.address],
            delegatorTotalStakes: [bn(100)]
        });

        const p4 = d.newParticipant();
        p4.stake(100);
        expect(await d.delegations.getDelegation(p4.address)).to.equal(p4.address);

        await d.erc20.assign(d.accounts[0], 1000);
        await d.erc20.approve(d.staking.address, 1000, {from: d.accounts[0]});
        r = await d.staking.distributeRewards(
            1000,
            [p1.address, p2.address, p3.address, p4.address],
            [100, 200, 300, 400]
        );
        expect(r).to.have.a.delegatedStakeChangedEvent({
            addr: p1.address,
            selfDelegatedStake: bn(200),
            delegatedStake: bn(411),
            delegators: [p1.address],
            delegatorTotalStakes: [bn(200)]
        });
        expect(r).to.have.a.delegatedStakeChangedEvent({
            addr: p1.address,
            selfDelegatedStake: bn(200),
            delegatedStake: bn(611),
            delegators: [p2.address],
            delegatorTotalStakes: [bn(311)]
        });
        expect(r).to.have.a.delegatedStakeChangedEvent({
            addr: p1.address,
            selfDelegatedStake: bn(200),
            delegatedStake: bn(911),
            delegators: [p3.address],
            delegatorTotalStakes: [bn(400)]
        });
        expect(r).to.have.a.delegatedStakeChangedEvent({
            addr: p4.address,
            selfDelegatedStake: bn(500),
            delegatedStake: bn(500),
            delegators: [p4.address],
            delegatorTotalStakes: [bn(500)]
        });
    });

    it('when delegating to another, DelegatedStakeChanged should indicate a new delegation of 0 to the previous delegate', async () => {
        const d = await Driver.new();
        let r: TransactionReceipt;

        const v1 = d.newParticipant();
        const v2 = d.newParticipant();
        const d1 = d.newParticipant();

        await d1.stake(100);
        r = await d1.delegate(v1);
        expect(r).to.have.a.delegatedStakeChangedEvent({
            addr: v1.address,
            delegators: [d1.address],
            delegatorTotalStakes: [bn(100)]
        });

        r = await d1.delegate(v2);
        expect(r).to.have.a.delegatedStakeChangedEvent({
            addr: v2.address,
            delegators: [d1.address],
            delegatorTotalStakes: [bn(100)]
        });
        expect(r).to.have.a.delegatedStakeChangedEvent({
            addr: v1.address,
            delegators: [d1.address],
            delegatorTotalStakes: [bn(0)]
        });
    });

    it("tracks total delegated stakes", async () => {
        const d = await Driver.new();
        async function expectTotalGovernanceStakeToBe(n) {
            expect(await d.delegations.getTotalDelegatedStake()).to.be.bignumber.equal(bn(n));
        }

        const stakeOfA = 11;
        const stakeOfB = 13;
        const stakeOfC = 17;
        const stakeOfABC = stakeOfA+stakeOfB+stakeOfC;

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
        await expectTotalGovernanceStakeToBe(stakeOfA + stakeOfB); // fails

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

    it('uses absolute stake on first notification of stake change (batched and non-batched)', async () => {
       const d = await Driver.new();

       const otherDelegationContract = await d.web3.deploy("Delegations", [d.contractRegistry.address, d.registryAdmin.address], null, d.session);

       await d.contractRegistry.setContract("delegations", otherDelegationContract.address, true, {from: d.registryAdmin.address});

       const v1 = d.newParticipant();
       await v1.stake(100);

       const v2 = d.newParticipant();
       await v2.stake(100);

        await d.contractRegistry.setContract("delegations", d.delegations.address, true, {from: d.registryAdmin.address});

       // Non-batched

       // First time - using the total value
       let r = await v1.stake(100);
       expect(r).to.have.a.delegatedStakeChangedEvent({
           addr: v1.address,
           selfDelegatedStake: bn(200)
       });

       // Second time - using the delta
       r = await v1.stake(100);
       expect(r).to.have.a.delegatedStakeChangedEvent({
           addr: v1.address,
           selfDelegatedStake: bn(300)
       });

       // Batched

       // First time - using the total value
       await v2.assignAndApproveOrbs(100, d.staking.address);
       r = await d.staking.distributeRewards(100, [v2.address], [100], {from: v2.address});
       expect(r).to.have.a.delegatedStakeChangedEvent({
           addr: v2.address,
           selfDelegatedStake: bn(200)
       });

       // Second time - using the delta
       await v2.assignAndApproveOrbs(100, d.staking.address);
       r = await d.staking.distributeRewards(100, [v2.address], [100], {from: v2.address});
       expect(r).to.have.a.delegatedStakeChangedEvent({
           addr: v2.address,
           selfDelegatedStake: bn(300)
       });

    });

    const importDelegationsTestGenerator = (notifyElections: boolean) => {
        return async () => {
            const d = await Driver.new();

            await d.stakingContractHandler.setNotifyDelegations(false, {from: d.migrationManager.address});

            const d1 = d.newParticipant();
            await d1.stake(100);

            const d2 = d.newParticipant();
            await d2.stake(200);

            const d3 = d.newParticipant();
            await d3.stake(300);

            await d.stakingContractHandler.setNotifyDelegations(true, {from: d.migrationManager.address});

            const {v: v1} = await d.newGuardian(100, false, false, true);
            const {v: v2} = await d.newGuardian(100, false, false, true);

            expect(await d.delegations.getTotalDelegatedStake()).to.be.bignumber.equal(bn(200));

            let r = await d.delegations.importDelegations([d1.address], v1.address, notifyElections, {from: d.migrationManager.address});
            notifyElections ?
                await expectCommittee(d,  {addrs: [v1.address, v2.address]}) :
                expect(r).to.not.have.a.guardianCommitteeChangeEvent();

            expect(r).to.have.a.delegationsImportedEvent({
                from: [d1.address],
                to: v1.address
            });
            expect(r).to.have.a.delegatedEvent({from: d1.address, to: v1.address});
            expect(r).to.have.a.delegatedStakeChangedEvent({
                addr: v1.address,
                selfDelegatedStake: bn(100),
                delegatedStake: bn(200),
                delegators: [d1.address],
                delegatorTotalStakes: [bn(100)]
            });

            expect(await d.delegations.getTotalDelegatedStake()).to.be.bignumber.equal(bn(300));

            r = await d.delegations.importDelegations([d2.address, d3.address], v2.address, notifyElections, {from: d.migrationManager.address});
            notifyElections ?
                await expectCommittee(d,  {addrs: [v2.address, v1.address]}) :
                expect(r).to.not.have.a.guardianCommitteeChangeEvent();

            expect(r).to.have.a.delegationsImportedEvent({
                from: [d2.address, d3.address],
                to: v2.address
            });
            expect(r).to.have.a.delegatedEvent({from: d2.address, to: v2.address});
            expect(r).to.have.a.delegatedEvent({from: d3.address, to: v2.address});
            expect(r).to.have.a.delegatedStakeChangedEvent({
                addr: v2.address,
                selfDelegatedStake: bn(100),
                delegatedStake: bn(600),
                delegators: [d2.address, d3.address],
                delegatorTotalStakes: [bn(200), bn(300)]
            });

            expect(await d.delegations.getTotalDelegatedStake()).to.be.bignumber.equal(bn(800));

            // import a delegation when already delegated should fail

            await expectRejected(d.delegations.importDelegations([d1.address], v2.address, notifyElections, {from: d.migrationManager.address}),
                /import allowed only for uninitialized accounts. existing delegation detected/);

            await expectRejected(d.delegations.importDelegations([v2.address], v1.address, notifyElections, {from: d.migrationManager.address}),
                /import allowed only for uninitialized accounts. existing stake detected/);

            if (!notifyElections) { // manual notification refresh:
                r = await d.delegations.refreshStakeNotification(v1.address);
                await expectCommittee(d,  {addrs: [v1.address, v2.address]});

                r = await d.delegations.refreshStakeNotification(v2.address);
                await expectCommittee(d,  {addrs: [v2.address, v1.address]});
            }
        };
    };

    // it('imports a delegation for a delegator with an existing stake (without elections notification)', importDelegationsTestGenerator(false));
    it('imports a delegation for a delegator with an existing stake (with    elections notification)', importDelegationsTestGenerator(true));

    it('tracks uncappedStakes and totalDelegateStakes correctly on importDelegations', async () => {
        const d = await Driver.new();

        await d.stakingContractHandler.setNotifyDelegations(false, {from: d.migrationManager.address});

        const d1 = d.newParticipant();
        await d1.stake(100);

        const d2 = d.newParticipant();
        await d2.stake(200);

        const d3 = d.newParticipant();
        await d3.stake(300);

        await d.stakingContractHandler.setNotifyDelegations(true, {from: d.migrationManager.address});

        await d.delegations.importDelegations([d1.address], d2.address, false, {from: d.migrationManager.address});
        expect(await d.delegations.getTotalDelegatedStake()).to.be.bignumber.equal(bn(100));
        expect(await d.delegations.uncappedStakes(d1.address)).to.be.bignumber.equal(bn(0));
        expect(await d.delegations.uncappedStakes(d2.address)).to.be.bignumber.equal(bn(100));
        expect(await d.delegations.uncappedStakes(d3.address)).to.be.bignumber.equal(bn(0));

        await d.delegations.importDelegations([d3.address], d1.address, false, {from: d.migrationManager.address});
        expect(await d.delegations.getTotalDelegatedStake()).to.be.bignumber.equal(bn(100));
        expect(await d.delegations.uncappedStakes(d1.address)).to.be.bignumber.equal(bn(300));
        expect(await d.delegations.uncappedStakes(d2.address)).to.be.bignumber.equal(bn(100));
        expect(await d.delegations.uncappedStakes(d3.address)).to.be.bignumber.equal(bn(0));

        await d.delegations.importDelegations([d2.address], d3.address, false, {from: d.migrationManager.address});
        expect(await d.delegations.getTotalDelegatedStake()).to.be.bignumber.equal(bn(0));
        expect(await d.delegations.uncappedStakes(d1.address)).to.be.bignumber.equal(bn(300));
        expect(await d.delegations.uncappedStakes(d2.address)).to.be.bignumber.equal(bn(100));
        expect(await d.delegations.uncappedStakes(d3.address)).to.be.bignumber.equal(bn(200));
    });

    it('ensures only the migration owner can import a delegation and finalize imports', async () => {
       const d = await Driver.new();

       const d1 = d.newParticipant();
       const v1 = d.newParticipant();

       await expectRejected(d.delegations.importDelegations([d1.address], v1.address, false, {from: d.functionalManager.address}), /sender is not the migration manager/);
       await d.delegations.importDelegations([d1.address], v1.address, false, {from: d.migrationManager.address});

       await expectRejected(d.delegations.finalizeDelegationImport({from: d.functionalManager.address}), /sender is not the migration manager/);
       let r = await d.delegations.finalizeDelegationImport({from: d.migrationManager.address});
       expect(r).to.have.a.delegationImportFinalizedEvent({});

       await expectRejected(d.delegations.importDelegations([d1.address], v1.address, false, {from: d.migrationManager.address}), /delegation import was finalized/);
    });

    it('properly handles a delegation when self stake of delegator is not yet initialized', async () => {
        const d = await Driver.new();

        const d1 = d.newParticipant();
        const {v} = await d.newGuardian(100, false, false, true);
        await d1.delegate(v);

        const otherDelegationContract = await d.web3.deploy("Delegations", [d.contractRegistry.address, d.registryAdmin.address], null, d.session);

        await d.contractRegistry.setContract("delegations", otherDelegationContract.address, true, {from: d.registryAdmin.address});

        await d1.stake(100);

        await d.contractRegistry.setContract("delegations", d.delegations.address, true, {from: d.registryAdmin.address});

        let r = await d.delegations.refreshStake(d1.address);
        expect(r).to.have.a.delegatedStakeChangedEvent({
            addr: v.address,
            delegatedStake: bn(200)
        });
        await expectCommittee(d,  {addrs: [v.address]});
    });

    it('properly handles a stake change notifications when previous notifications were not given', async () => {
        const d = await Driver.new();

        const v = d.newParticipant();

        const d1 = d.newParticipant();
        await d1.stake(100);

        let r = await d1.delegate(v);
        expect(r).to.have.a.delegatedStakeChangedEvent({
            addr: d1.address,
            delegatedStake: bn(0)
        });
        expect(r).to.have.a.delegatedStakeChangedEvent({
            addr: v.address,
            delegatedStake: bn(100)
        });

        const otherDelegationContract = await d.web3.deploy("Delegations", [d.contractRegistry.address, d.registryAdmin.address], null, d.session);

        await d.contractRegistry.setContract("delegations", otherDelegationContract.address, true, {from: d.registryAdmin.address});

        r = await d1.stake(200);
        expect(r).to.not.have.withinContract(d.delegations).a.delegatedStakeChangedEvent();

        await d.contractRegistry.setContract("delegations", d.delegations.address, true, {from: d.registryAdmin.address});

        r = await d1.stake(300);
        expect(r).to.have.a.delegatedStakeChangedEvent({
            addr: v.address,
            delegatedStake: bn(600)
        });
    });

    it('does not fail a delegation to the same guardian', async () => {
       const d = await Driver.new();

       const p = d.newParticipant();
       const v = d.newParticipant();

       await p.delegate(p);
       await p.delegate(p);
       await p.delegate(v);
       await p.delegate(v);
       await p.delegate(p);
       await p.delegate(p);
    });
});
