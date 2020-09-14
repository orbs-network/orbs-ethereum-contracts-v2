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

const BASE_STAKE = fromTokenUnits(1000);
const MONTH_IN_SECONDS = 30*24*60*60;
const MAX_COMMITTEE = 4;

const GENERAL_FEES_MONTHLY_RATE = fromTokenUnits(1000);
const CERTIFIED_FEES_MONTHLY_RATE = fromTokenUnits(2000);

const GENERAL_ANNUAL_BOOTSTRAP = fromTokenUnits(12000);
const CERTIFIED_ANNUAL_BOOTSTRAP = fromTokenUnits(15000);

const STAKING_REWARDS_ANNUAL_RATE = bn(12000);
const STAKING_REWARDS_ANNUAL_CAP = fromTokenUnits(10000)

const MIN_SELF_STAKE_PERCENT_MILLE = bn(13000);

const DELEGATOR_REWARDS_PERCENT_MILLE = bn(67000);

const YEAR_IN_SECONDS = 365*24*60*60;

async function fullCommittee(stakes?: BN[] | null, numVCs=5, opts?: {
    stakingRewardsAnnualRate?: BN,
    stakingRewardsAnnualCap?: BN,
    minSelfStakePercentMille?: BN
}): Promise<{d: Driver, committee: Participant[]}> {
    opts = opts || {};

    const stakingRewardsAnnualRate: BN = opts.stakingRewardsAnnualRate || STAKING_REWARDS_ANNUAL_RATE;
    const stakingRewardsAnnualCap: BN = opts.stakingRewardsAnnualCap || STAKING_REWARDS_ANNUAL_CAP;
    const minSelfStakePercentMille: BN = opts.minSelfStakePercentMille || MIN_SELF_STAKE_PERCENT_MILLE;

    const d = await Driver.new({maxCommitteeSize: MAX_COMMITTEE, minSelfStakePercentMille: minSelfStakePercentMille.toNumber(), delegatorsStakingRewardsPercentMille: DELEGATOR_REWARDS_PERCENT_MILLE});

    const g = d.newParticipant();
    const poolAmount = fromTokenUnits(1000000000000);
    await g.assignAndApproveOrbs(poolAmount, d.stakingRewardsWallet.address);
    await d.stakingRewardsWallet.topUp(poolAmount, {from: g.address});
    let r = await d.rewards.setAnnualStakingRewardsRate(stakingRewardsAnnualRate, stakingRewardsAnnualCap, {from: d.functionalManager.address});
    expect(r).to.have.a.annualStakingRewardsRateChangedEvent({
        annualRateInPercentMille: stakingRewardsAnnualRate,
        annualCap: stakingRewardsAnnualCap
    })

    await g.assignAndApproveExternalToken(poolAmount, d.bootstrapRewardsWallet.address);
    await d.bootstrapRewardsWallet.topUp(poolAmount, {from: g.address});
    await d.rewards.setGeneralCommitteeAnnualBootstrap(GENERAL_ANNUAL_BOOTSTRAP, {from: d.functionalManager.address});
    await d.rewards.setCertifiedCommitteeAnnualBootstrap(CERTIFIED_ANNUAL_BOOTSTRAP, {from: d.functionalManager.address});

    let committee: Participant[] = [];
    for (let i = 0; i < MAX_COMMITTEE; i++) {
        const stake = stakes ? stakes[i] : BASE_STAKE;
        const {v} = await d.newGuardian(stake, false, false, false);
        committee.push(v);
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

function roundTo48(x: BN): BN {
    return fromTokenUnits(toTokenUnits(x));
}

async function stakingRewardsForDuration(d: Driver, duration: number, delegator: Participant, guardian: Participant): Promise<{delegatorRewards: BN, guardianRewards: BN}> {
    const memberInfo = await d.committee.getMemberInfo(guardian.address);
    const guardianWeight = bn(memberInfo.weight);
    const totalWeight = bn(memberInfo.totalCommitteeWeight)

    const cap = bn(await d.rewards.getAnnualStakingRewardsCap());
    const ratio = bn(await d.rewards.getDelegatorsStakingRewardsPercentMille());
    const rate = bn(await d.rewards.getAnnualStakingRewardsRatePercentMille());

    const actualRate = BN.min(totalWeight.mul(rate).div(bn(100000)), cap).mul(bn(100000)).div(totalWeight);

    const delegatorStake = bn((await d.delegations.getDelegationInfo(delegator.address)).delegatorStake);
    const guardianStake = bn((await d.delegations.getDelegationInfo(guardian.address)).delegatorStake);
    const guardianDelegatedStake = bn(await d.delegations.getDelegatedStake(guardian.address));

    const totalRewards = guardianWeight.mul(actualRate).mul(bn(duration)).div(bn(YEAR_IN_SECONDS * 100000));
    const totalDelegatorRewards = totalRewards.mul(ratio).div(bn(100000));
    let guardianRewards = totalRewards.sub(totalDelegatorRewards);
    const delegatorRewards = roundTo48(totalDelegatorRewards.mul(delegatorStake).div(guardianDelegatedStake));
    guardianRewards = guardianRewards.add(roundTo48(totalDelegatorRewards.mul(guardianStake).div(guardianDelegatedStake)))

    return {
        delegatorRewards,
        guardianRewards,
    }
}

function expectApproxEq(actual: BN|string|number, expected: BN|string|number) {
    assert(bn(actual).sub(bn(expected)).abs().lte(BN.max(bn(actual), bn(expected)).div(bn(50))), `Expected ${actual.toString()} to approx. equal ${expected.toString()}`);
}

describe.only('rewards', async () => {

    // Bootstrap and fees

    it('assigned bootstrap rewards and fees according to committee member participation (general committee), emits events', async () => {
        const {d, committee} = await fullCommittee(null, 1);

        const DURATION = MONTH_IN_SECONDS * 5;

        // First committee member comes and goes, in committee for DURATION / 2 seconds in total
        // Second committee member is present the entire time

        let c0Fees = await d.rewards.getFeeBalance(committee[0].address)
        let c0Bootstrap = await d.rewards.getBootstrapBalance(committee[0].address)
        let c1Fees = await d.rewards.getFeeBalance(committee[1].address)
        let c1Bootstrap = await d.rewards.getBootstrapBalance(committee[1].address)

        expectApproxEq(c0Fees, 0);
        expectApproxEq(c0Bootstrap, 0);

        expectApproxEq(c1Fees, 0);
        expectApproxEq(c1Bootstrap, 0);

        await evmIncreaseTimeForQueries(d.web3, DURATION / 4);

        expectApproxEq(await d.rewards.getFeeBalance(committee[0].address), generalFeesForDuration(DURATION / 4, MAX_COMMITTEE));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[0].address), generalBootstrapForDuration(DURATION / 4));

        expectApproxEq(await d.rewards.getFeeBalance(committee[1].address), generalFeesForDuration(DURATION / 4, MAX_COMMITTEE));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[1].address), generalBootstrapForDuration(DURATION / 4));

        let r = await committee[0].readyToSync(); // leaves committee
        expect(r).to.have.a.approx().feesAssignedEvent({guardian: committee[0].address, amount: generalFeesForDuration(DURATION / 4, MAX_COMMITTEE)});
        expect(r).to.have.a.approx().bootstrapRewardsAssignedEvent({guardian: committee[0].address, amount: generalBootstrapForDuration(DURATION / 4)});

        expectApproxEq(await d.rewards.getFeeBalance(committee[0].address), generalFeesForDuration(DURATION / 4, MAX_COMMITTEE));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[0].address), generalBootstrapForDuration(DURATION / 4));

        expectApproxEq(await d.rewards.getFeeBalance(committee[1].address), generalFeesForDuration(DURATION / 4, MAX_COMMITTEE));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[1].address), generalBootstrapForDuration(DURATION / 4));

        await evmIncreaseTimeForQueries(d.web3, DURATION / 4);

        expectApproxEq(await d.rewards.getFeeBalance(committee[0].address), generalFeesForDuration(DURATION / 4, MAX_COMMITTEE));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[0].address), generalBootstrapForDuration(DURATION / 4));

        expectApproxEq(await d.rewards.getFeeBalance(committee[1].address), generalFeesForDuration(DURATION / 4, MAX_COMMITTEE).add(generalFeesForDuration(DURATION / 4, MAX_COMMITTEE - 1)));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[1].address), generalBootstrapForDuration(DURATION / 2));

        r = await committee[0].readyForCommittee(); // joins committee
        expect(r).to.have.a.approx().feesAssignedEvent({guardian: committee[0].address, amount: bn(0)});
        expect(r).to.have.a.approx().bootstrapRewardsAssignedEvent({guardian: committee[0].address, amount: bn(0)});

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
        r = await d.rewards.withdrawFees(committee[0].address);
        expect(r).to.have.a.feesAssignedEvent({});
        const c0AssignedFees = bn(await d.erc20.balanceOf(committee[0].address)).sub(bn(c0OrbsBalance));
        expectApproxEq(c0AssignedFees, generalFeesForDuration(DURATION / 2, MAX_COMMITTEE))

        const c0BootstrapBalance = await d.bootstrapToken.balanceOf(committee[0].address);
        r = await d.rewards.withdrawBootstrapFunds(committee[0].address);
        expect(r).to.have.a.bootstrapRewardsAssignedEvent({});
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
        const {d, committee} = await fullCommittee(null, 1);

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

    // Staking rewards

    it('assigns staking rewards to committee member, accommodate for participation and stake changes', async () => {
        const {d, committee} = await fullCommittee([fromTokenUnits(4000), fromTokenUnits(3000), fromTokenUnits(2000), fromTokenUnits(1000)], 1);

        const c0 = committee[0];

        expectApproxEq(await d.rewards.getStakingRewardsBalance(c0.address), 0);

        // In committee, stake 4000

        await evmIncreaseTimeForQueries(d.web3, MONTH_IN_SECONDS);

        let total = (await stakingRewardsForDuration(d, MONTH_IN_SECONDS, c0, c0)).guardianRewards;
        expectApproxEq(await d.rewards.getStakingRewardsBalance(c0.address), total);

        await c0.unstake(fromTokenUnits(2000));

        expectApproxEq(await d.rewards.getStakingRewardsBalance(c0.address), total);

        // In committee, stake 2000

        await evmIncreaseTimeForQueries(d.web3, MONTH_IN_SECONDS);

        total = total.add((await stakingRewardsForDuration(d, MONTH_IN_SECONDS, c0, c0)).guardianRewards)
        expectApproxEq(await d.rewards.getStakingRewardsBalance(c0.address), total);

        await c0.stake(fromTokenUnits(2000));

        // In committee, stake 4000

        expectApproxEq(await d.rewards.getStakingRewardsBalance(c0.address), total);
        await evmIncreaseTimeForQueries(d.web3, MONTH_IN_SECONDS);

        total = total.add((await stakingRewardsForDuration(d, MONTH_IN_SECONDS, c0, c0)).guardianRewards)
        expectApproxEq(await d.rewards.getStakingRewardsBalance(c0.address), total);

        await c0.readyToSync();

        // Out of committee

        expectApproxEq(await d.rewards.getStakingRewardsBalance(c0.address), total);

        await evmIncreaseTimeForQueries(d.web3, MONTH_IN_SECONDS);

        expectApproxEq(await d.rewards.getStakingRewardsBalance(c0.address), total);

        await c0.readyForCommittee();

        // In committee, stake 4000

        expectApproxEq(await d.rewards.getStakingRewardsBalance(c0.address), total);

        await evmIncreaseTimeForQueries(d.web3, MONTH_IN_SECONDS);

        total = total.add((await stakingRewardsForDuration(d, MONTH_IN_SECONDS, c0, c0)).guardianRewards)

        expectApproxEq(await d.rewards.getStakingRewardsBalance(c0.address), total);

        // Claiming entire amount

        let r = await d.rewards.claimStakingRewards(c0.address);

        expect(r).to.have.approx().a.stakingRewardsClaimedEvent({
            addr: c0.address,
            amount: total
        });
        expect(r).to.have.approx().a.stakedEvent({
            stakeOwner: c0.address,
            amount: total
        });
    });

    it('assigns staking rewards to delegator, accommodate for delegation and stake changes', async () => {
        const {d, committee} = await fullCommittee([fromTokenUnits(4000), fromTokenUnits(3000), fromTokenUnits(2000), fromTokenUnits(1000)], 1);

        const c0 = committee[0];
        let delegation = c0;

        const d0 = d.newParticipant();
        await d0.delegate(delegation);
        await d0.stake(fromTokenUnits(1000));

        const PERIOD = MONTH_IN_SECONDS * 2;

        let cTotal = bn(0);
        let dTotal = bn(0);

        const checkAndUpdate = async () => {
            expectApproxEq(await d.rewards.getStakingRewardsBalance(c0.address), cTotal);
            expectApproxEq(await d.rewards.getStakingRewardsBalance(d0.address), dTotal);

            await evmIncreaseTimeForQueries(d.web3, PERIOD);

            cTotal = cTotal.add((await stakingRewardsForDuration(d, PERIOD, c0, c0)).guardianRewards);
            expectApproxEq(await d.rewards.getStakingRewardsBalance(c0.address), cTotal);

            dTotal = dTotal.add((await stakingRewardsForDuration(d, PERIOD, d0, delegation)).delegatorRewards);
            expectApproxEq(await d.rewards.getStakingRewardsBalance(d0.address), dTotal);
        }

        // In committee, d0 [stake: 1000] -> c0 [stake: 4000]
        await checkAndUpdate();

        await c0.unstake(fromTokenUnits(2000));

        // In committee, d0 [stake: 1000] -> c0 [stake: 2000]
        await checkAndUpdate();

        await c0.stake(fromTokenUnits(2000));

        // In committee, d0 [stake: 1000] -> c0 [stake: 4000]
        await checkAndUpdate();

        await c0.readyToSync();

        // Out of committee
        await checkAndUpdate();

        await c0.readyForCommittee();

        // In committee, d0 [stake: 1000] -> c0 [stake: 4000]
        await checkAndUpdate();

        delegation = committee[1];
        await d0.delegate(delegation);

        // In committee, d0 [stake: 1000] -> c1 [stake: 3000]
        await checkAndUpdate();

        await d0.stake(fromTokenUnits(1000));

        // In committee, d0 [stake: 2000] -> c1 [stake: 3000]
        await checkAndUpdate();

        delegation = d0;
        await d0.delegate(delegation);

        // In committee, d0 -> d0
        await checkAndUpdate();

        delegation = c0;
        await d0.delegate(delegation);

        // In committee, d0 [stake: 2000] -> c0 [stake: 4000]
        await checkAndUpdate();

        // Claim entire amount
        let r = await d.rewards.claimStakingRewards(c0.address);
        expect(r).to.have.approx().a.stakingRewardsClaimedEvent({
            addr: c0.address,
            amount: cTotal
        });

        r = await d.rewards.claimStakingRewards(d0.address);
        expect(r).to.have.approx().a.stakingRewardsClaimedEvent({
            addr: d0.address,
            amount: dTotal
        });
    });

    it('enforces annual staking rewards cap', async () => {
        const {d, committee} = await fullCommittee([STAKING_REWARDS_ANNUAL_CAP.mul(bn(100000)).div(STAKING_REWARDS_ANNUAL_RATE).mul(bn(2)), bn(1), bn(1), bn(1)]);

        await evmIncreaseTimeForQueries(d.web3, YEAR_IN_SECONDS);

        expectApproxEq(await d.rewards.getStakingRewardsBalance(committee[0].address), STAKING_REWARDS_ANNUAL_CAP);
    })

    it('enforces annual staking rewards cap when set to zero', async () => {
        const {d, committee} = await fullCommittee(null, 1, {stakingRewardsAnnualCap: bn(0)});

        await evmIncreaseTimeForQueries(d.web3, YEAR_IN_SECONDS);

        expect(await d.rewards.getStakingRewardsBalance(committee[0].address)).to.bignumber.eq(bn(0));
    })

    it('enforces effective stake limit (min self stake)', async () => {
        const {d, committee} = await fullCommittee([fromTokenUnits(MIN_SELF_STAKE_PERCENT_MILLE), bn(1), bn(1), bn(1)], 1, {stakingRewardsAnnualCap: fromTokenUnits(100000000000)});
        const c0 = committee[0];
        const d0 = d.newParticipant();
        const dStake = fromTokenUnits(bn(100000).sub(MIN_SELF_STAKE_PERCENT_MILLE));
        await d0.stake(dStake);
        await d0.delegate(c0);

        await evmIncreaseTimeForQueries(d.web3, YEAR_IN_SECONDS);

        let cTotal = bn((await stakingRewardsForDuration(d, YEAR_IN_SECONDS, c0, c0)).guardianRewards);
        expectApproxEq(await d.rewards.getStakingRewardsBalance(c0.address), cTotal);
        let dTotal = bn((await stakingRewardsForDuration(d, YEAR_IN_SECONDS, d0, c0)).delegatorRewards);
        expectApproxEq(await d.rewards.getStakingRewardsBalance(d0.address), dTotal);

        const allRewards0 = cTotal.add(dTotal);

        await d0.stake(dStake);

        await evmIncreaseTimeForQueries(d.web3, YEAR_IN_SECONDS);

        cTotal = cTotal.add(bn((await stakingRewardsForDuration(d, YEAR_IN_SECONDS, c0, c0)).guardianRewards));
        expectApproxEq(await d.rewards.getStakingRewardsBalance(c0.address), cTotal);
        dTotal = dTotal.add(bn((await stakingRewardsForDuration(d, YEAR_IN_SECONDS, d0, c0)).delegatorRewards));
        expectApproxEq(await d.rewards.getStakingRewardsBalance(d0.address), dTotal);

        const allRewards1 = cTotal.add(dTotal);

        expectApproxEq(allRewards1.div(bn(2)), allRewards0); // rate shouldn't have changed as the effective stake remained the same for the two periods
    })

    it('performs emergency withdrawal only by the migration manager', async () => {
        // const {d, committee} = await fullCommittee();

        // // await d.rewards.assignRewards();
        // await evmIncreaseTime(d.web3, 12*30*24*60*60);
        // await committee[0].stake(bn(1000)); // trigger reward assignment

        const d = await Driver.new();
        const p = d.newParticipant();
        await p.assignAndTransferOrbs(bn(1000), d.rewards.address);
        await p.assignAndTransferExternalToken(bn(2000), d.rewards.address);

        await expectRejected(d.rewards.emergencyWithdraw({from: d.functionalManager.address}), /sender is not the migration manager/);
        let r = await d.rewards.emergencyWithdraw({from: d.migrationManager.address});
        expect(r).to.have.a.emergencyWithdrawalEvent({addr: d.migrationManager.address});

        expect(await d.erc20.balanceOf(d.migrationManager.address)).to.bignumber.eq(bn(1000));
        expect(await d.bootstrapToken.balanceOf(d.migrationManager.address)).to.bignumber.eq(bn(2000));
        expect(await d.erc20.balanceOf(d.rewards.address)).to.bignumber.eq(bn(0));
        expect(await d.bootstrapToken.balanceOf(d.rewards.address)).to.bignumber.eq(bn(0));
    });

    it('gets settings', async () => {
        const opts = {
            generalCommitteeAnnualBootstrap: fromTokenUnits(10),
            certifiedCommitteeAnnualBootstrap: fromTokenUnits(20),
            delegatorsStakingRewardsPercentMille: 3,
            stakingRewardsAnnualRateInPercentMille: 4,
            stakingRewardsAnnualCap: fromTokenUnits(50)
        };
        const d = await Driver.new(opts as any);

        expect(await d.rewards.getGeneralCommitteeAnnualBootstrap()).to.eq(opts.generalCommitteeAnnualBootstrap.toString());
        expect(await d.rewards.getCertifiedCommitteeAnnualBootstrap()).to.eq(opts.certifiedCommitteeAnnualBootstrap.toString());
        expect(await d.rewards.getDelegatorsStakingRewardsPercentMille()).to.eq(opts.delegatorsStakingRewardsPercentMille.toString());
        expect(await d.rewards.getAnnualStakingRewardsRatePercentMille()).to.eq(opts.stakingRewardsAnnualRateInPercentMille.toString());
        expect(await d.rewards.getAnnualStakingRewardsCap()).to.eq(opts.stakingRewardsAnnualCap.toString());

        expect((await d.rewards.getSettings()).generalCommitteeAnnualBootstrap).to.eq(opts.generalCommitteeAnnualBootstrap.toString());
        expect((await d.rewards.getSettings()).certifiedCommitteeAnnualBootstrap).to.eq(opts.certifiedCommitteeAnnualBootstrap.toString());
        expect((await d.rewards.getSettings()).delegatorsStakingRewardsPercentMille).to.eq(opts.delegatorsStakingRewardsPercentMille.toString());
        expect((await d.rewards.getSettings()).annualStakingRewardsRatePercentMille).to.eq(opts.stakingRewardsAnnualRateInPercentMille.toString());
        expect((await d.rewards.getSettings()).annualStakingRewardsCap).to.eq(opts.stakingRewardsAnnualCap.toString());
        expect((await d.rewards.getSettings()).active).to.be.true;
    });

    it("ensures only migration manager can activate and deactivate", async () => {
        const d = await Driver.new();

        await expectRejected(d.rewards.deactivate({from: d.functionalManager.address}), /sender is not the migration manager/);
        let r = await d.rewards.deactivate({from: d.migrationManager.address});
        expect(r).to.have.a.rewardDistributionDeactivatedEvent();

        await expectRejected(d.rewards.activate(await d.web3.txTimestamp(r), {from: d.functionalManager.address}), /sender is not the migration manager/);
        r = await d.rewards.activate(await d.web3.txTimestamp(r), {from: d.migrationManager.address});
        expect(r).to.have.a.rewardDistributionActivatedEvent();
    });

    it("allows anyone to migrate staking rewards to a new contract", async () => {
        const {d, committee} = await fullCommittee();

        const c0 = committee[0];

        /* top up staking rewards pool */
        const g = d.functionalManager;

        await evmIncreaseTime(d.web3, YEAR_IN_SECONDS);

        await expectRejected(d.rewards.migrateStakingRewardsBalance(c0.address), /Reward distribution must be deactivated for migration/);

        let r = await d.rewards.deactivate({from: d.migrationManager.address});
        expect(r).to.have.a.rewardDistributionDeactivatedEvent({});

        // Migrating to the same contract should revert
        await expectRejected(d.rewards.migrateStakingRewardsBalance(c0.address), /New rewards contract is not set/);

        await c0.stake(1); // trigger reward assignment

        const c0Balance = bn(await d.rewards.getStakingRewardsBalance(c0.address));
        expect(c0Balance).to.be.bignumber.greaterThan(bn(0));

        const c0GuardianBalance = fromTokenUnits((await (d.rewards as any).guardiansStakingRewards(c0.address)).balance);
        const c0DelegatorBalance = fromTokenUnits((await (d.rewards as any).delegatorsStakingRewards(c0.address)).balance);

        expectApproxEq(c0GuardianBalance.add(c0DelegatorBalance), c0Balance);

        const newRewardsContract = await d.web3.deploy('Rewards', [d.contractRegistry.address, d.registryAdmin.address, d.erc20.address, d.bootstrapToken.address,
          defaultDriverOptions.generalCommitteeAnnualBootstrap,
          defaultDriverOptions.certifiedCommitteeAnnualBootstrap,
          defaultDriverOptions.stakingRewardsAnnualRateInPercentMille,
          defaultDriverOptions.stakingRewardsAnnualCap,
          defaultDriverOptions.delegatorsStakingRewardsPercentMille
        ], null, d.session);
        await d.contractRegistry.setContract('rewards', newRewardsContract.address, true, {from: d.registryAdmin.address});

        // migrate to the new contract
        r = await d.rewards.migrateStakingRewardsBalance(c0.address);
        expect(r).to.have.withinContract(newRewardsContract).a.approx().stakingRewardsMigrationAcceptedEvent({
          migrator: d.rewards.address,
          to: c0.address,
          guardianBalance: c0GuardianBalance,
          delegatorBalance: c0DelegatorBalance
        });
        expect(r).to.have.withinContract(d.rewards).a.approx().stakingRewardsBalanceMigratedEvent({
          from: c0.address,
          guardianBalance: c0GuardianBalance,
          delegatorBalance: c0DelegatorBalance,
          toRewardsContract: newRewardsContract.address
        });
        expect(bn(await d.rewards.getStakingRewardsBalance(c0.address))).to.bignumber.eq(bn(0));
        expect(bn(await newRewardsContract.getStakingRewardsBalance(c0.address))).to.bignumber.eq(c0Balance);

        // anyone can migrate
        const migrator = d.newParticipant();
        await migrator.assignAndApproveOrbs(100, newRewardsContract.address);
        r = await newRewardsContract.acceptStakingRewardsMigration(c0.address, 40, 60, {from: migrator.address});
        expect(r).to.have.withinContract(newRewardsContract).a.stakingRewardsMigrationAcceptedEvent({
            migrator: migrator.address,
            to: c0.address,
            delegatorBalance: bn(40),
            guardianBalance: bn(60),
        });

    });

});
