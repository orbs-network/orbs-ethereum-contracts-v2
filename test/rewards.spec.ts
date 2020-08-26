import 'mocha';
import Web3 from "web3";
import BN from "bn.js";
import * as _ from "lodash";
import {
    defaultDriverOptions,
    Driver,
    Participant
} from "./driver";
import chai from "chai";
import {createVC} from "./consumer-macros";
import {bn, bnSum, evmIncreaseTime, expectRejected, fromTokenUnits, toTokenUnits} from "./helpers";
import {
    stakingRewardsAssignedEvents,
} from "./event-parsing";


declare const web3: Web3;

chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const expect = chai.expect;
const assert = chai.assert;

const BASE_STAKE = fromTokenUnits(1000000);
const MONTH_IN_SECONDS = 30*24*60*60;
const MAX_COMMITTEE = 4;

async function fullCommittee(committeeEvenStakes:boolean = false, numVCs=5): Promise<{d: Driver, committee: Participant[]}> {
    const d = await Driver.new({maxCommitteeSize: MAX_COMMITTEE, minSelfStakePercentMille: 0});

    const g = d.newParticipant();
    const poolAmount = fromTokenUnits(1000000);
    await g.assignAndApproveOrbs(poolAmount, d.stakingRewardsWallet.address);
    await d.stakingRewardsWallet.topUp(poolAmount, {from: g.address});
    let r = await d.rewards.setAnnualStakingRewardsRate(12000, poolAmount, {from: d.functionalManager.address});
    expect(r).to.have.a.annualStakingRewardsRateChangedEvent({
        annualRateInPercentMille: bn(12000),
        annualCap: poolAmount
    })

    await g.assignAndApproveExternalToken(poolAmount, d.bootstrapRewardsWallet.address);
    await d.bootstrapRewardsWallet.topUp(poolAmount, {from: g.address});
    await d.rewards.setGeneralCommitteeAnnualBootstrap(fromTokenUnits(12000), {from: d.functionalManager.address});
    await d.rewards.setCertifiedCommitteeAnnualBootstrap(fromTokenUnits(12000), {from: d.functionalManager.address});

    let committee: Participant[] = [];
    for (let i = 0; i < MAX_COMMITTEE; i++) {
        const {v} = await d.newGuardian(BASE_STAKE.add(fromTokenUnits(1 + (committeeEvenStakes ? 0 : i))), true, false, false);
        committee = [v].concat(committee);
    }

    await Promise.all(_.shuffle(committee).map(v => v.readyForCommittee()));

    const monthlyRate = fromTokenUnits(1000);
    const subs = await d.newSubscriber('defaultTier', monthlyRate);
    const appOwner = d.newParticipant();

    for (let i = 0; i < numVCs; i++) {
        await createVC(d, false, subs, monthlyRate, appOwner);
        await createVC(d, true, subs, monthlyRate, appOwner);
    }

    return {
        d,
        committee,
    }
}

async function sumBalances(d: Driver, committee: Participant[]): Promise<{fees: string, staking: string, bootstrap: string}> {
    const r = {
      fees: "0",
      staking: "0",
      bootstrap: "0"
    };
    await Promise.all(committee.map(async (v) => {
       const fees = bn(await d.rewards.getFeeBalance(v.address));
       const bootstrap = bn(await d.rewards.getBootstrapBalance(v.address));
       const balance = bn(await d.rewards.getStakingRewardBalance(v.address));

       r.fees = bn(r.fees).add(fees).toString();
       r.bootstrap = bn(r.bootstrap).add(bootstrap).toString();
       r.staking = bn(r.staking).add(balance).toString();
    }));
    expect(bn(r.staking).gt(bn(0))).to.be.true;
    expect(bn(r.bootstrap).gt(bn(0))).to.be.true;
    expect(bn(r.fees).gt(bn(0))).to.be.true;
    return r;
}

describe('rewards', async () => {
    it('withdraws staking rewards of guardian address even if sent from orbs address, and updates balances', async () => {
        const {d, committee} = await fullCommittee(true);

        // await d.rewards.assignRewards();
        await evmIncreaseTime(d.web3, 12*30*24*60*60);
        let r = await d.rewards.assignRewards();
        const stakingRewards = stakingRewardsAssignedEvents(r)[0].amounts;

        r = await d.rewards.distributeStakingRewards(
            stakingRewards[0],
            0,
            1,
            1,
            0,
            [committee[0].address],
            [stakingRewards[0]],
            {from: committee[0].address}
        );
        expect(r).to.have.a.stakedEvent({stakeOwner: committee[0].address, amount: stakingRewards[0]});

        r = await d.rewards.distributeStakingRewards(
            stakingRewards[1],
            0,
            1,
            1,
            0,
            [committee[1].address],
            [stakingRewards[1]],
            {from: committee[1].orbsAddress}
        );
        expect(r).to.have.a.stakedEvent({stakeOwner: committee[1].address, amount: stakingRewards[1]});

        expect(await d.rewards.getStakingRewardBalance(committee[0].address)).to.be.bignumber.eq(bn(0));
        expect(await d.rewards.getStakingRewardBalance(committee[1].address)).to.be.bignumber.eq(bn(0));
    });

    // todo - rewards contract tests

    it('performs emergency withdrawal only by the migration manager', async () => {
        const {d} = await fullCommittee();

        // await d.rewards.assignRewards();
        await evmIncreaseTime(d.web3, 12*30*24*60*60);
        await d.rewards.assignRewards();

        expect(await d.bootstrapToken.balanceOf(d.rewards.address)).to.bignumber.gt(bn(0));
        expect(await d.erc20.balanceOf(d.rewards.address)).to.bignumber.gt(bn(0));

        await expectRejected(d.rewards.emergencyWithdraw({from: d.functionalManager.address}), /sender is not the migration manager/);
        let r = await d.rewards.emergencyWithdraw({from: d.migrationManager.address});
        expect(r).to.have.a.emergencyWithdrawalEvent({addr: d.migrationManager.address});

        expect(await d.erc20.balanceOf(d.migrationManager.address)).to.bignumber.gt(bn(0));
        expect(await d.bootstrapToken.balanceOf(d.migrationManager.address)).to.bignumber.gt(bn(0));
        expect(await d.erc20.balanceOf(d.rewards.address)).to.bignumber.eq(bn(0));
        expect(await d.bootstrapToken.balanceOf(d.rewards.address)).to.bignumber.eq(bn(0));
    });

    it('gets settings', async () => {
        const d = await Driver.new();
        expect(await d.rewards.getCertifiedCommitteeAnnualBootstrap()).to.eq(defaultDriverOptions.certifiedCommitteeAnnualBootstrap.toString());
        expect(await d.rewards.getMaxDelegatorsStakingRewardsPercentMille()).to.eq(defaultDriverOptions.maxDelegatorsStakingRewardsPercentMille.toString());
        expect(await d.rewards.getAnnualStakingRewardsRate()).to.eq(defaultDriverOptions.stakingRewardsAnnualRateInPercentMille.toString());
        expect(await d.rewards.getAnnualStakingRewardsCap()).to.eq(defaultDriverOptions.stakingRewardsAnnualCap.toString());
    })

});
