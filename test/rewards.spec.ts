import 'mocha';
import Web3 from "web3";
import BN from "bn.js";
import * as _ from "lodash";
import {
    defaultDriverOptions,
    Driver,
    Participant, ZERO_ADDR
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

async function fullCommittee(stakes?: BN[] | null, numVCs=2, opts?: {
    stakingRewardsAnnualRate?: BN,
    stakingRewardsAnnualCap?: BN,
    minSelfStakePercentMille?: BN
}): Promise<{d: Driver, committee: Participant[]}> {
    opts = opts || {};

    const stakingRewardsAnnualRate: BN = opts.stakingRewardsAnnualRate || STAKING_REWARDS_ANNUAL_RATE;
    const stakingRewardsAnnualCap: BN = opts.stakingRewardsAnnualCap || STAKING_REWARDS_ANNUAL_CAP;
    const minSelfStakePercentMille: BN = opts.minSelfStakePercentMille || MIN_SELF_STAKE_PERCENT_MILLE;

    const d = await Driver.new({maxCommitteeSize: MAX_COMMITTEE, minSelfStakePercentMille: minSelfStakePercentMille.toNumber(), defaultDelegatorsStakingRewardsPercentMille: DELEGATOR_REWARDS_PERCENT_MILLE});

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

    const settings = await d.rewards.getSettings();
    const cap = bn(settings.annualStakingRewardsCap);
    const rate = bn(settings.annualStakingRewardsRatePercentMille);
    const ratio = bn(await d.rewards.getGuardianDelegatorsStakingRewardsPercentMille(guardian.address));

    const actualRate = BN.min(totalWeight.mul(rate).div(bn(100000)), cap).mul(bn(100000)).div(totalWeight);

    const delegatorStake = bn((await d.delegations.getDelegationInfo(delegator.address)).delegatorStake);
    const guardianStake = bn((await d.delegations.getDelegationInfo(guardian.address)).delegatorStake);
    const guardianDelegatedStake = bn(await d.delegations.getDelegatedStake(guardian.address));

    const totalRewards = guardianWeight.mul(actualRate).mul(bn(duration)).div(bn(YEAR_IN_SECONDS * 100000));
    const totalDelegatorRewards = totalRewards.mul(ratio).div(bn(100000));
    let guardianRewards = roundTo48(totalRewards.mul(bn(100000).sub(ratio)).div(bn(100000)));
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

describe('rewards', async () => {

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

        expect(c0AssignedFees).to.be.bignumber.gt(bn(0));
        expect(c1AssignedFees).to.be.bignumber.gt(bn(0));
        expect(c0AssignedBootstrap).to.be.bignumber.gt(bn(0));
        expect(c1AssignedBootstrap).to.be.bignumber.gt(bn(0));
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

        expect(c0AssignedFees).to.be.bignumber.gt(bn(0));
        expect(c1AssignedFees).to.be.bignumber.gt(bn(0));
        expect(c0AssignedBootstrap).to.be.bignumber.gt(bn(0));
        expect(c1AssignedBootstrap).to.be.bignumber.gt(bn(0));
    });

    it('erc20 of bootstrap token is total bootstrap balance', async () => {
        const {d, committee} = await fullCommittee([fromTokenUnits(4000), fromTokenUnits(3000), fromTokenUnits(2000), fromTokenUnits(1000)], 1);

        const PERIOD = MONTH_IN_SECONDS * 2;

        await evmIncreaseTimeForQueries(d.web3, PERIOD);

        for (const c of committee) {
            await c.readyToSync(); // leave committee
        }

        let total = bn(0);
        for (const c of committee) {
            total = total.add(bn(await d.rewards.getBootstrapBalance(c.address)));
        }
        expect(await d.bootstrapToken.balanceOf(d.rewards.address)).to.bignumber.eq(total);
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

        expect(total).to.be.bignumber.gt(bn(0));
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

        expect(cTotal).to.be.bignumber.gt(bn(0));
        expect(dTotal).to.be.bignumber.gt(bn(0));
    });

    it('tracks total unclaimed staking rewards', async () => {
        const {d, committee} = await fullCommittee([fromTokenUnits(4000), fromTokenUnits(3000), fromTokenUnits(2000), fromTokenUnits(1000)], 1);

        const PERIOD = MONTH_IN_SECONDS * 2;

        await evmIncreaseTimeForQueries(d.web3, PERIOD);

        let total = bn(0);
        for (const c of committee) {
            total = total.add(bn(await d.rewards.getStakingRewardsBalance(c.address)));
        }
        expectApproxEq((await d.rewards.getStakingRewardsState()).unclaimedStakingRewards, total);
    });

    it('properly assigns staking rewards to a guardian who becomes a delegator', async () => {
        const {d, committee} = await fullCommittee([fromTokenUnits(4000), fromTokenUnits(3000), fromTokenUnits(2000), fromTokenUnits(1000)], 1);

        const c0 = committee[0];
        const c1 = committee[1];

        const PERIOD = MONTH_IN_SECONDS * 2;

        let c0Total = bn(0);
        let c1Total = bn(0);

        expectApproxEq(await d.rewards.getStakingRewardsBalance(c0.address), c0Total);
        expectApproxEq(await d.rewards.getStakingRewardsBalance(c1.address), c1Total);

        await evmIncreaseTimeForQueries(d.web3, PERIOD);

        c0Total = c0Total.add((await stakingRewardsForDuration(d, PERIOD, c0, c0)).guardianRewards);
        expectApproxEq(await d.rewards.getStakingRewardsBalance(c0.address), c0Total);
        c1Total = c1Total.add((await stakingRewardsForDuration(d, PERIOD, c1, c1)).guardianRewards);
        expectApproxEq(await d.rewards.getStakingRewardsBalance(c1.address), c1Total);

        c0.delegate(c1);

        expectApproxEq(await d.rewards.getStakingRewardsBalance(c0.address), c0Total);
        expectApproxEq(await d.rewards.getStakingRewardsBalance(c1.address), c1Total);

        await evmIncreaseTimeForQueries(d.web3, PERIOD);

        c0Total = c0Total.add((await stakingRewardsForDuration(d, PERIOD, c0, c1)).delegatorRewards);
        expectApproxEq(await d.rewards.getStakingRewardsBalance(c0.address), c0Total);

        c1Total = c1Total.add((await stakingRewardsForDuration(d, PERIOD, c0, c1)).guardianRewards);
        expectApproxEq(await d.rewards.getStakingRewardsBalance(c1.address), c1Total);

        // Claim entire amount
        let r = await d.rewards.claimStakingRewards(c0.address);
        expect(r).to.have.approx().a.stakingRewardsClaimedEvent({
            addr: c0.address,
            amount: c0Total
        });

        r = await d.rewards.claimStakingRewards(c1.address);
        expect(r).to.have.approx().a.stakingRewardsClaimedEvent({
            addr: c1.address,
            amount: c1Total
        });

        expect(c0Total).to.be.bignumber.gt(bn(0));
        expect(c1Total).to.be.bignumber.gt(bn(0));
    });

    it('properly handles a change in maxCommitteeSize', async () => {
        const {d, committee} = await fullCommittee([fromTokenUnits(4000), fromTokenUnits(3000), fromTokenUnits(2000), fromTokenUnits(1000)], 1);

        const c0 = committee[0];
        const c2 = committee[2];
        const c3 = committee[3];

        const PERIOD = MONTH_IN_SECONDS * 2;

        let c0Total = bn(0);
        let c2Total = bn(0);
        let c3Total = bn(0);

        expectApproxEq(await d.rewards.getStakingRewardsBalance(c0.address), c0Total);
        expectApproxEq(await d.rewards.getStakingRewardsBalance(c2.address), c2Total);
        expectApproxEq(await d.rewards.getStakingRewardsBalance(c3.address), c3Total);

        await evmIncreaseTimeForQueries(d.web3, PERIOD);

        c0Total = c0Total.add((await stakingRewardsForDuration(d, PERIOD, c0, c0)).guardianRewards);
        expectApproxEq(await d.rewards.getStakingRewardsBalance(c0.address), c0Total);
        c2Total = c2Total.add((await stakingRewardsForDuration(d, PERIOD, c2, c2)).guardianRewards);
        expectApproxEq(await d.rewards.getStakingRewardsBalance(c2.address), c2Total);
        c3Total = c3Total.add((await stakingRewardsForDuration(d, PERIOD, c3, c3)).guardianRewards);
        expectApproxEq(await d.rewards.getStakingRewardsBalance(c3.address), c3Total);

        await d.committee.setMaxCommitteeSize(2, {from: d.functionalManager.address});

        expectApproxEq(await d.rewards.getStakingRewardsBalance(c0.address), c0Total);
        expectApproxEq(await d.rewards.getStakingRewardsBalance(c2.address), c2Total);
        expectApproxEq(await d.rewards.getStakingRewardsBalance(c3.address), c3Total);

        await evmIncreaseTimeForQueries(d.web3, PERIOD);

        c0Total = c0Total.add((await stakingRewardsForDuration(d, PERIOD, c0, c0)).guardianRewards);
        expectApproxEq(await d.rewards.getStakingRewardsBalance(c0.address), c0Total);

        expectApproxEq(await d.rewards.getStakingRewardsBalance(c2.address), c2Total);
        expectApproxEq(await d.rewards.getStakingRewardsBalance(c3.address), c3Total);

        // Claim entire amount
        let r = await d.rewards.claimStakingRewards(c0.address);
        expect(r).to.have.approx().a.stakingRewardsClaimedEvent({
            addr: c0.address,
            amount: c0Total
        });

        r = await d.rewards.claimStakingRewards(c2.address);
        expect(r).to.have.approx().a.stakingRewardsClaimedEvent({
            addr: c2.address,
            amount: c2Total
        });

        r = await d.rewards.claimStakingRewards(c3.address);
        expect(r).to.have.approx().a.stakingRewardsClaimedEvent({
            addr: c3.address,
            amount: c3Total
        });

        expect(c0Total).to.be.bignumber.gt(bn(0));
        expect(c3Total).to.be.bignumber.gt(bn(0));
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
            defaultDelegatorsStakingRewardsPercentMille: 3,
            stakingRewardsAnnualRateInPercentMille: 4,
            stakingRewardsAnnualCap: fromTokenUnits(50)
        };
        const d = await Driver.new(opts as any);

        expect((await d.rewards.getSettings()).generalCommitteeAnnualBootstrap).to.eq(opts.generalCommitteeAnnualBootstrap.toString());
        expect((await d.rewards.getSettings()).certifiedCommitteeAnnualBootstrap).to.eq(opts.certifiedCommitteeAnnualBootstrap.toString());
        expect((await d.rewards.getSettings()).defaultDelegatorsStakingRewardsPercentMille).to.eq(opts.defaultDelegatorsStakingRewardsPercentMille.toString());
        expect((await d.rewards.getSettings()).annualStakingRewardsRatePercentMille).to.eq(opts.stakingRewardsAnnualRateInPercentMille.toString());
        expect((await d.rewards.getSettings()).annualStakingRewardsCap).to.eq(opts.stakingRewardsAnnualCap.toString());
        expect((await d.rewards.getSettings()).rewardAllocationActive).to.be.true;
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

        await evmIncreaseTime(d.web3, YEAR_IN_SECONDS);

        await expectRejected(d.rewards.migrateRewardsBalance(c0.address), /Reward distribution must be deactivated for migration/);

        let r = await d.rewards.deactivate({from: d.migrationManager.address});
        expect(r).to.have.a.rewardDistributionDeactivatedEvent({});

        // Migrating to the same contract should revert
        await expectRejected(d.rewards.migrateRewardsBalance(c0.address), /New rewards contract is not set/);

        // trigger reward assignment
        await c0.stake(1);
        await c0.readyToSync();
        await c0.readyForCommittee();

        const c0StakingBalance = bn(await d.rewards.getStakingRewardsBalance(c0.address));
        expect(c0StakingBalance).to.be.bignumber.greaterThan(bn(0));

        const c0GuardianStakingBalance = fromTokenUnits((await (d.rewards as any).guardiansStakingRewards(c0.address)).balance);
        const c0DelegatorStakingBalance = fromTokenUnits((await (d.rewards as any).delegatorsStakingRewards(c0.address)).balance);

        expectApproxEq(c0GuardianStakingBalance.add(c0DelegatorStakingBalance), c0StakingBalance);

        const c0BootstrapBalance = bn(await d.rewards.getBootstrapBalance(c0.address));
        expect(c0BootstrapBalance).to.be.bignumber.greaterThan(bn(0));

        const c0FeeBalance = bn(await d.rewards.getFeeBalance(c0.address));
        expect(c0FeeBalance).to.be.bignumber.greaterThan(bn(0));

        const newRewardsContract = await d.web3.deploy('Rewards', [d.contractRegistry.address, d.registryAdmin.address, d.erc20.address, d.bootstrapToken.address,
          defaultDriverOptions.generalCommitteeAnnualBootstrap,
          defaultDriverOptions.certifiedCommitteeAnnualBootstrap,
          defaultDriverOptions.stakingRewardsAnnualRateInPercentMille,
          defaultDriverOptions.stakingRewardsAnnualCap,
          defaultDriverOptions.defaultDelegatorsStakingRewardsPercentMille,
          defaultDriverOptions.maxDelegatorsStakingRewardsPercentMille,
          ZERO_ADDR,
          []
        ], null, d.session);
        await d.contractRegistry.setContract('rewards', newRewardsContract.address, true, {from: d.registryAdmin.address});

        // migrate to the new contract
        r = await d.rewards.migrateRewardsBalance(c0.address);
        expect(r).to.have.withinContract(newRewardsContract).a.approx().rewardsBalanceMigrationAcceptedEvent({
          from: d.rewards.address,
          to: c0.address,
          guardianStakingRewards: c0GuardianStakingBalance.toString(),
          delegatorStakingRewards: c0DelegatorStakingBalance.toString(),
          bootstrapRewards: c0BootstrapBalance.toString(),
          fees: c0FeeBalance.toString()
        });
        expect(r).to.have.withinContract(d.rewards).a.approx().rewardsBalanceMigratedEvent({
          from: c0.address,
          guardianStakingRewards: c0GuardianStakingBalance,
          delegatorStakingRewards: c0DelegatorStakingBalance,
          bootstrapRewards: c0BootstrapBalance,
          fees: c0FeeBalance,
          toRewardsContract: newRewardsContract.address
        });
        expect(r).to.have.withinContract(d.erc20).a.approx().transferEvent({
            from: d.rewards.address,
            to: newRewardsContract.address,
            value: bn(c0FeeBalance).add(c0GuardianStakingBalance).add(c0DelegatorStakingBalance)
        });
        expect(r).to.have.withinContract(d.bootstrapToken).a.approx().transferEvent({
            from: d.rewards.address,
            to: newRewardsContract.address,
            value: bn(c0BootstrapBalance)
        });
        expect(bn(await d.rewards.getStakingRewardsBalance(c0.address))).to.bignumber.eq(bn(0));
        expect(bn(await d.rewards.getBootstrapBalance(c0.address))).to.bignumber.eq(bn(0));
        expect(bn(await d.rewards.getFeeBalance(c0.address))).to.bignumber.eq(bn(0));
        expectApproxEq(bn(await newRewardsContract.getStakingRewardsBalance(c0.address)), c0StakingBalance);
        expectApproxEq(bn(await newRewardsContract.getBootstrapBalance(c0.address)), c0BootstrapBalance);
        expectApproxEq(bn(await newRewardsContract.getFeeBalance(c0.address)), c0FeeBalance);

        // anyone can migrate
        const migrator = d.newParticipant();
        await migrator.assignAndApproveOrbs(180, newRewardsContract.address);
        await migrator.assignAndApproveExternalToken(100, newRewardsContract.address);
        r = await newRewardsContract.acceptRewardsBalanceMigration(c0.address, 40, 60, 80, 100, {from: migrator.address});
        expect(r).to.have.withinContract(newRewardsContract).a.rewardsBalanceMigrationAcceptedEvent({
            from: migrator.address,
            to: c0.address,
            guardianStakingRewards: bn(40),
            delegatorStakingRewards: bn(60),
            fees: bn(80),
            bootstrapRewards: bn(100)
        });
        expect(r).to.have.withinContract(d.erc20).a.approx().transferEvent({
            from: migrator.address,
            to: newRewardsContract.address,
            value: bn(180)
        });
        expect(r).to.have.withinContract(d.bootstrapToken).a.approx().transferEvent({
            from: migrator.address,
            to: newRewardsContract.address,
            value: bn(100)
        });

    });

    it("updates guardian delegator rewards ratio", async () => {
        const {d, committee} = await fullCommittee();

        const d0 = d.newParticipant();
        await d0.stake(fromTokenUnits(1000));
        const c0 = committee[0];
        await d0.delegate(c0);

        const PERIOD = MONTH_IN_SECONDS*2;

        let cTotal = bn(0);
        let dTotal = bn(0);

        const checkAndUpdate = async (updater?: ()=>Promise<void>) => {
            expectApproxEq(await d.rewards.getStakingRewardsBalance(c0.address), cTotal);
            expectApproxEq(await d.rewards.getStakingRewardsBalance(d0.address), dTotal);

            if (updater) {
                await updater();
            }
            await evmIncreaseTimeForQueries(d.web3, PERIOD);

            cTotal = cTotal.add((await stakingRewardsForDuration(d, PERIOD, c0, c0)).guardianRewards);
            expectApproxEq(await d.rewards.getStakingRewardsBalance(c0.address), cTotal);

            dTotal = dTotal.add((await stakingRewardsForDuration(d, PERIOD, d0, c0)).delegatorRewards);
            expectApproxEq(await d.rewards.getStakingRewardsBalance(d0.address), dTotal);
        }

        await checkAndUpdate();

        await checkAndUpdate(async () => {
            let r = await d.rewards.setGuardianDelegatorsStakingRewardsPercentMille(bn(100000).sub(DELEGATOR_REWARDS_PERCENT_MILLE), {from: c0.address});
            expect(r).to.have.a.guardianDelegatorsStakingRewardsPercentMilleUpdatedEvent({
                guardian: c0.address,
                delegatorsStakingRewardsPercentMille: bn(100000).sub(DELEGATOR_REWARDS_PERCENT_MILLE)
            });
        });

        await checkAndUpdate(async () => {
            await c0.stake(1); // trigger reward assignment on the previous period
            let r = await d.rewards.setMaxDelegatorsStakingRewardsPercentMille(bn(11000), {from: d.functionalManager.address});
            expect(r).to.have.a.maxDelegatorsStakingRewardsChangedEvent({
                maxDelegatorsStakingRewardsPercentMille: bn(11000)
            });
        });

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

        expect(cTotal).to.be.bignumber.gt(bn(0));
        expect(dTotal).to.be.bignumber.gt(bn(0));
    });

    it("does not allow setting guardian and default reward ratios bigger than the maximum", async () => {
        const d = await Driver.new({maxDelegatorsStakingRewardsPercentMille: 55000, defaultDelegatorsStakingRewardsPercentMille: 55000});
        const p = d.newParticipant();

        await expectRejected(d.rewards.setGuardianDelegatorsStakingRewardsPercentMille(55001), /delegatorRewardsPercentMille must not be larger than maxDelegatorsStakingRewardsPercentMille/)
        let r = await d.rewards.setGuardianDelegatorsStakingRewardsPercentMille(55000);
        expect(r).to.have.a.guardianDelegatorsStakingRewardsPercentMilleUpdatedEvent({delegatorsStakingRewardsPercentMille: bn(55000)})

        await expectRejected(d.rewards.setGuardianDelegatorsStakingRewardsPercentMille(55001, {from: d.functionalManager.address}), /delegatorRewardsPercentMille must not be larger than maxDelegatorsStakingRewardsPercentMille/);
    });

    it("considers max allowed ratio when getting the guardian ratio", async () => {
        const d = await Driver.new({maxDelegatorsStakingRewardsPercentMille: 55000, defaultDelegatorsStakingRewardsPercentMille: 55000});
        const p = d.newParticipant();

        let r = await d.rewards.setGuardianDelegatorsStakingRewardsPercentMille(55000);
        expect(r).to.have.a.guardianDelegatorsStakingRewardsPercentMilleUpdatedEvent({delegatorsStakingRewardsPercentMille: bn(55000)})

        expect(await d.rewards.getGuardianDelegatorsStakingRewardsPercentMille(p.address)).to.bignumber.eq(bn(55000));
        await d.rewards.setMaxDelegatorsStakingRewardsPercentMille(20000, {from: d.functionalManager.address});
        expect(await d.rewards.getGuardianDelegatorsStakingRewardsPercentMille(p.address)).to.bignumber.eq(bn(20000));
    });

    it("does not update rewards when deactivated", async () => {
        const {d, committee} = await fullCommittee();

        const PERIOD = MONTH_IN_SECONDS * 2;

        await evmIncreaseTimeForQueries(d.web3, PERIOD);

        const c0StakingBefore = bn(await d.rewards.getStakingRewardsBalance(committee[0].address));
        const c0BootstrapBefore = bn(await d.rewards.getBootstrapBalance(committee[0].address));
        const c0FeesBefore = bn(await d.rewards.getFeeBalance(committee[0].address));

        expect(c0StakingBefore).to.be.bignumber.gt(bn(0));
        expect(c0BootstrapBefore).to.be.bignumber.gt(bn(0));
        expect(c0FeesBefore).to.be.bignumber.gt(bn(0));

        let r = await d.rewards.deactivate({from: d.migrationManager.address});
        expect(r).to.have.a.rewardDistributionDeactivatedEvent();
        const deactivationTime = await d.web3.txTimestamp(r);

        const c0StakingAfter = bn(await d.rewards.getStakingRewardsBalance(committee[0].address));
        const c0BootstrapAfter = bn(await d.rewards.getBootstrapBalance(committee[0].address));
        const c0FeesAfter = bn(await d.rewards.getFeeBalance(committee[0].address));

        expectApproxEq(c0StakingBefore, c0StakingAfter);
        expectApproxEq(c0BootstrapBefore, c0BootstrapAfter);
        expectApproxEq(c0FeesBefore, c0FeesAfter);

        await evmIncreaseTimeForQueries(d.web3, PERIOD);

        expect(await d.rewards.getStakingRewardsBalance(committee[0].address)).to.be.bignumber.eq(c0StakingAfter);
        expect(await d.rewards.getBootstrapBalance(committee[0].address)).to.be.bignumber.eq(c0BootstrapAfter);
        expect(await d.rewards.getFeeBalance(committee[0].address)).to.be.bignumber.eq(c0FeesAfter);

        await evmIncreaseTimeForQueries(d.web3, PERIOD);

        expect(await d.rewards.getStakingRewardsBalance(committee[0].address)).to.be.bignumber.eq(c0StakingAfter);
        expect(await d.rewards.getBootstrapBalance(committee[0].address)).to.be.bignumber.eq(c0BootstrapAfter);
        expect(await d.rewards.getFeeBalance(committee[0].address)).to.be.bignumber.eq(c0FeesAfter);

        r = await d.rewards.activate(deactivationTime, {from: d.migrationManager.address});
        expect(r).to.have.a.rewardDistributionActivatedEvent();

        expectApproxEq(await d.rewards.getStakingRewardsBalance(committee[0].address), c0StakingAfter.mul(bn(3)));
        expectApproxEq(await d.rewards.getBootstrapBalance(committee[0].address), c0BootstrapAfter.mul(bn(3)));
        expectApproxEq(await d.rewards.getFeeBalance(committee[0].address), c0FeesAfter.mul(bn(3)));
    });

    it("migrates guardian settings from previous contract", async () => {
        const d = await Driver.new();

        const guardians = _.range(4).map(() => d.newParticipant());
        const ratios = [bn(1000), bn(2000), bn(3000), bn(4000)];
        for (const [guardian, ratio] of _.zip(guardians, ratios)) {
            await d.rewards.setGuardianDelegatorsStakingRewardsPercentMille(ratio, {from: (guardian as Participant).address});
        }

        const newRewardsContract = await d.web3.deploy('Rewards', [d.contractRegistry.address, d.registryAdmin.address, d.erc20.address, d.bootstrapToken.address,
            defaultDriverOptions.generalCommitteeAnnualBootstrap,
            defaultDriverOptions.certifiedCommitteeAnnualBootstrap,
            defaultDriverOptions.stakingRewardsAnnualRateInPercentMille,
            defaultDriverOptions.stakingRewardsAnnualCap,
            defaultDriverOptions.defaultDelegatorsStakingRewardsPercentMille,
            defaultDriverOptions.maxDelegatorsStakingRewardsPercentMille,
            d.rewards.address,
            guardians.map(g => g.address)
        ], null, d.session);

        const creationTx = await newRewardsContract.getCreationTx();
        for (const [g, ratio] of _.zip(guardians, ratios)) {
            const guardian = g as Participant;
            expect(creationTx).to.have.a.guardianDelegatorsStakingRewardsPercentMilleUpdatedEvent({
                guardian: guardian.address,
                delegatorsStakingRewardsPercentMille: ratio
            });
            expect(await newRewardsContract.getGuardianDelegatorsStakingRewardsPercentMille(guardian.address)).to.bignumber.eq(ratio);
        }

    });
});
