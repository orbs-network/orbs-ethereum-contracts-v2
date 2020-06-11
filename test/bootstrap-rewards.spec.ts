import 'mocha';

import * as _ from "lodash";
import BN from "bn.js";
import {Driver, Participant} from "./driver";
import chai from "chai";
import {bn, evmIncreaseTime, fromTokenUnits, toTokenUnits} from "./helpers";
import {TransactionReceipt} from "web3-core";
import {Web3Driver} from "../eth";
import {bootstrapRewardsAssignedEvents} from "./event-parsing";

chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const YEAR_IN_SECONDS = 365*24*60*60;

async function txTimestamp(web3: Web3Driver, r: TransactionReceipt): Promise<number> { // TODO move
  return (await web3.eth.getBlock(r.blockNumber)).timestamp as number;
}

const expect = chai.expect;

async function sleep(ms): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

describe('bootstrap-rewards-level-flows', async () => {

  it('should distribute bootstrap rewards to validators in committee', async () => {
    const d = await Driver.new({maxCommitteeSize: 4});

    /* top up bootstrap reward  pool */

    const g = d.functionalOwner;

    const annualAmountGeneral = fromTokenUnits(10000000);
    const annualAmountCompliance = fromTokenUnits(20000000);
    const poolAmount = annualAmountGeneral.add(annualAmountCompliance).mul(bn(6*12));

    await d.rewards.setGeneralCommitteeAnnualBootstrap(annualAmountGeneral, {from: g.address});
    await d.rewards.setComplianceCommitteeAnnualBootstrap(annualAmountCompliance, {from: g.address});

    // create committee

    const initStakeLesser = fromTokenUnits(17000);
    const initStakeLarger = fromTokenUnits(21000);

    const {v: v1} = await d.newValidator(initStakeLarger, true, false, true);
    const {v: v2} = await d.newValidator(initStakeLarger, false, false, true);
    const {v: v3} = await d.newValidator(initStakeLesser, true, false, true);
    const {v: v4, r: firstAssignTxRes} = await d.newValidator(initStakeLesser, false, false, true);
    const startTime = await txTimestamp(d.web3, firstAssignTxRes);
    const generalCommittee: Participant[] = [v1, v2, v3, v4];

    const initialBalance:BN[] = [];
    for (const v of generalCommittee) {
      initialBalance.push(new BN(await d.rewards.getBootstrapBalance(v.address)));
    }

    await sleep(3000);
    await evmIncreaseTime(d.web3, YEAR_IN_SECONDS*4);

    const assignRewardsTxRes = await d.rewards.assignRewards();
    const endTime = await txTimestamp(d.web3, assignRewardsTxRes);
    const elapsedTime = endTime - startTime;

    const calcRewards = (annualRate) => fromTokenUnits(toTokenUnits(annualRate).mul(bn(elapsedTime)).div(bn(YEAR_IN_SECONDS)));

    const expectedGeneralCommitteeRewards = calcRewards(annualAmountGeneral);
    const expectedComplianceCommitteeRewards = expectedGeneralCommitteeRewards.add(calcRewards(annualAmountCompliance));

    expect(assignRewardsTxRes).to.have.a.bootstrapRewardsAssignedEvent({
      generalValidatorAmount: expectedGeneralCommitteeRewards.toString(),
      certifiedValidatorAmount: expectedComplianceCommitteeRewards.toString()
    });

    const tokenBalances:BN[] = [];
    for (const v of generalCommittee) {
      tokenBalances.push(new BN(await d.rewards.getBootstrapBalance(v.address)));
    }

    // Pool can be topped up after assignment
    await g.assignAndApproveExternalToken(poolAmount, d.rewards.address);
    let r = await d.rewards.topUpBootstrapPool(poolAmount, {from: g.address});
    expect(r).to.have.a.bootstrapAddedToPoolEvent({
      added: bn(poolAmount),
      total: bn(poolAmount) // todo: a test where total is more than added
    });

    for (const v of generalCommittee) {
      const i = generalCommittee.indexOf(v);

      const expectedRewards = (i % 2 == 0) ? expectedComplianceCommitteeRewards : expectedGeneralCommitteeRewards;
      expect(tokenBalances[i].sub(initialBalance[i])).to.be.bignumber.equal(expectedRewards.toString());

      // claim the funds
      await d.rewards.withdrawBootstrapFunds({from: v.address});
      const tokenBalance = await d.externalToken.balanceOf(v.address);
      expect(new BN(tokenBalance)).to.bignumber.equal(new BN(tokenBalances[i]));
    }
  })
});
