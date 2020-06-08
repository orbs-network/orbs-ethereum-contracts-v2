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
import {bn, evmIncreaseTime, fromTokenUnits, toTokenUnits} from "./helpers";
import {gasReportEvents} from "./event-parsing";

declare const web3: Web3;

chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const expect = chai.expect;
const assert = chai.assert;

const BASE_STAKE = fromTokenUnits(1000000);
const MONTH_IN_SECONDS = 30*24*60*60;

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

async function getTotalBalances(d: Driver): Promise<{fees: string, staking: string, bootstrap: string}> {
    const r = await d.rewards.getTotalBalances();
    return {
        fees: r[0],
        staking: r[1],
        bootstrap: r[2]
    }
}

describe('rewards', async () => {
    it("maintains total balances", async () => {
        const d = await Driver.new();

        const poolAmount = fromTokenUnits(1000000);
        await d.erc20.assign(d.accounts[0], poolAmount);
        await d.erc20.approve(d.rewards.address, poolAmount);
        await d.rewards.setAnnualStakingRewardsRate(12000, poolAmount, {from: d.functionalOwner.address});
        await d.rewards.topUpStakingRewardsPool(poolAmount);

        await d.externalToken.assign(d.accounts[0], poolAmount);
        await d.externalToken.approve(d.rewards.address, poolAmount);
        await d.rewards.setGeneralCommitteeAnnualBootstrap(fromTokenUnits(12000), {from: d.functionalOwner.address});
        await d.rewards.setComplianceCommitteeAnnualBootstrap(fromTokenUnits(12000), {from: d.functionalOwner.address});
        await d.rewards.topUpBootstrapPool(poolAmount);

        const committee: Participant[] = await Promise.all(_.range(defaultDriverOptions.maxCommitteeSize).map(async () =>
            (await d.newValidator(BASE_STAKE, true, false, true)).v
        ));

        const monthlyRate = fromTokenUnits(1000);
        const subs = await d.newSubscriber('defaultTier', monthlyRate);
        const appOwner = d.newParticipant();

        await createVC(d, true, subs, monthlyRate, appOwner);

        await evmIncreaseTime(d.web3, MONTH_IN_SECONDS);
        await d.rewards.assignRewards();
        let expectedTotals = await sumBalances(d, committee);
        expect(await getTotalBalances(d)).to.deep.eq(expectedTotals);

        await d.rewards.withdrawFeeFunds({from: committee[0].address});
        expectedTotals = await sumBalances(d, committee);
        expect(await getTotalBalances(d)).to.deep.eq(expectedTotals);

        await d.rewards.withdrawBootstrapFunds({from: committee[0].address});
        expectedTotals = await sumBalances(d, committee);
        expect(await getTotalBalances(d)).to.deep.eq(expectedTotals);

        await d.rewards.distributeOrbsTokenStakingRewards(fromTokenUnits(1), 0, 1, 5, 0, [committee[0].address], [fromTokenUnits(1)], {from: committee[0].address});
        expectedTotals = await sumBalances(d, committee);
        expect(await getTotalBalances(d)).to.deep.eq(expectedTotals);

        await evmIncreaseTime(d.web3, MONTH_IN_SECONDS);
        await d.rewards.assignRewards();
        expectedTotals = await sumBalances(d, committee);
        expect(await getTotalBalances(d)).to.deep.eq(expectedTotals);

    });

});
