import 'mocha';

import BN from "bn.js";
import {
    Driver, ZERO_ADDR,
} from "./driver";
import chai from "chai";
import {bn, expectRejected} from './helpers';
chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const expect = chai.expect;

describe("staking-contract-handler", async () => {

    it("should proxy getStakeBalanceOf and getTotalStakedTokens", async () => {
        const d = await Driver.new();
        const p1 = d.newParticipant();
        await p1.stake(100);
        const p2 = d.newParticipant();
        await p2.stake(200);

        expect(await d.stakingContractHandler.getStakeBalanceOf(p1.address)).to.bignumber.eq(bn(100));
        expect(await d.stakingContractHandler.getTotalStakedTokens()).to.bignumber.eq(bn(300));
    });

    it("does not revert staking although stake change notifier has reverted", async () => {
        const d = await Driver.new();

        const revertingNotifier = await d.web3.deploy('RevertingStakeChangeNotifier' as any, [], null, d.session);

        // make sure it actually reverts
        await expectRejected(revertingNotifier.stakeChange(ZERO_ADDR, 0, false, 0), /RevertingStakeChangeNotifier: stakeChange reverted/);
        await expectRejected(revertingNotifier.stakeChangeBatch([ZERO_ADDR], [0], [false], [0]), /RevertingStakeChangeNotifier: stakeChangeBatch reverted/);
        await expectRejected(revertingNotifier.stakeMigration(ZERO_ADDR, 0), /RevertingStakeChangeNotifier: stakeMigration reverted/);

        await d.contractRegistry.setContract("delegations", revertingNotifier.address, false, {from: d.functionalOwner.address});

        const p = d.newParticipant();
        let r = await p.stake(100);
        expect(r).to.have.a.stakedEvent({
            stakeOwner: p.address,
            totalStakedAmount: bn(100)
        });
        expect(r).to.have.a.stakeChangeNotificationFailedEvent({stakeOwner: p.address});

        const p2 = d.newParticipant();
        await p.assignAndApproveOrbs(100, d.staking.address);
        r = await d.staking.distributeRewards(100, [p2.address], [100], {from : p.address});
        expect(r).to.have.a.stakedEvent({
            stakeOwner: p2.address,
            totalStakedAmount: bn(100)
        });
        expect(r).to.have.a.stakeChangeBatchNotificationFailedEvent({stakeOwners: [p2.address]});

        // Stake migration - both staking contracts will notify, requires a complex setup
        const newRegistry = await d.web3.deploy('ContractRegistry', [], null, d.session);

        const newHandler = await d.web3.deploy('StakingContractHandler', [newRegistry.address], null, d.session);
        await newRegistry.setContract("stakingContractHandler", newHandler.address, true);

        const newStaking = await d.newStakingContract(newHandler.address, d.erc20.address);
        await newRegistry.setContract("staking", newStaking.address, false);

        const newRevertingNotifier = await d.web3.deploy('RevertingStakeChangeNotifier' as any, [], null, d.session);
        await newRegistry.setContract("delegations", newRevertingNotifier.address, false);

        await d.staking.addMigrationDestination(newStaking.address, {from: d.migrationOwner.address});
        r = await d.staking.migrateStakedTokens(newStaking.address, 100, {from: p2.address});
        expect(r).to.have.a.migratedStakeEvent({
            stakeOwner: p2.address,
            amount: bn(100)
        });
        expect(r).to.have.a.stakeMigrationNotificationFailedEvent({stakeOwner: p2.address});
    })

    it("does not revert staking although stake change notifier consumes too much gas", async () => {
        const d = await Driver.new();

        const gasConsumingNotifier = await d.web3.deploy('GasConsumingStakeChangeNotifier' as any, [], null, d.session);
        await d.contractRegistry.setContract("delegations", gasConsumingNotifier.address, false, {from: d.functionalOwner.address});

        // make sure it consumes too much gas
        expect((await gasConsumingNotifier.stakeChange(ZERO_ADDR, 0, false, 0)).gasUsed).to.be.greaterThan(5000000);
        expect((await gasConsumingNotifier.stakeChangeBatch([ZERO_ADDR], [0], [false], [0])).gasUsed).to.be.greaterThan(5000000);
        expect((await gasConsumingNotifier.stakeMigration(ZERO_ADDR, 0)).gasUsed).to.be.greaterThan(5000000);

        const p = d.newParticipant();
        let r = await p.stake(100);
        expect(r).to.have.a.stakedEvent({
            stakeOwner: p.address,
            totalStakedAmount: bn(100)
        });
        expect(r).to.have.a.stakeChangeNotificationFailedEvent({stakeOwner: p.address});
        expect(r.gasUsed).to.be.greaterThan(5000000);

        const p2 = d.newParticipant();
        await p.assignAndApproveOrbs(100, d.staking.address);
        r = await d.staking.distributeRewards(100, [p2.address], [100], {from : p.address});
        expect(r).to.have.a.stakedEvent({
            stakeOwner: p2.address,
            totalStakedAmount: bn(100)
        });
        expect(r).to.have.a.stakeChangeBatchNotificationFailedEvent({stakeOwners: [p2.address]});
        expect(r.gasUsed).to.be.greaterThan(5000000);

        // Stake migration - both staking contracts will notify, requires a complex setup
        const newRegistry = await d.web3.deploy('ContractRegistry', [], null, d.session);

        const newHandler = await d.web3.deploy('StakingContractHandler', [newRegistry.address], null, d.session);
        await newRegistry.setContract("stakingContractHandler", newHandler.address, true);

        const newStaking = await d.newStakingContract(newHandler.address, d.erc20.address);
        await newRegistry.setContract("staking", newStaking.address, false);

        const newRevertingNotifier = await d.web3.deploy('GasConsumingStakeChangeNotifier' as any, [], null, d.session);
        await newRegistry.setContract("delegations", newRevertingNotifier.address, false);

        await d.staking.addMigrationDestination(newStaking.address, {from: d.migrationOwner.address});
        r = await d.staking.migrateStakedTokens(newStaking.address, 100, {from: p2.address});
        expect(r).to.have.a.migratedStakeEvent({
            stakeOwner: p2.address,
            amount: bn(100)
        });
        expect(r).to.have.a.stakeMigrationNotificationFailedEvent({stakeOwner: p2.address});
        expect(r.gasUsed).to.be.greaterThan(5000000);
    });

    it("accepts notifications only from the staking contract", async () => {
        const d = await Driver.new();

        await expectRejected(d.stakingContractHandler.stakeChange(ZERO_ADDR, 1, true, 1), /caller is not the staking contract/);
        await expectRejected(d.stakingContractHandler.stakeChangeBatch([ZERO_ADDR], [1], [true], [1]), /caller is not the staking contract/);
        await expectRejected(d.stakingContractHandler.stakeMigration(ZERO_ADDR, 1), /caller is not the staking contract/);
    });

})