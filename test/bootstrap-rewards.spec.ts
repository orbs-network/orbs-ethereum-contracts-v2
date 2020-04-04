import 'mocha';

import * as _ from "lodash";
import BN from "bn.js";
import {Driver, Participant} from "./driver";
import chai from "chai";
import {bn, evmIncreaseTime} from "./helpers";
import {TransactionReceipt} from "web3-core";
import {Web3Driver} from "../eth";

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

    const g = d.rewardsGovernor;

    const annualAmountGeneral = 10000000;
    const annualAmountCompliance = 20000000;
    const poolAmount = (annualAmountGeneral + annualAmountCompliance) * 6 * 12;

    await d.bootstrapRewards.setGeneralCommitteeAnnualBootstrap(annualAmountGeneral, {from: g.address});
    let r = await d.bootstrapRewards.setComplianceCommitteeAnnualBootstrap(annualAmountCompliance, {from: g.address});
    const startTime = await txTimestamp(d.web3, r);

    await g.assignAndApproveExternalToken(poolAmount, d.bootstrapRewards.address);
    r = await d.bootstrapRewards.topUpBootstrapPool(poolAmount, {from: g.address});
    expect(r).to.have.a.bootstrapAddedToPoolEvent({
      added: bn(poolAmount),
      total: bn(poolAmount) // todo: a test where total is more than added
    });

    // create committee

    const initStakeLesser = 17000;
    const initStakeLarger = 21000;

    const {v: v1} = await d.newValidator(initStakeLarger, true, false, true);
    const {v: v2} = await d.newValidator(initStakeLesser, false, false, true);
    const {v: v3} = await d.newValidator(initStakeLarger, true, false, true);
    const {v: v4} = await d.newValidator(initStakeLesser, false, false, true);

    const generalCommittee: Participant[] = [v1, v2, v3, v4];
    const complianceCommittee: Participant[] = [v1, v3];

    await sleep(3000);
    await evmIncreaseTime(d.web3, YEAR_IN_SECONDS*4);

    const assignRewardsTxRes = await d.bootstrapRewards.assignRewards();
    const endTime = await txTimestamp(d.web3, assignRewardsTxRes);
    const elapsedTime = endTime - startTime;

    const calcRewards = (annualRate) => Math.floor(annualRate * elapsedTime / YEAR_IN_SECONDS);

    const expectedGeneralCommitteeRewards = calcRewards(annualAmountGeneral);
    expect(assignRewardsTxRes).to.have.a.bootstrapRewardsAssignedEvent({
      assignees: generalCommittee.map(v => v.address),
      amounts: generalCommittee.map(() => expectedGeneralCommitteeRewards.toString())
    });

    const expectedComplianceCommitteeRewards = calcRewards(annualAmountCompliance);
    expect(assignRewardsTxRes).to.have.a.bootstrapRewardsAssignedEvent({
      assignees: complianceCommittee.map(v => v.address),
      amounts: complianceCommittee.map(() => expectedComplianceCommitteeRewards.toString())
    });

    const tokenBalances:BN[] = [];
    for (const v of generalCommittee) {
      tokenBalances.push(new BN(await d.bootstrapRewards.getBootstrapBalance(v.address)));
    }

    for (const v of generalCommittee) {
      const i = generalCommittee.indexOf(v);

      const expectedBalance = expectedGeneralCommitteeRewards + ((i % 2 == 0) ? expectedComplianceCommitteeRewards : 0);
      expect(tokenBalances[i]).to.be.bignumber.equal(expectedBalance.toString());

      // claim the funds
      await d.bootstrapRewards.withdrawFunds({from: v.address});
      const tokenBalance = await d.externalToken.balanceOf(v.address);
      expect(new BN(tokenBalance)).to.bignumber.equal(new BN(expectedBalance));
    }

  })
});
