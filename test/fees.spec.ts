import 'mocha';

import * as _ from "lodash";
import BN from "bn.js";
import {Driver, DEPLOYMENT_SUBSET_MAIN, Participant} from "./driver";
import chai from "chai";
import {feesAddedToBucketEvents, subscriptionChangedEvents, vcCreatedEvents} from "./event-parsing";
import {bn, evmIncreaseTime} from "./helpers";
import {TransactionReceipt} from "web3-core";
import {Web3Driver} from "../eth";
import {FeesAddedToBucketEvent} from "../typings/fees-contract";

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

  it('should distribute fees to validators in general and compliance committees', async () => {
    const d = await Driver.new({maxCommitteeSize: 4});

    // create committee

    const initStakeLesser = 17000;
    const initStakeLarger = 21000;

    const {v: v1} = await d.newValidator(initStakeLarger, true, false, true);
    const {v: v2} = await d.newValidator(initStakeLarger, false, false, true);
    const {v: v3} = await d.newValidator(initStakeLesser, true, false, true);
    const {v: v4} = await d.newValidator(initStakeLesser, false, false, true);

    const generalCommittee = [v1, v2, v3, v4];
    const complianceCommittee = [v1, v3];

    // create a VCs

    const createVc = async (vcRate: number, isCompliant: boolean, payment: number): Promise<{vcid: number|BN, appOwner: Participant, feeBuckets: FeesAddedToBucketEvent[], startTime: number}> => {
      const subs = await d.newSubscriber('tier', vcRate);

      const appOwner = d.newParticipant();
      await d.erc20.assign(appOwner.address, payment);
      await d.erc20.approve(subs.address, payment, {from: appOwner.address});

      let r = await subs.createVC(payment, isCompliant, DEPLOYMENT_SUBSET_MAIN, {from: appOwner.address});
      const vcid = vcCreatedEvents(r)[0].vcid;
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

      return {
        vcid,
        startTime,
        appOwner,
        feeBuckets
      }
    };

    const {feeBuckets: generalFeeBuckets, startTime: generalStartTime} = await createVc(3000000000, false, 12 * 3000000000);
    const {feeBuckets: complianceFeeBuckets, startTime: complianceStartTime} = await createVc(6000000000, true, 12 * 3000000000);

    const calcFeeRewardsAndUpdateBuckets = (feeBuckets: FeesAddedToBucketEvent[], startTime: number, endTime: number, committee: Participant[]) => {
      let rewards = 0;
      for (const bucket of feeBuckets) {
        const bucketStartTime = Math.max(parseInt(bucket.bucketId as string), startTime);
        const bucketEndTime = bucketStartTime - (bucketStartTime % MONTH_IN_SECONDS) + MONTH_IN_SECONDS;
        const bucketRemainingTime = bucketEndTime - bucketStartTime;
        const bucketAmount = parseInt(bucket.added as string);
        if (bucketStartTime < endTime) {
          const payedDuration = Math.min(endTime, bucketEndTime) - bucketStartTime;
          const amount = Math.floor(bucketAmount * payedDuration / bucketRemainingTime);
          bucket.added = (parseInt(bucket.added as string) - amount).toString();
          bucket.total = (parseInt(bucket.total as string) - amount).toString();
          rewards += amount;
        }
      }
      const rewardsArr = committee.map(() => Math.floor(rewards / committee.length));
      const remainder = rewards - _.sum(rewardsArr);
      const remainderWinnerIdx = endTime % committee.length;
      rewardsArr[remainderWinnerIdx] = rewardsArr[remainderWinnerIdx] + remainder;
      return rewardsArr;
    };

    if (complianceStartTime > generalStartTime) {
      // the creation of the second VC triggered reward calculaton for the general committee, need to fix the buckets
      calcFeeRewardsAndUpdateBuckets(generalFeeBuckets, generalStartTime, complianceStartTime, generalCommittee);
    }

    // creating the VC has triggered reward assignment. We wish to ignore it, so we take the initial balance
    // and subtract it afterwards

    const initialOrbsBalances:BN[] = [];
    for (const v of generalCommittee) {
      initialOrbsBalances.push(new BN(await d.fees.getOrbsBalance(v.address)));
    }

    await sleep(3000);
    await evmIncreaseTime(d.web3, MONTH_IN_SECONDS*4);

    const assignFeesTxRes = await d.fees.assignFees();
    const endTime = await txTimestamp(d.web3, assignFeesTxRes);

    // Calculate expected rewards from VC fees

    const generalCommitteeRewardsArr = calcFeeRewardsAndUpdateBuckets(generalFeeBuckets, complianceStartTime, endTime, generalCommittee);
    expect(assignFeesTxRes).to.have.a.feesAssignedEvent({
      assignees: generalCommittee.map(v => v.address),
      orbs_amounts: generalCommitteeRewardsArr.map(x => x.toString())
    });

    const complianceCommitteeRewardsArr = calcFeeRewardsAndUpdateBuckets(complianceFeeBuckets, complianceStartTime, endTime, complianceCommittee);
    expect(assignFeesTxRes).to.have.a.feesAssignedEvent({
      assignees: complianceCommittee.map(v => v.address),
      orbs_amounts: complianceCommitteeRewardsArr.map(x => x.toString())
    });

    const orbsBalances:BN[] = [];
    for (const v of generalCommittee) {
      orbsBalances.push(new BN(await d.fees.getOrbsBalance(v.address)));
    }


    for (const v of generalCommittee) {
      const i = generalCommittee.indexOf(v);
      const totalExpectedRewards = generalCommitteeRewardsArr[i] + (i % 2 == 0 ? complianceCommitteeRewardsArr[i / 2] : 0);
      const expectedBalance = bn(totalExpectedRewards).add(initialOrbsBalances[i]);
      expect(orbsBalances[i]).to.be.bignumber.equal(expectedBalance);

      // withdraw the funds
      await d.fees.withdrawFunds({from: v.address});
      const actualBalance = await d.erc20.balanceOf(v.address);
      expect(new BN(actualBalance)).to.bignumber.equal(expectedBalance);
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

    let r = await subs.createVC(firstPayment, false, DEPLOYMENT_SUBSET_MAIN, {from: appOwner.address});
    let startTime = await txTimestamp(d.web3, r);
    expect(r).to.have.a.subscriptionChangedEvent({
      expiresAt: bn(startTime + MONTH_IN_SECONDS * initialDurationInMonths)
    });
    const vcid = bn(subscriptionChangedEvents(r)[0].vcid);

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
