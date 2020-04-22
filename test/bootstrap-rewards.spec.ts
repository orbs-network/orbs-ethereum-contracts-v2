import 'mocha';

import * as _ from "lodash";
import BN from "bn.js";
import {Driver, DEPLOYMENT_SUBSET_MAIN} from "./driver";
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
    const d = await Driver.new();

    /* top up bootstrap reward  pool */

    const g = d.rewardsGovernor;

    const annualAmount = 10000000;
    const poolAmount = annualAmount*12;

    let r = await d.bootstrapRewards.setGeneralCommitteeAnnualBootstrap(annualAmount, {from: g.address});
    const startTime = await txTimestamp(d.web3, r);
    await g.assignAndApproveExternalToken(poolAmount, d.bootstrapRewards.address);
    r = await d.bootstrapRewards.topUpBootstrapPool(poolAmount, {from: g.address});
    expect(r).to.have.a.bootstrapAddedToPoolEvent({
      added: bn(poolAmount),
      total: bn(poolAmount) // todo: a test where total is more than added
    });

    // create committee

    const initStakeLesser = new BN(17000);
    const v1 = d.newParticipant();
    await v1.stake(initStakeLesser);
    await v1.registerAsValidator();
    await v1.notifyReadyForCommittee();

    const initStakeLarger = new BN(21000);
    const v2 = d.newParticipant();
    await v2.stake(initStakeLarger);
    await v2.registerAsValidator();
    await v2.notifyReadyForCommittee();

    const validators = [{
      v: v2,
      stake: initStakeLarger
    }, {
      v: v1,
      stake: initStakeLesser
    }];

    const nValidators = validators.length;

    await sleep(3000);
    await evmIncreaseTime(d.web3, YEAR_IN_SECONDS*4);

    const assignRewardsTxRes = await d.bootstrapRewards.assignRewards();
    const endTime = await txTimestamp(d.web3, assignRewardsTxRes);
    const elapsedTime = endTime - startTime;

    const calcRewards = () => {
      const rewards = new BN(Math.floor(annualAmount * elapsedTime / YEAR_IN_SECONDS));
      return validators.map(() => rewards);
    };

    const totalExternalTokenRewardsArr = calcRewards();
    expect(assignRewardsTxRes).to.have.a.bootstrapRewardsAssignedEvent({
      assignees: validators.map(v => v.v.address),
      amounts: totalExternalTokenRewardsArr
    });

    const externalBalances:BN[] = [];
    for (const v of validators) {
      externalBalances.push(new BN(await d.bootstrapRewards.getBootstrapBalance(v.v.address)));
    }

    for (const v of validators) {
      const i = validators.indexOf(v);

      expect(externalBalances[i]).to.be.bignumber.equal(new BN(totalExternalTokenRewardsArr[i]));

      // claim the funds
      const expectedBalance = parseInt(await d.bootstrapRewards.getBootstrapBalance(v.v.address));
      expect(expectedBalance).to.be.equal(externalBalances[i].toNumber());
      await d.bootstrapRewards.withdrawFunds({from: v.v.address});
      const externalBalance = await d.externalToken.balanceOf(v.v.address);
      expect(new BN(externalBalance)).to.bignumber.equal(new BN(expectedBalance));
    }
  })
});
