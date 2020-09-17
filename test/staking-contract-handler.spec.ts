import 'mocha';

import BN from "bn.js";
import {
    Driver, ZERO_ADDR,
} from "./driver";
import chai from "chai";
import {bn, expectRejected} from './helpers';
import {chaiEventMatchersPlugin} from "./matchers";
chai.use(require('chai-bn')(BN));
chai.use(chaiEventMatchersPlugin);

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

    it("accepts notifications only from the staking contract", async () => {
        const d = await Driver.new();

        await expectRejected(d.stakingContractHandler.stakeChange(ZERO_ADDR, 1, true, 1), /caller is not the staking contract/);
        await expectRejected(d.stakingContractHandler.stakeChangeBatch([ZERO_ADDR], [1], [true], [1]), /caller is not the staking contract/);
        await expectRejected(d.stakingContractHandler.stakeMigration(ZERO_ADDR, 1), /caller is not the staking contract/);
    });

    it("does not notify delegations if notifyDelegations is set to false", async () => {
        const d = await Driver.new();

        await expectRejected(d.stakingContractHandler.setNotifyDelegations(true, {from: d.functionalManager.address}), /sender is not the migration manager/);
        let r = await d.stakingContractHandler.setNotifyDelegations(true, {from: d.migrationManager.address});
        expect(r).to.have.a.notifyDelegationsChangedEvent({notifyDelegations: true});

        r = await d.stakingContractHandler.setNotifyDelegations(false, {from: d.migrationManager.address});
        expect(r).to.have.a.notifyDelegationsChangedEvent({notifyDelegations: false});

        const p = d.newParticipant();
        r = await p.stake(100);
        expect(r).to.have.a.stakedEvent({
            stakeOwner: p.address,
            totalStakedAmount: bn(100)
        });
        expect(r).to.have.a.stakeChangeNotificationSkippedEvent({
            stakeOwner: p.address
        });
        expect(r).to.not.have.a.delegatedStakeChangedEvent();

        await p.assignAndApproveOrbs(100, d.staking.address);
        const p2 = d.newParticipant();
        r = await d.staking.distributeRewards(100, [p2.address], [100], {from: p.address});
        expect(r).to.have.a.stakedEvent({
            stakeOwner: p2.address,
            totalStakedAmount: bn(100)
        });
        expect(r).to.have.a.stakeChangeBatchNotificationSkippedEvent({
            stakeOwners: [p2.address]
        });
        expect(r).to.not.have.a.delegatedStakeChangedEvent();

        const newStaking = await d.newStakingContract(ZERO_ADDR, d.erc20.address);

        await d.staking.addMigrationDestination(newStaking.address, {from: d.migrationManager.address});
        r = await d.staking.migrateStakedTokens(newStaking.address, 100, {from: p2.address});
        expect(r).to.have.a.migratedStakeEvent({
            stakeOwner: p2.address,
            amount: bn(100)
        });
        expect(r).to.have.a.stakeMigrationNotificationSkippedEvent({stakeOwner: p2.address});
    });

})