import 'mocha';

import BN from "bn.js";
import {Driver} from "./driver";
import chai from "chai";
import {
  feesAddedToBucketEvents,
} from "./event-parsing";
import {bn, bnSum, contractId, evmIncreaseTime, expectRejected, fromTokenUnits, toTokenUnits} from "./helpers";
import {chaiEventMatchersPlugin} from "./matchers";

chai.use(require('chai-bn')(BN));
chai.use(chaiEventMatchersPlugin);

const MONTH_IN_SECONDS = 30*24*60*60;

const expect = chai.expect;

async function sleep(ms): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

const bucketId = timestamp => bn(timestamp - timestamp % MONTH_IN_SECONDS);

describe('fees-wallet-contract', async () => {

  it('should not fill past buckets (one bucket)', async () => {
    const d = await Driver.new();

    const {v: assigner, r: rNow} = await d.newGuardian(1, false, false, true);
    await assigner.assignAndApproveOrbs(2, d.generalFeesWallet.address);

    const now = await d.web3.txTimestamp(rNow);
    await expectRejected(d.generalFeesWallet.fillFeeBuckets(1, 10, now - MONTH_IN_SECONDS, {from: assigner.address}), /cannot fill bucket from the past/);
  });

  it('should fill fee buckets (one bucket)', async () => {
    const d = await Driver.new();

    const {v: assigner, r: rNow} = await d.newGuardian(1, false, false, true);
    await assigner.assignAndApproveOrbs(2, d.generalFeesWallet.address);

    const now = await d.web3.txTimestamp(rNow);
    let r = await d.generalFeesWallet.fillFeeBuckets(1, 1000, now, {from: assigner.address});
    expect(r).to.have.a.feesAddedToBucketEvent({
      bucketId: bucketId(now).toString(),
      added: bn(1).toString(),
      total: bn(1).toString(),
    });

    r = await d.generalFeesWallet.fillFeeBuckets(1, 1000, now + 1, {from: assigner.address});
    expect(r).to.have.a.feesAddedToBucketEvent({
      bucketId: bucketId(now).toString(),
      added: bn(1).toString(),
      total: bn(2).toString(),
    })
  });

  it('should fill fee buckets (3 buckets)', async () => {
    const d = await Driver.new();

    const {v: assigner, r: rNow} = await d.newGuardian(1, false, false, true);
    await assigner.assignAndApproveOrbs(100000, d.generalFeesWallet.address);

    const rate = bn(1000);
    const amount = bn(2001);
    const now = await d.web3.txTimestamp(rNow);
    let r = await d.generalFeesWallet.fillFeeBuckets(amount, rate, now, {from: assigner.address});
    const expectedAmounts = [
        bn(MONTH_IN_SECONDS - now % MONTH_IN_SECONDS).mul(rate).div(bn(MONTH_IN_SECONDS)),
        bn(rate),
        bn(amount - rate - bn(MONTH_IN_SECONDS - now % MONTH_IN_SECONDS).mul(rate).div(bn(MONTH_IN_SECONDS)).toNumber())
    ];
    expect(r).to.have.a.feesAddedToBucketEvent({
      bucketId: bucketId(now),
      added: expectedAmounts[0],
      total: expectedAmounts[0],
    });
    expect(r).to.have.a.feesAddedToBucketEvent({
      bucketId: bucketId(now).add(bn(MONTH_IN_SECONDS)),
      added: expectedAmounts[1],
      total: expectedAmounts[1],
    });
    expect(r).to.have.a.feesAddedToBucketEvent({
      bucketId: bucketId(now).add(bn(2*MONTH_IN_SECONDS)),
      added: expectedAmounts[2],
      total: expectedAmounts[2],
    });

    r = await d.generalFeesWallet.fillFeeBuckets(amount, rate, now + 1, {from: assigner.address});
    const now2 = await d.web3.txTimestamp(r);
    const expectedAmounts2 = [
      bn(MONTH_IN_SECONDS - now2 % MONTH_IN_SECONDS).mul(rate).div(bn(MONTH_IN_SECONDS)),
      rate,
      bn(amount - rate - bn(MONTH_IN_SECONDS - now2 % MONTH_IN_SECONDS).mul(rate).div(bn(MONTH_IN_SECONDS)).toNumber())
    ];

    expect(r).to.have.a.feesAddedToBucketEvent({
      bucketId: bucketId(now),
      added: expectedAmounts2[0],
      total: expectedAmounts[0].add(expectedAmounts2[0]),
    });
    expect(r).to.have.a.feesAddedToBucketEvent({
      bucketId: bucketId(now).add(bn(MONTH_IN_SECONDS)),
      added: expectedAmounts2[1],
      total: expectedAmounts[1].add(expectedAmounts2[1]),
    });
    expect(r).to.have.a.feesAddedToBucketEvent({
      bucketId: bucketId(now).add(bn(2*MONTH_IN_SECONDS)),
      added: expectedAmounts2[2],
      total: expectedAmounts[2].add(expectedAmounts2[2]),
    });
  });

  it('collects fees', async () => {
    const d = await Driver.new();

    const {v: assigner, r: rNow} = await d.newGuardian(1, false, false, true);
    await assigner.assignAndApproveOrbs(300000000, d.generalFeesWallet.address);

    const collector = d.newParticipant();
    await d.contractRegistry.setContract("rewards", collector.address, false,{from: d.registryAdmin.address});

    const startTime = await d.web3.txTimestamp(await d.generalFeesWallet.collectFees({from: collector.address}));

    const now = await d.web3.txTimestamp(rNow);
    const rate = bn(10000000);
    await d.generalFeesWallet.fillFeeBuckets(30000000, rate, now, {from: assigner.address});

    await evmIncreaseTime(d.web3, 30);

    let r1 = await d.generalFeesWallet.collectFees({from: collector.address});
    let duration = await d.web3.txTimestamp(r1) - startTime;
    const expected1 = bn(duration).mul(rate).div(bn(MONTH_IN_SECONDS));
    expect(bn(await d.erc20.balanceOf(collector.address))).to.bignumber.eq(expected1);

    await evmIncreaseTime(d.web3, 60*30);

    let r2 = await d.generalFeesWallet.collectFees({from: collector.address});
    duration = await d.web3.txTimestamp(r2) - await d.web3.txTimestamp(r1);
    const expected2 = bn(duration).mul(rate).div(bn(MONTH_IN_SECONDS));
    expect(bn(await d.erc20.balanceOf(collector.address))).to.bignumber.eq(expected1.add(expected2));

    await evmIncreaseTime(d.web3, MONTH_IN_SECONDS);

    let r3 = await d.generalFeesWallet.collectFees({from: collector.address});
    duration = await d.web3.txTimestamp(r3) - await d.web3.txTimestamp(r2);
    const expected3 = bn(duration).mul(rate).div(bn(MONTH_IN_SECONDS));
    let totalExpected = expected1.add(expected2).add(expected3);
    const currentBalance: BN = bn(await d.erc20.balanceOf(collector.address));
    if (totalExpected.sub(currentBalance).abs().lt(totalExpected.div(bn(100)))) {
      totalExpected = currentBalance; // Allow a 1% rounding error;
    }
    expect(currentBalance).to.bignumber.eq(totalExpected);
  });

  it('only rewards contract can collect fees', async () => {
    const d = await Driver.new();

    const {v: assigner, r: rNow} = await d.newGuardian(1, false, false, true);
    await assigner.assignAndApproveOrbs(30, d.generalFeesWallet.address);

    const now = await d.web3.txTimestamp(rNow);
    await d.generalFeesWallet.fillFeeBuckets(30, 10, now, {from: assigner.address});
    await expectRejected(d.generalFeesWallet.collectFees({from: assigner.address}), /caller is not the rewards contract/);

    await d.contractRegistry.setContract("rewards", assigner.address, false, {from: d.registryAdmin.address});
    await d.generalFeesWallet.collectFees({from: assigner.address});
  });

  it('performs emergency withdrawal only by the migration manager', async () => {
    const d = await Driver.new();
    const amount = bn(1000);

    const {v: assigner, r: rNow} = await d.newGuardian(1, false, false, true);
    await assigner.assignAndApproveOrbs(amount, d.generalFeesWallet.address);
    const now = await d.web3.txTimestamp(rNow);

    await d.generalFeesWallet.fillFeeBuckets(amount, 500, now, {from: assigner.address});

    await expectRejected(d.generalFeesWallet.emergencyWithdraw({from: d.functionalManager.address}), /sender is not the migration manager/);
    let r = await d.generalFeesWallet.emergencyWithdraw({from: d.migrationManager.address});
    expect(r).to.have.a.emergencyWithdrawalEvent({addr: d.migrationManager.address});

    expect(await d.erc20.balanceOf(d.migrationManager.address)).to.bignumber.eq(amount);
  });

  it('performs migration only by the migration manager', async () => {
    const d = await Driver.new();
    const amount = bn(1000);

    const {v: assigner, r: rNow} = await d.newGuardian(1, false, false, true);
    await assigner.assignAndApproveOrbs(amount, d.generalFeesWallet.address);
    const now = await d.web3.txTimestamp(rNow);

    let r = await d.generalFeesWallet.fillFeeBuckets(amount, 500, now, {from: assigner.address});
    const buckets = feesAddedToBucketEvents(r);

    const newFeesWallet = await d.web3.deploy('FeesWallet', [d.contractRegistry.address, d.registryAdmin.address, d.erc20.address], null, d.session);

    for (const bucket of buckets) {
      await expectRejected(d.generalFeesWallet.migrateBucket(newFeesWallet.address, bn(bucket.bucketId), {from: d.functionalManager.address}), /sender is not the migration manager/);
      await expectRejected(d.generalFeesWallet.migrateBucket(newFeesWallet.address, bn(bucket.bucketId).add(bn(1)), {from: d.migrationManager.address}), /bucketStartTime must be the  start time of a bucket/);
      r = await d.generalFeesWallet.migrateBucket(newFeesWallet.address, bn(bucket.bucketId), {from: d.migrationManager.address});
      expect(r).to.have.withinContract(d.generalFeesWallet).a.feesWithdrawnFromBucketEvent({
        bucketId: bucket.bucketId,
        withdrawn: bucket.total,
        total: bn(0),
      });
      expect(r).to.have.withinContract(newFeesWallet).a.feesAddedToBucketEvent({
        bucketId: bucket.bucketId,
        added: bucket.total,
        total: bucket.total,
      });
    }
    expect(await d.erc20.balanceOf(newFeesWallet.address)).to.bignumber.eq(bn(amount));
  });

});
