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

describe('staking-rewards-level-flows', async () => {

  it('should distribute staking rewards to validators in committee', async () => {
    const d = await Driver.new();

    /* top up staking rewards pool */
    const g = d.rewardsGovernor;

    const annualRate = 12000;
    const poolAmount = 2000000000;
    const annualCap = poolAmount;

    let r = await d.stakingRewards.setAnnualRate(annualRate, annualCap, {from: g.address}); // todo monthly to annual
    const startTime = await txTimestamp(d.web3, r);
    await g.assignAndApproveOrbs(poolAmount, d.stakingRewards.address);
    await d.stakingRewards.topUpPool(poolAmount, {from: g.address});

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

    expect(await d.stakingRewards.getLastRewardsAssignment()).to.be.bignumber.equal(new BN(startTime));

    await sleep(3000);
    await evmIncreaseTime(d.web3, YEAR_IN_SECONDS*4);

    const assignRewardTxRes = await d.stakingRewards.assignRewards();
    const endTime = await txTimestamp(d.web3, assignRewardTxRes);
    const elapsedTime = endTime - startTime;

    const calcRewards = () => {
      const totalCommitteeStake = _.sumBy(validators, v => v.stake.toNumber());
      const annualAmount = Math.min(Math.floor(annualRate * totalCommitteeStake / 100000), annualCap);
      const rewards = new BN(Math.floor(annualAmount * elapsedTime / YEAR_IN_SECONDS));
      const rewardsArr = validators.map(v => rewards.mul(v.stake).div(bn(totalCommitteeStake)));
      const remainder =  rewards.sub(new BN(_.sumBy(rewardsArr, r => r.toNumber())));
      const remainderWinnerIdx = endTime % nValidators;
      rewardsArr[remainderWinnerIdx] = rewardsArr[remainderWinnerIdx].add(remainder);
      return rewardsArr;
    };

    const totalOrbsRewardsArr = calcRewards();

    const orbsBalances:BN[] = [];
    for (const v of validators) {
      orbsBalances.push(new BN(await d.stakingRewards.getRewardBalance(v.v.address)));
    }

    for (const v of validators) {
      const i = validators.indexOf(v);
      expect(orbsBalances[i]).to.be.bignumber.equal(new BN(totalOrbsRewardsArr[i]));
      expect(assignRewardTxRes).to.have.a.stakingRewardAssignedEvent({
        assignee: v.v.address,
        amount: bn(new BN(totalOrbsRewardsArr[i])),
        balance: bn(new BN(totalOrbsRewardsArr[i])) // todo: a test where balance is different than amount
      });

      r = await d.stakingRewards.distributeOrbsTokenRewards([v.v.address], [totalOrbsRewardsArr[i]], {from: v.v.address});
      expect(r).to.have.a.stakedEvent({
        stakeOwner: v.v.address,
        amount: totalOrbsRewardsArr[i],
        totalStakedAmount: new BN(v.stake).add(totalOrbsRewardsArr[i])
      });
      expect(r).to.have.a.committeeChangedEvent({
        orbsAddrs: validators.map(v => v.v.orbsAddress),
        addrs: validators.map(v => v.v.address),
        weights: validators.map((_v, _i) => (_i <= i) ? new BN(_v.stake).add(totalOrbsRewardsArr[_i]) : new BN(_v.stake))
      });
    }
  });

  it('should enforce the annual cap', async () => {
    const d = await Driver.new();

    /* top up staking rewards pool */
    const g = d.rewardsGovernor;

    const annualRate = 12000;
    const poolAmount = 2000000000;
    const annualCap = 100;

    let r = await d.stakingRewards.setAnnualRate(annualRate, annualCap, {from: g.address}); // todo monthly to annual
    const startTime = await txTimestamp(d.web3, r);
    await g.assignAndApproveOrbs(poolAmount, d.stakingRewards.address);
    await d.stakingRewards.topUpPool(poolAmount, {from: g.address});

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

    expect(await d.stakingRewards.getLastRewardsAssignment()).to.be.bignumber.equal(new BN(startTime));

    await sleep(3000);
    await evmIncreaseTime(d.web3, YEAR_IN_SECONDS*4);

    const assignRewardTxRes = await d.stakingRewards.assignRewards();
    const endTime = await txTimestamp(d.web3, assignRewardTxRes);
    const elapsedTime = endTime - startTime;

    const calcRewards = () => {
      const totalCommitteeStake = _.sumBy(validators, v => v.stake.toNumber());
      const annualAmount = Math.min(Math.floor(annualRate * totalCommitteeStake / 100000), annualCap);
      const rewards = new BN(Math.floor(annualAmount * elapsedTime / YEAR_IN_SECONDS));
      const rewardsArr = validators.map(v => rewards.mul(v.stake).div(bn(totalCommitteeStake)));
      const remainder =  rewards.sub(new BN(_.sumBy(rewardsArr, r => r.toNumber())));
      const remainderWinnerIdx = endTime % nValidators;
      rewardsArr[remainderWinnerIdx] = rewardsArr[remainderWinnerIdx].add(remainder);
      return rewardsArr;
    };

    const totalOrbsRewardsArr = calcRewards();

    const orbsBalances:BN[] = [];
    for (const v of validators) {
      orbsBalances.push(new BN(await d.stakingRewards.getRewardBalance(v.v.address)));
    }

    for (const v of validators) {
      const i = validators.indexOf(v);
      expect(orbsBalances[i]).to.be.bignumber.equal(new BN(totalOrbsRewardsArr[i]));
      expect(assignRewardTxRes).to.have.a.stakingRewardAssignedEvent({
        assignee: v.v.address,
        amount: bn(new BN(totalOrbsRewardsArr[i])),
        balance: bn(new BN(totalOrbsRewardsArr[i])) // todo: a test where balance is different than amount
      });

      r = await d.stakingRewards.distributeOrbsTokenRewards([v.v.address], [totalOrbsRewardsArr[i]], {from: v.v.address});
      expect(r).to.have.a.stakedEvent({
        stakeOwner: v.v.address,
        amount: totalOrbsRewardsArr[i],
        totalStakedAmount: new BN(v.stake).add(totalOrbsRewardsArr[i])
      });
      expect(r).to.have.a.committeeChangedEvent({
        orbsAddrs: validators.map(v => v.v.orbsAddress),
        addrs: validators.map(v => v.v.address),
        weights: validators.map((_v, _i) => (_i <= i) ? new BN(_v.stake).add(totalOrbsRewardsArr[_i]) : new BN(_v.stake))
      });
    }
  });
});
