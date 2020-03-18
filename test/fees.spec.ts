import 'mocha';

import * as _ from "lodash";
import Web3 from "web3";
import BN from "bn.js";
import {Driver, DEPLOYMENT_SUBSET_MAIN} from "./driver";
import chai from "chai";
import {feeAddedToBucketEvents} from "./event-parsing";
import {evmIncreaseTime} from "./helpers";
import {web3} from "../eth";
import {TransactionReceipt} from "web3-core";

chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const MONTH_IN_SECONDS = 30*24*60*60;

async function txTimestamp(r: TransactionReceipt): Promise<number> { // TODO move
  return (await web3.eth.getBlock(r.blockNumber)).timestamp as number;
}

const expect = chai.expect;

async function sleep(ms): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

describe('fees-contract', async () => {

  it('should distribute fees to validators in committee', async () => {
    const d = await Driver.new();

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

    // create a new VC

    const vcRate = 3000000000;
    const subs = await d.newSubscriber('tier', vcRate);

    const appOwner = d.newParticipant();
    const payment = 12 * vcRate;
    await d.erc20.assign(appOwner.address, payment);
    await d.erc20.approve(subs.address, payment, {from: appOwner.address});

    let r = await subs.createVC(payment, DEPLOYMENT_SUBSET_MAIN, {from: appOwner.address});
    let startTime = await txTimestamp(r);

    const feeBuckets = feeAddedToBucketEvents(r);

    // all the payed rewards were added to a bucket
    const totalAdded = feeBuckets.reduce((t, l) => t.add(new BN(l.added)), new BN(0));
    expect(totalAdded).to.be.bignumber.equal(new BN(payment));

    // the first bucket was added to with proportion to the remaining time
    const secondsInFirstMonth = parseInt(feeBuckets[1].bucketId) - startTime;
    expect(parseInt(feeBuckets[0].added)).to.equal(Math.floor(secondsInFirstMonth * vcRate / MONTH_IN_SECONDS));

    // all middle buckets were added to by the monthly rate
    const middleBuckets = feeBuckets.filter((l, i) => i > 0 && i < feeBuckets.length - 1);
    expect(middleBuckets).to.have.length(feeBuckets.length - 2);
    middleBuckets.forEach(l => {
      expect(l.added).to.be.bignumber.equal(new BN(vcRate));
    });

    expect(await d.fees.getLastPayedAt()).to.be.bignumber.equal(new BN(startTime));

    // creating the VC has triggered reward assignment. We wish to ignore it, so we take the initial balance
    // and subtract it afterwards

    const initialOrbsBalances:BN[] = [];
    for (const v of validators) {
      initialOrbsBalances.push(new BN(await d.fees.getOrbsBalance(v.v.address)));
    }

    await sleep(3000);
    await evmIncreaseTime(MONTH_IN_SECONDS*4);

    r = await d.fees.assignFees();
    const endTime = await txTimestamp(r);
    const elapsedTime = endTime - startTime;

    const calcFeeRewards = () => {
      let rewards = 0;
      for (const bucket of feeBuckets) {
        const bucketStartTime = Math.max(parseInt(bucket.bucketId), startTime);
        const bucketEndTime = bucketStartTime - (bucketStartTime % MONTH_IN_SECONDS) + MONTH_IN_SECONDS;
        const bucketRemainingTime = bucketEndTime - bucketStartTime;
        const bucketAmount = parseInt(bucket.added);
        if (bucketStartTime < endTime) {
          const payedDuration = Math.min(endTime, bucketEndTime) - bucketStartTime;
          const amount = Math.floor(bucketAmount * payedDuration / bucketRemainingTime);
          rewards += amount;
        }
      }
      const rewardsArr = validators.map(() => Math.floor(rewards / validators.length));
      const remainder = rewards - _.sum(rewardsArr);
      const remainderWinnerIdx = endTime % nValidators;
      rewardsArr[remainderWinnerIdx] = rewardsArr[remainderWinnerIdx] + remainder;
      return rewardsArr.map(x => new BN(x));
    };

    // Calculate expected rewards from VC fees
    const totalOrbsRewardsArr = calcFeeRewards();

    const orbsBalances:BN[] = [];
    for (const v of validators) {
      orbsBalances.push(new BN(await d.fees.getOrbsBalance(v.v.address)));
    }

    for (const v of validators) {
      const i = validators.indexOf(v);
      let orbsBalance = orbsBalances[i].sub(initialOrbsBalances[i]);
      expect(orbsBalance).to.be.bignumber.equal(new BN(totalOrbsRewardsArr[i]));

      // withdraw the funds
      await d.fees.withdrawFunds({from: v.v.address});
      const actualBalance = await d.erc20.balanceOf(v.v.address);
      expect(new BN(actualBalance)).to.bignumber.equal(new BN(orbsBalances[i]));
    }

  })
});
