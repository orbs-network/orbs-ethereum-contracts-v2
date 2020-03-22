import 'mocha';

import * as _ from "lodash";
import BN from "bn.js";
import {Driver, DEPLOYMENT_SUBSET_MAIN} from "./driver";
import chai from "chai";
import {feesAddedToBucketEvents, subscriptionChangedEvents} from "./event-parsing";
import {bn, evmIncreaseTime} from "./helpers";
import {TransactionReceipt} from "web3-core";
import {Web3Driver} from "../eth";

chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const MONTH_IN_SECONDS = 30*24*60*60;

async function txTimestamp(web3: Web3Driver, r: TransactionReceipt): Promise<number> { // TODO move
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
    let startTime = await txTimestamp(d.web3, r);

    const feeBuckets = feesAddedToBucketEvents(r);

    // all the payed rewards were added to a bucket
    const totalAdded = feeBuckets.reduce((t, l) => t.add(new BN(l.added)), new BN(0));
    expect(totalAdded).to.be.bignumber.equal(new BN(payment));

    // the first bucket was added to with proportion to the remaining time
    const secondsInFirstMonth = parseInt(feeBuckets[1].bucketId as string) - startTime;
    expect(parseInt(feeBuckets[0].added as string)).to.equal(Math.floor(secondsInFirstMonth * vcRate / MONTH_IN_SECONDS));

    // all middle buckets were added to by the monthly rate
    const middleBuckets = feeBuckets.filter((l, i) => i > 0 && i < feeBuckets.length - 1);
    expect(middleBuckets).to.have.length(feeBuckets.length - 2);
    middleBuckets.forEach(l => {
      expect(l.added).to.be.bignumber.equal(new BN(vcRate));
    });

    expect(await d.fees.getLastFeesAssignment()).to.be.bignumber.equal(new BN(startTime));

    // creating the VC has triggered reward assignment. We wish to ignore it, so we take the initial balance
    // and subtract it afterwards

    const initialOrbsBalances:BN[] = [];
    for (const v of validators) {
      initialOrbsBalances.push(new BN(await d.fees.getOrbsBalance(v.v.address)));
    }

    await sleep(3000);
    await evmIncreaseTime(d.web3, MONTH_IN_SECONDS*4);

    const assignFeesTxRes = await d.fees.assignFees();
    const endTime = await txTimestamp(d.web3, assignFeesTxRes);

    const calcFeeRewards = () => {
      let rewards = 0;
      for (const bucket of feeBuckets) {
        const bucketStartTime = Math.max(parseInt(bucket.bucketId as string), startTime);
        const bucketEndTime = bucketStartTime - (bucketStartTime % MONTH_IN_SECONDS) + MONTH_IN_SECONDS;
        const bucketRemainingTime = bucketEndTime - bucketStartTime;
        const bucketAmount = parseInt(bucket.added as string);
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
    expect(assignFeesTxRes).to.have.a.feesAssignedEvent({
      assignees: validators.map(v => v.v.address),
      orbs_amounts: totalOrbsRewardsArr
    });

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

  });

  it('should fill the correct fee buckets on subscription extension', async () => {
    const bucketId = (timestamp: number) => timestamp - timestamp % MONTH_IN_SECONDS;
    const d = await Driver.new();

    const vcRate = 3000000000;
    const subs = await d.newSubscriber('tier', vcRate);

    const initialDurationInMonths = 3;
    const firstPayment = initialDurationInMonths * vcRate;
    const appOwner = d.newParticipant();
    await d.erc20.assign(appOwner.address, firstPayment);
    await d.erc20.approve(subs.address, firstPayment, {from: appOwner.address});

    let r = await subs.createVC(firstPayment, DEPLOYMENT_SUBSET_MAIN, {from: appOwner.address});
    let startTime = await txTimestamp(d.web3, r);
    expect(r).to.have.a.subscriptionChangedEvent({
      expiresAt: bn(startTime + MONTH_IN_SECONDS * initialDurationInMonths)
    });
    const vcid = subscriptionChangedEvents(r)[0].vcid;

    const extensionInMonths = 2;
    const secondPayment = extensionInMonths * vcRate;
    await d.erc20.assign(appOwner.address, secondPayment);
    await d.erc20.approve(subs.address, secondPayment, {from: appOwner.address});
    r = await subs.extendSubscription(vcid, secondPayment, {from: appOwner.address});

    const firstBucketAmount = Math.floor((bucketId(startTime + MONTH_IN_SECONDS * (initialDurationInMonths + 1)) - (startTime + MONTH_IN_SECONDS * initialDurationInMonths)) * vcRate / MONTH_IN_SECONDS);
    expect(r).to.have.a.feesAddedToBucketEvent({
      bucketId: bucketId(startTime + MONTH_IN_SECONDS * initialDurationInMonths).toString(),
      added: firstBucketAmount.toString()
    });

    const secondBucketAmount = vcRate;
    expect(r).to.have.a.feesAddedToBucketEvent({
      bucketId: bn(bucketId(startTime + MONTH_IN_SECONDS * (initialDurationInMonths + 1))),
      added: secondBucketAmount.toString()
    });

    if (startTime != bucketId(startTime)) {
      expect(r).to.have.a.feesAddedToBucketEvent({
        bucketId: bucketId(startTime + MONTH_IN_SECONDS * (initialDurationInMonths + extensionInMonths)).toString(),
        added: (secondPayment - firstBucketAmount - secondBucketAmount).toString(),
      });
    }

  })

});
