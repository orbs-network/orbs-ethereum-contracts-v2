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
import {
    bn,
    bnSum,
    evmIncreaseTime,
    evmIncreaseTimeForQueries,
    expectRejected,
    fromTokenUnits,
    toTokenUnits
} from "./helpers";
import {
    stakingRewardsAssignedEvents,
} from "./event-parsing";
import {chaiEventMatchersPlugin} from "./matchers";

declare const web3: Web3;

chai.use(require('chai-bn')(BN));
chai.use(chaiEventMatchersPlugin);

const expect = chai.expect;
const assert = chai.assert;

const BASE_STAKE = fromTokenUnits(1000000);
const MONTH_IN_SECONDS = 30*24*60*60;
const MAX_COMMITTEE = 4;

const GENERAL_FEES_MONTHLY_RATE = fromTokenUnits(1000);
const CERTIFIED_FEES_MONTHLY_RATE = fromTokenUnits(2000);

const GENERAL_ANNUAL_BOOTSTRAP = fromTokenUnits(12000);
const CERTIFIED_ANNUAL_BOOTSTRAP = fromTokenUnits(15000);

async function fullCommittee(committeeEvenStakes:boolean = false, numVCs=5): Promise<{d: Driver, committee: Participant[]}> {
    const d = await Driver.new({maxCommitteeSize: MAX_COMMITTEE, minSelfStakePercentMille: 0});

    const g = d.newParticipant();
    const poolAmount = fromTokenUnits(1000000000000);
    await g.assignAndApproveOrbs(poolAmount, d.stakingRewardsWallet.address);
    await d.stakingRewardsWallet.topUp(poolAmount, {from: g.address});
    let r = await d.rewards.setAnnualStakingRewardsRate(12000, poolAmount, {from: d.functionalManager.address});
    expect(r).to.have.a.annualStakingRewardsRateChangedEvent({
        annualRateInPercentMille: bn(12000),
        annualCap: poolAmount
    })

    await g.assignAndApproveExternalToken(poolAmount, d.bootstrapRewardsWallet.address);
    await d.bootstrapRewardsWallet.topUp(poolAmount, {from: g.address});
    await d.rewards.setGeneralCommitteeAnnualBootstrap(GENERAL_ANNUAL_BOOTSTRAP, {from: d.functionalManager.address});
    await d.rewards.setCertifiedCommitteeAnnualBootstrap(CERTIFIED_ANNUAL_BOOTSTRAP, {from: d.functionalManager.address});

    let committee: Participant[] = [];
    for (let i = 0; i < MAX_COMMITTEE; i++) {
        const {v} = await d.newGuardian(BASE_STAKE.add(fromTokenUnits(1 + (committeeEvenStakes ? 0 : i))), false, false, false);
        committee = [v].concat(committee);
    }

    await Promise.all(_.shuffle(committee).map(v => v.readyForCommittee()));

    const subsGeneral = await d.newSubscriber('defaultTier', GENERAL_FEES_MONTHLY_RATE);
    const subsCertified = await d.newSubscriber('defaultTier', CERTIFIED_FEES_MONTHLY_RATE);
    const appOwner = d.newParticipant();

    for (let i = 0; i < numVCs; i++) {
        await createVC(d, false, subsGeneral, GENERAL_FEES_MONTHLY_RATE, appOwner);
        await createVC(d, true, subsCertified, CERTIFIED_FEES_MONTHLY_RATE, appOwner);
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
       const balance = bn(await d.rewards.getStakingRewardsBalance(v.address));

       r.fees = bn(r.fees).add(fees).toString();
       r.bootstrap = bn(r.bootstrap).add(bootstrap).toString();
       r.staking = bn(r.staking).add(balance).toString();
    }));
    expect(bn(r.staking).gt(bn(0))).to.be.true;
    expect(bn(r.bootstrap).gt(bn(0))).to.be.true;
    expect(bn(r.fees).gt(bn(0))).to.be.true;
    return r;
}

function rewardsForDuration(duration: number, nMembers: number, monthlyRate: BN): BN {
    return bn(duration).mul(monthlyRate).div(bn(MONTH_IN_SECONDS)).div(bn(nMembers));
}

function generalFeesForDuration(duration: number, nMembers: number): BN {
    return rewardsForDuration(duration, nMembers, GENERAL_FEES_MONTHLY_RATE);
}

function certifiedFeesForDuration(duration: number, nMembersCertified: number, nMembersGeneral): BN {
    return rewardsForDuration(duration, nMembersCertified, CERTIFIED_FEES_MONTHLY_RATE).add(rewardsForDuration(duration, nMembersGeneral, GENERAL_FEES_MONTHLY_RATE));
}

function generalBootstrapForDuration(duration: number): BN {
    return rewardsForDuration(duration, 1, GENERAL_ANNUAL_BOOTSTRAP.div(bn(12)));
}

function certifiedBootstrapForDuration(duration: number): BN {
    return rewardsForDuration(duration, 1, CERTIFIED_ANNUAL_BOOTSTRAP.add(GENERAL_ANNUAL_BOOTSTRAP).div(bn(12)));
}

function expectApproxEq(actual: BN|string|number, expected: BN|string|number) {
    const max = BN.max(bn(actual), bn(expected));
    const min = BN.min(bn(actual), bn(expected));

    assert(bn(max).mul(bn(100)).div(bn(min).add(bn(1))).lt(bn(102)), `Expected ${actual.toString()} to approx. equal ${expected.toString()}`);
}

describe('rewards', async () => {

    // Bootstrap and fees

    it('assigned bootstrap rewards and fees according to committee member participation (general committee)', async () => {
        const {d, committee} = await fullCommittee(false, 1);

        const DURATION = MONTH_IN_SECONDS * 5;

        // First committee member comes and goes, in committee for DURATION / 2 seconds in total
        // Second committee member is present the entire time

        expectApproxEq(await d.rewards.getFeeBalance(committee[0].address), 0);
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[0].address), 0);

        expectApproxEq(await d.rewards.getFeeBalance(committee[1].address), 0);
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[1].address), 0);

        await evmIncreaseTimeForQueries(d.web3, DURATION / 4);

        expectApproxEq(await d.rewards.getFeeBalance(committee[0].address), generalFeesForDuration(DURATION / 4, MAX_COMMITTEE));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[0].address), generalBootstrapForDuration(DURATION / 4));

        expectApproxEq(await d.rewards.getFeeBalance(committee[1].address), generalFeesForDuration(DURATION / 4, MAX_COMMITTEE));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[1].address), generalBootstrapForDuration(DURATION / 4));

        await committee[0].readyToSync(); // leaves committee

        expectApproxEq(await d.rewards.getFeeBalance(committee[0].address), generalFeesForDuration(DURATION / 4, MAX_COMMITTEE));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[0].address), generalBootstrapForDuration(DURATION / 4));

        expectApproxEq(await d.rewards.getFeeBalance(committee[1].address), generalFeesForDuration(DURATION / 4, MAX_COMMITTEE));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[1].address), generalBootstrapForDuration(DURATION / 4));

        await evmIncreaseTimeForQueries(d.web3, DURATION / 4);

        expectApproxEq(await d.rewards.getFeeBalance(committee[0].address), generalFeesForDuration(DURATION / 4, MAX_COMMITTEE));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[0].address), generalBootstrapForDuration(DURATION / 4));

        expectApproxEq(await d.rewards.getFeeBalance(committee[1].address), generalFeesForDuration(DURATION / 4, MAX_COMMITTEE).add(generalFeesForDuration(DURATION / 4, MAX_COMMITTEE - 1)));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[1].address), generalBootstrapForDuration(DURATION / 2));

        await committee[0].readyForCommittee(); // joins committee

        expectApproxEq(await d.rewards.getFeeBalance(committee[0].address), generalFeesForDuration(DURATION / 4, MAX_COMMITTEE));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[0].address), generalBootstrapForDuration(DURATION / 4));

        expectApproxEq(await d.rewards.getFeeBalance(committee[1].address), generalFeesForDuration(DURATION / 4, MAX_COMMITTEE).add(generalFeesForDuration(DURATION / 4, MAX_COMMITTEE - 1)));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[1].address), generalBootstrapForDuration(DURATION / 2));

        await evmIncreaseTimeForQueries(d.web3, DURATION / 4);

        expectApproxEq(await d.rewards.getFeeBalance(committee[0].address), generalFeesForDuration(DURATION / 2, MAX_COMMITTEE));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[0].address), generalBootstrapForDuration(DURATION / 2));

        expectApproxEq(await d.rewards.getFeeBalance(committee[1].address), generalFeesForDuration(DURATION / 2, MAX_COMMITTEE).add(generalFeesForDuration(DURATION / 4, MAX_COMMITTEE - 1)));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[1].address), generalBootstrapForDuration(DURATION / 4 * 3));

        await committee[0].readyToSync(); // leaves committee

        expectApproxEq(await d.rewards.getFeeBalance(committee[0].address), generalFeesForDuration(DURATION / 2, MAX_COMMITTEE));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[0].address), generalBootstrapForDuration(DURATION / 2));

        expectApproxEq(await d.rewards.getFeeBalance(committee[1].address), generalFeesForDuration(DURATION / 2, MAX_COMMITTEE).add(generalFeesForDuration(DURATION / 4, MAX_COMMITTEE - 1)));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[1].address), generalBootstrapForDuration(DURATION / 4 * 3));

        await evmIncreaseTimeForQueries(d.web3, DURATION / 4);

        expectApproxEq(await d.rewards.getFeeBalance(committee[0].address), generalFeesForDuration(DURATION / 2, MAX_COMMITTEE));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[0].address), generalBootstrapForDuration(DURATION / 2));

        expectApproxEq(await d.rewards.getFeeBalance(committee[1].address), generalFeesForDuration(DURATION / 2, MAX_COMMITTEE).add(generalFeesForDuration(DURATION / 2, MAX_COMMITTEE - 1)));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[1].address), generalBootstrapForDuration(DURATION));

        const c0OrbsBalance = await d.erc20.balanceOf(committee[0].address);
        await d.rewards.withdrawFees(committee[0].address);
        const c0AssignedFees = bn(await d.erc20.balanceOf(committee[0].address)).sub(bn(c0OrbsBalance));
        expectApproxEq(c0AssignedFees, generalFeesForDuration(DURATION / 2, MAX_COMMITTEE))

        const c0BootstrapBalance = await d.bootstrapToken.balanceOf(committee[0].address);
        await d.rewards.withdrawBootstrapFunds(committee[0].address);
        const c0AssignedBootstrap = bn(await d.bootstrapToken.balanceOf(committee[0].address)).sub(bn(c0BootstrapBalance));
        expectApproxEq(c0AssignedBootstrap, generalBootstrapForDuration(DURATION / 2));

        const c1OrbsBalance = await d.erc20.balanceOf(committee[1].address);
        await d.rewards.withdrawFees(committee[1].address);
        const c1AssignedFees = bn(await d.erc20.balanceOf(committee[1].address)).sub(bn(c1OrbsBalance));
        expectApproxEq(c1AssignedFees, generalFeesForDuration(DURATION / 2, MAX_COMMITTEE).add(generalFeesForDuration(DURATION / 2, MAX_COMMITTEE - 1)));

        const c1BootstrapBalance = await d.bootstrapToken.balanceOf(committee[1].address);
        await d.rewards.withdrawBootstrapFunds(committee[1].address);
        const c1AssignedBootstrap = bn(await d.bootstrapToken.balanceOf(committee[1].address)).sub(bn(c1BootstrapBalance));
        expectApproxEq(c1AssignedBootstrap, generalBootstrapForDuration(DURATION));
    });

    it('assigned bootstrap rewards and fees according to committee member participation (compliance committee)', async () => {
        const {d, committee} = await fullCommittee(false, 1);

        await Promise.all(committee.map(c => c.becomeCertified()));

        const DURATION = MONTH_IN_SECONDS*5;

        // First committee member comes and goes, in committee for DURATION / 2 seconds in total
        // Second committee member is present the entire time

        expectApproxEq(await d.rewards.getFeeBalance(committee[0].address), 0);
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[0].address), 0);

        expectApproxEq(await d.rewards.getFeeBalance(committee[1].address), 0);
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[1].address), 0);

        await evmIncreaseTimeForQueries(d.web3, DURATION / 4);

        expectApproxEq(await d.rewards.getFeeBalance(committee[0].address), certifiedFeesForDuration(DURATION / 4, MAX_COMMITTEE, MAX_COMMITTEE));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[0].address), certifiedBootstrapForDuration(DURATION / 4));

        expectApproxEq(await d.rewards.getFeeBalance(committee[1].address), certifiedFeesForDuration(DURATION / 4, MAX_COMMITTEE, MAX_COMMITTEE));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[1].address), certifiedBootstrapForDuration(DURATION / 4));

        await committee[0].becomeNotCertified(); // leaves certified committee

        expectApproxEq(await d.rewards.getFeeBalance(committee[0].address), certifiedFeesForDuration(DURATION / 4, MAX_COMMITTEE, MAX_COMMITTEE));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[0].address), certifiedBootstrapForDuration(DURATION / 4));

        expectApproxEq(await d.rewards.getFeeBalance(committee[1].address), certifiedFeesForDuration(DURATION / 4, MAX_COMMITTEE, MAX_COMMITTEE));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[1].address), certifiedBootstrapForDuration(DURATION / 4));

        await evmIncreaseTimeForQueries(d.web3, DURATION / 4);

        expectApproxEq(await d.rewards.getFeeBalance(committee[0].address), certifiedFeesForDuration(DURATION / 4, MAX_COMMITTEE, MAX_COMMITTEE).add(generalFeesForDuration(DURATION / 4, MAX_COMMITTEE)));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[0].address), certifiedBootstrapForDuration(DURATION / 4).add(generalBootstrapForDuration(DURATION / 4)));

        expectApproxEq(await d.rewards.getFeeBalance(committee[1].address), certifiedFeesForDuration(DURATION / 4, MAX_COMMITTEE, MAX_COMMITTEE).add(certifiedFeesForDuration(DURATION / 4, MAX_COMMITTEE - 1, MAX_COMMITTEE)));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[1].address), certifiedBootstrapForDuration(DURATION / 2));

        await committee[0].becomeCertified(); // joins certified committee

        expectApproxEq(await d.rewards.getFeeBalance(committee[0].address), certifiedFeesForDuration(DURATION / 4, MAX_COMMITTEE, MAX_COMMITTEE).add(generalFeesForDuration(DURATION / 4, MAX_COMMITTEE)));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[0].address), certifiedBootstrapForDuration(DURATION / 4).add(generalBootstrapForDuration(DURATION / 4)));

        expectApproxEq(await d.rewards.getFeeBalance(committee[1].address), certifiedFeesForDuration(DURATION / 4, MAX_COMMITTEE, MAX_COMMITTEE).add(certifiedFeesForDuration(DURATION / 4, MAX_COMMITTEE - 1, MAX_COMMITTEE)));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[1].address), certifiedBootstrapForDuration(DURATION / 2));

        await evmIncreaseTimeForQueries(d.web3, DURATION / 4);

        expectApproxEq(await d.rewards.getFeeBalance(committee[0].address), certifiedFeesForDuration(DURATION / 2, MAX_COMMITTEE, MAX_COMMITTEE).add(generalFeesForDuration(DURATION / 4, MAX_COMMITTEE)));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[0].address), certifiedBootstrapForDuration(DURATION / 2).add(generalBootstrapForDuration(DURATION / 4)));

        expectApproxEq(await d.rewards.getFeeBalance(committee[1].address), certifiedFeesForDuration(DURATION / 2, MAX_COMMITTEE, MAX_COMMITTEE).add(certifiedFeesForDuration(DURATION / 4, MAX_COMMITTEE - 1, MAX_COMMITTEE)));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[1].address), certifiedBootstrapForDuration(DURATION / 4 * 3));

        await committee[0].readyToSync(); // leaves both committees

        expectApproxEq(await d.rewards.getFeeBalance(committee[0].address), certifiedFeesForDuration(DURATION / 2, MAX_COMMITTEE, MAX_COMMITTEE).add(generalFeesForDuration(DURATION / 4, MAX_COMMITTEE)));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[0].address), certifiedBootstrapForDuration(DURATION / 2).add(generalBootstrapForDuration(DURATION / 4)));

        expectApproxEq(await d.rewards.getFeeBalance(committee[1].address), certifiedFeesForDuration(DURATION / 2, MAX_COMMITTEE, MAX_COMMITTEE).add(certifiedFeesForDuration(DURATION / 4, MAX_COMMITTEE - 1, MAX_COMMITTEE)));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[1].address), certifiedBootstrapForDuration(DURATION / 4 * 3));

        await evmIncreaseTimeForQueries(d.web3, DURATION / 4);

        expectApproxEq(await d.rewards.getFeeBalance(committee[0].address), certifiedFeesForDuration(DURATION / 2, MAX_COMMITTEE, MAX_COMMITTEE).add(generalFeesForDuration(DURATION / 4, MAX_COMMITTEE)));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[0].address), certifiedBootstrapForDuration(DURATION / 2).add(generalBootstrapForDuration(DURATION / 4)));

        expectApproxEq(await d.rewards.getFeeBalance(committee[1].address), certifiedFeesForDuration(DURATION / 2, MAX_COMMITTEE, MAX_COMMITTEE).add(certifiedFeesForDuration(DURATION / 4, MAX_COMMITTEE - 1, MAX_COMMITTEE)).add(certifiedFeesForDuration(DURATION / 4, MAX_COMMITTEE - 1, MAX_COMMITTEE - 1)));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[1].address), certifiedBootstrapForDuration(DURATION));

        const c0OrbsBalance = await d.erc20.balanceOf(committee[0].address);
        await d.rewards.withdrawFees(committee[0].address);
        const c0AssignedFees = bn(await d.erc20.balanceOf(committee[0].address)).sub(bn(c0OrbsBalance));
        expectApproxEq(c0AssignedFees, certifiedFeesForDuration(DURATION / 2, MAX_COMMITTEE, MAX_COMMITTEE).add(generalFeesForDuration(DURATION / 4, MAX_COMMITTEE)))

        const c0BootstrapBalance = await d.bootstrapToken.balanceOf(committee[0].address);
        await d.rewards.withdrawBootstrapFunds(committee[0].address);
        const c0AssignedBootstrap = bn(await d.bootstrapToken.balanceOf(committee[0].address)).sub(bn(c0BootstrapBalance));
        expectApproxEq(c0AssignedBootstrap, certifiedBootstrapForDuration(DURATION / 2).add(generalBootstrapForDuration(DURATION / 4)));

        const c1OrbsBalance = await d.erc20.balanceOf(committee[1].address);
        await d.rewards.withdrawFees(committee[1].address);
        const c1AssignedFees = bn(await d.erc20.balanceOf(committee[1].address)).sub(bn(c1OrbsBalance));
        expectApproxEq(c1AssignedFees, certifiedFeesForDuration(DURATION / 2, MAX_COMMITTEE, MAX_COMMITTEE).add(certifiedFeesForDuration(DURATION / 4, MAX_COMMITTEE - 1, MAX_COMMITTEE)).add(certifiedFeesForDuration(DURATION / 4, MAX_COMMITTEE - 1, MAX_COMMITTEE - 1)));

        const c1BootstrapBalance = await d.bootstrapToken.balanceOf(committee[1].address);
        await d.rewards.withdrawBootstrapFunds(committee[1].address);
        const c1AssignedBootstrap = bn(await d.bootstrapToken.balanceOf(committee[1].address)).sub(bn(c1BootstrapBalance));
        expectApproxEq(c1AssignedBootstrap, certifiedBootstrapForDuration(DURATION));
    });

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

        expect(await d.rewards.getStakingRewardsBalance(committee[0].address)).to.be.bignumber.eq(bn(0));
        expect(await d.rewards.getStakingRewardsBalance(committee[1].address)).to.be.bignumber.eq(bn(0));
    });

    // Staking rewards

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
        const opts = {
            generalCommitteeAnnualBootstrap: fromTokenUnits(10),
            certifiedCommitteeAnnualBootstrap: fromTokenUnits(20),
            maxDelegatorsStakingRewardsPercentMille: 3,
            stakingRewardsAnnualRateInPercentMille: 4,
            stakingRewardsAnnualCap: fromTokenUnits(50)
        };
        const d = await Driver.new(opts as any);

        expect(await d.rewards.getGeneralCommitteeAnnualBootstrap()).to.eq(opts.generalCommitteeAnnualBootstrap.toString());
        expect(await d.rewards.getCertifiedCommitteeAnnualBootstrap()).to.eq(opts.certifiedCommitteeAnnualBootstrap.toString());
        expect(await d.rewards.getMaxDelegatorsStakingRewardsPercentMille()).to.eq(opts.maxDelegatorsStakingRewardsPercentMille.toString());
        expect(await d.rewards.getAnnualStakingRewardsRatePercentMille()).to.eq(opts.stakingRewardsAnnualRateInPercentMille.toString());
        expect(await d.rewards.getAnnualStakingRewardsCap()).to.eq(opts.stakingRewardsAnnualCap.toString());

        expect((await d.rewards.getSettings()).generalCommitteeAnnualBootstrap).to.eq(opts.generalCommitteeAnnualBootstrap.toString());
        expect((await d.rewards.getSettings()).certifiedCommitteeAnnualBootstrap).to.eq(opts.certifiedCommitteeAnnualBootstrap.toString());
        expect((await d.rewards.getSettings()).maxDelegatorsStakingRewardsPercentMille).to.eq(opts.maxDelegatorsStakingRewardsPercentMille.toString());
        expect((await d.rewards.getSettings()).annualStakingRewardsRatePercentMille).to.eq(opts.stakingRewardsAnnualRateInPercentMille.toString());
        expect((await d.rewards.getSettings()).annualStakingRewardsCap).to.eq(opts.stakingRewardsAnnualCap.toString());
        expect((await d.rewards.getSettings()).active).to.be.true;
    })

});
