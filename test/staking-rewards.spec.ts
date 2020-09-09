import 'mocha';

import BN from "bn.js";
import {defaultDriverOptions, Driver} from "./driver";
import chai from "chai";
import {
  bn,
  bnSum,
  contractId,
  evmIncreaseTime,
  evmMine,
  expectRejected,
  fromTokenUnits,
  toTokenUnits
} from "./helpers";
import {committeeSnapshotEvents} from "./event-parsing";
import {chaiEventMatchersPlugin, expectCommittee} from "./matchers";

chai.use(require('chai-bn')(BN));
chai.use(chaiEventMatchersPlugin);

const YEAR_IN_SECONDS = 365*24*60*60;

const expect = chai.expect;

async function sleep(ms): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

describe('staking-rewards', async () => {

  before(async () => {
    const d = await Driver.new();
    await evmMine(d.web3, 200); // tests assume block 200 is in the past
  });

  it('should distribute staking rewards to guardians in general committee', async () => {
    /* top up staking rewards pool */
    const d = await Driver.new();
    const g = d.functionalManager;

    const annualRate = bn(12000);
    const poolAmount = fromTokenUnits(200000000000);
    const annualCap = poolAmount;

    await d.rewards.setAnnualStakingRewardsRate(annualRate, annualCap, {from: g.address});

    await g.assignAndApproveOrbs(poolAmount, d.stakingRewardsWallet.address);
    await d.stakingRewardsWallet.topUp(poolAmount,{from: g.address});

    // create committee

    const initStakeLesser = fromTokenUnits(17000);
    const v1 = d.newParticipant();
    await v1.stake(initStakeLesser);
    await v1.registerAsGuardian();
    await v1.readyForCommittee();

    const initStakeLarger = fromTokenUnits(21000);
    const v2 = d.newParticipant();
    await v2.stake(initStakeLarger);
    await v2.registerAsGuardian();
    let r = await v2.readyForCommittee();
    const startTime = await d.web3.txTimestamp(r);

    const guardians = [{
      v: v2,
      stake: initStakeLarger
    }, {
      v: v1,
      stake: initStakeLesser
    }];

    const nGuardians = guardians.length;

    expect(await d.rewards.getLastRewardAssignmentTime()).to.be.bignumber.equal(new BN(startTime));

    await sleep(3000);
    await evmIncreaseTime(d.web3, YEAR_IN_SECONDS*4);

    const assignRewardTxRes = await d.rewards.assignRewards();
    const endTime = await d.web3.txTimestamp(assignRewardTxRes);
    const elapsedTime = endTime - startTime;

    const calcRewards = () => {
      const totalCommitteeStake = bnSum(guardians.map(v => v.stake));
      const actualAnnualRate = BN.min(annualRate, annualCap.mul(bn(100000)).div(totalCommitteeStake));
      const rewardsArr = guardians
          .map(v => actualAnnualRate.mul(v.stake).div(bn(100000)))
          .map(r => toTokenUnits(r))
          .map(r => r.mul(bn(elapsedTime)).div(bn(YEAR_IN_SECONDS)));
      return rewardsArr.map(x => fromTokenUnits(x));
    };

    const totalOrbsRewardsArr = calcRewards();

    expect(assignRewardTxRes).to.have.a.stakingRewardsAssignedEvent({
      assignees: guardians.map(v => v.v.address),
      amounts: totalOrbsRewardsArr
    });

    const orbsBalances:BN[] = [];
    for (const v of guardians) {
      orbsBalances.push(new BN(await d.rewards.getStakingRewardBalance(v.v.address)));
    }

    for (const v of guardians) {
      const delegator = d.newParticipant();
      await delegator.delegate(v.v);

      const i = guardians.indexOf(v);
      expect(orbsBalances[i]).to.be.bignumber.equal(totalOrbsRewardsArr[i]);

      let r = await d.rewards.distributeStakingRewards(
          totalOrbsRewardsArr[i],
          0,
          100,
          1,
          0,
          [v.v.address, delegator.address],
          [bn(1), totalOrbsRewardsArr[i].sub(bn(1))],
            {from: v.v.address}
        );
      expect(r).to.have.a.stakingRewardsDistributedEvent({
        distributer: v.v.address,
        fromBlock: bn(0),
        toBlock: bn(100),
        split: bn(1),
        txIndex: bn(0),
        to: [v.v.address, delegator.address],
        amounts: [bn(1), totalOrbsRewardsArr[i].sub(bn(1))]
      });
      expect(r).to.have.a.stakedEvent({
        stakeOwner: delegator.address,
        amount: totalOrbsRewardsArr[i].sub(bn(1)),
        totalStakedAmount: totalOrbsRewardsArr[i].sub(bn(1)),
      });
      expect(r).to.have.a.stakedEvent({
        stakeOwner: v.v.address,
        amount: bn(1),
        totalStakedAmount: bn(v.stake).add(bn(1))
      });
    }
  });

  it('should enforce the annual cap', async () => {
    const d = await Driver.new();

    /* top up staking rewards pool */
    const g = d.functionalManager;

    const annualRate = bn(12000);
    const poolAmount = fromTokenUnits(2000000000);
    const annualCap = fromTokenUnits(100);

    await d.rewards.setAnnualStakingRewardsRate(annualRate, annualCap, {from: g.address}); // todo monthly to annual

    await g.assignAndApproveOrbs(poolAmount, d.stakingRewardsWallet.address);
    await d.stakingRewardsWallet.topUp(poolAmount, {from: g.address});

    // create committee

    const initStakeLesser = fromTokenUnits(17000);
    const v1 = d.newParticipant();
    await v1.stake(initStakeLesser);
    await v1.registerAsGuardian();
    await v1.readyForCommittee();

    const initStakeLarger = fromTokenUnits(21000);
    const v2 = d.newParticipant();
    await v2.stake(initStakeLarger);
    await v2.registerAsGuardian();
    let r = await v2.readyForCommittee();
    const startTime = await d.web3.txTimestamp(r);

    const guardians = [{
      v: v1,
      stake: initStakeLesser
    }, {
      v: v2,
      stake: initStakeLarger
    }];

    const nGuardians = guardians.length;

    expect(await d.rewards.getLastRewardAssignmentTime()).to.be.bignumber.equal(new BN(startTime));

    await sleep(3000);
    await evmIncreaseTime(d.web3, YEAR_IN_SECONDS*4);

    const assignRewardTxRes = await d.rewards.assignRewards();
    const endTime = await d.web3.txTimestamp(assignRewardTxRes);
    const elapsedTime = endTime - startTime;

    const calcRewards = () => {
      const totalCommitteeStake = bnSum(guardians.map(v => v.stake));
      const actualAnnualRate = BN.min(annualRate, annualCap.mul(bn(100000)).div(totalCommitteeStake));
      const rewardsArr = guardians
          .map(v => actualAnnualRate
              .mul(v.stake)
              .mul(bn(elapsedTime))
              .div(bn(YEAR_IN_SECONDS).mul(bn(100000)))
          ).map(r => toTokenUnits(r));
      return rewardsArr.map(x => fromTokenUnits(x));
    };

    const totalOrbsRewardsArr = calcRewards();

    const orbsBalances:BN[] = [];
    for (const v of guardians) {
      orbsBalances.push(new BN(await d.rewards.getStakingRewardBalance(v.v.address)));
    }

    expect(assignRewardTxRes).to.have.a.stakingRewardsAssignedEvent({
      assignees: guardians.map(v => v.v.address),
      amounts: totalOrbsRewardsArr.map(x => x.toString())
    });

    for (const v of guardians) {
      const delegator = d.newParticipant();
      await delegator.delegate(v.v);

      const i = guardians.indexOf(v);
      expect(orbsBalances[i]).to.be.bignumber.equal(new BN(totalOrbsRewardsArr[i]));

      r = await d.rewards.distributeStakingRewards(
          totalOrbsRewardsArr[i],
          0,
          100,
          1,
          0,
          [v.v.address, delegator.address],
          [bn(1), totalOrbsRewardsArr[i].sub(bn(1))],
            {from: v.v.address});
      expect(r).to.have.a.stakingRewardsDistributedEvent({
        distributer: v.v.address,
        fromBlock: bn(0),
        toBlock: bn(100),
        split: bn(1),
        txIndex: bn(0),
        to: [v.v.address, delegator.address],
        amounts: [bn(1), totalOrbsRewardsArr[i].sub(bn(1))]
      });
      expect(r).to.have.a.stakedEvent({
        stakeOwner: delegator.address,
        amount: totalOrbsRewardsArr[i].sub(bn(1)),
        totalStakedAmount: totalOrbsRewardsArr[i].sub(bn(1))
      });
      expect(r).to.have.a.stakedEvent({
        stakeOwner: v.v.address,
        amount: bn(1),
        totalStakedAmount: bn(v.stake).add(bn(1))
      });
    }
  });

  it('should enforce totalAmount, fromBlock, toBlock, split, txIndex to be consecutive', async () => {
    const d = await Driver.new();

    const {v} = await d.newGuardian(fromTokenUnits(1000), false, false, true);
    const {v: v2} = await d.newGuardian(fromTokenUnits(1000), false, false, true);

    /* top up staking rewards pool */
    const g = d.functionalManager;

    const annualRate = 12000;
    const poolAmount = fromTokenUnits(20000000);
    const annualCap = fromTokenUnits(20000000);

    await d.rewards.setAnnualStakingRewardsRate(annualRate, annualCap, {from: g.address});

    await g.assignAndApproveOrbs(poolAmount, d.stakingRewardsWallet.address);
    await d.stakingRewardsWallet.topUp(poolAmount, {from: g.address});

    await evmIncreaseTime(d.web3, YEAR_IN_SECONDS);
    await evmMine(d.web3, 1000);

    let r = await d.rewards.assignRewards();

    // first fromBlock, toBlock must be in the past
    await expectRejected(d.rewards.distributeStakingRewards(
        fromTokenUnits(5),
        r.blockNumber - 10,
        r.blockNumber + 10,
        1,
        0,
        [v.address],
        [fromTokenUnits(5)],
        {from: v.address})
    , /toBlock must be in the past/);

    // should fail if total does not match actual total
    await expectRejected(d.rewards.distributeStakingRewards(
        fromTokenUnits(5),
        0,
        100,
        1,
        1,
        [],
        [],
        {from: v.address})
    , /list must contain at least one recipient/);

    await expectRejected(d.rewards.distributeStakingRewards(
        fromTokenUnits(5),
        0,
        100,
        1,
        1,
        [v.address],
        [1],
        {from: v.address})
    , /StakingContract::distributeRewards - incorrect total amount/);

    let fromBlock = bn(2);
    let toBlock = fromBlock.add(bn(100));
    let txIndex = bn(3);
    let split = bn(1);

    // First fromBlock, toBlock txIndex can be of any value as long as fromBlock is in the past
    r = await d.rewards.distributeStakingRewards(
        fromTokenUnits(5),
        fromBlock,
        toBlock,
        split,
        txIndex,
        [v.address],
        [fromTokenUnits(5)],
        {from: v.address}
      );
    expect(r).to.have.a.stakingRewardsDistributedEvent({
      distributer: v.address,
      fromBlock,
      toBlock,
      split,
      txIndex,
      to: [v.address],
      amounts: [bn(fromTokenUnits(5))]
    });

    // next txIndex must increment the previous one
    await expectRejected(d.rewards.distributeStakingRewards(
        fromTokenUnits(5),
        fromBlock,
        toBlock,
        split,
        0,
        [v.address],
        [fromTokenUnits(5)],
        {from: v.address}
      )
    , /txIndex mismatch/);

    await expectRejected(d.rewards.distributeStakingRewards(
        fromTokenUnits(5),
        fromBlock,
        toBlock,
        1,
        txIndex.add(bn(2)),
        [v.address],
        [fromTokenUnits(5)],
        {from: v.address}
      )
    , /txIndex mismatch/);

    txIndex = txIndex.add(bn(1));
    r = await d.rewards.distributeStakingRewards(
        fromTokenUnits(5),
        fromBlock,
        toBlock,
        split,
        txIndex,
        [v.address],
        [fromTokenUnits(5)],
        {from: v.address}
    );
    expect(r).to.have.a.stakingRewardsDistributedEvent({
      distributer: v.address,
      fromBlock,
      toBlock,
      split,
      txIndex,
      to: [v.address],
      amounts: [bn(fromTokenUnits(5))]
    });

    txIndex = txIndex.add(bn(1));
    r = await d.rewards.distributeStakingRewards(
        fromTokenUnits(5),
        fromBlock,
        toBlock,
        split,
        txIndex,
        [v.address],
        [fromTokenUnits(5)],
        {from: v.address}
    );
    expect(r).to.have.a.stakingRewardsDistributedEvent({
      distributer: v.address,
      fromBlock,
      toBlock,
      split,
      txIndex,
      to: [v.address],
      amounts: [bn(fromTokenUnits(5))]
    });

    txIndex = txIndex.add(bn(1));

    // next split must equal previous
    await expectRejected(d.rewards.distributeStakingRewards(
        fromTokenUnits(5),
        fromBlock,
        toBlock,
        split.add(bn(1)),
        txIndex,
        [v.address],
        [fromTokenUnits(5)],
        {from: v.address}
        )
    , /split mismatch/);

    split = bn(2);
    txIndex = bn(0);

    // next fromBlock must be previous toBlock + 1
    await expectRejected(d.rewards.distributeStakingRewards(
        fromTokenUnits(5),
        toBlock.sub(bn(1)),
        toBlock.add(bn(100)),
        split,
        txIndex,
        [v.address],
        [fromTokenUnits(5)],
        {from: v.address}
        )
    , /fromBlock mismatch/);

    await expectRejected(d.rewards.distributeStakingRewards(
        fromTokenUnits(5),
        toBlock,
        toBlock.add(bn(100)),
        split,
        txIndex,
        [v.address],
        [fromTokenUnits(5)],
        {from: v.address}
        )
    , /fromBlock mismatch/);

    fromBlock = toBlock.add(bn(1))

    // next toBlock must be at least new fromBlock
    await expectRejected(d.rewards.distributeStakingRewards(
        fromTokenUnits(5),
        fromBlock,
        fromBlock.sub(bn(1)),
        split,
        txIndex,
        [v.address],
        [fromTokenUnits(5)],
        {from: v.address}
        )
    , /toBlock must be at least fromBlock/);

    toBlock = fromBlock.add(bn(99))
    // on new distribution, txIndex must be 0
    await expectRejected(d.rewards.distributeStakingRewards(
        fromTokenUnits(5),
        fromBlock,
        toBlock,
        split,
        1,
        [v.address],
        [fromTokenUnits(5)],
        {from: v.address}
        )
    , /txIndex must be 0 for the first transaction/);

    // split can be changed on new distribution
    r = await d.rewards.distributeStakingRewards(
        fromTokenUnits(5),
        fromBlock,
        toBlock,
        split,
        txIndex,
        [v.address],
        [fromTokenUnits(5)],
        {from: v.address}
    );
    expect(r).to.have.a.stakingRewardsDistributedEvent({
      distributer: v.address,
      fromBlock,
      toBlock,
      split,
      txIndex,
      to: [v.address],
      amounts: [bn(fromTokenUnits(5))]
    });

    // state is per address, different distributor can start from any txIndex and past fromBlock, toBlock
    r = await d.rewards.distributeStakingRewards(
        fromTokenUnits(5),
        10,
        20,
        1,
        5,
        [v2.address],
        [fromTokenUnits(5)],
        {from: v2.address}
    );
    expect(r).to.have.a.stakingRewardsDistributedEvent({
      distributer: v2.address,
      fromBlock: bn(10),
      toBlock: bn(20),
      split: bn(1),
      txIndex: bn(5),
      to: [v2.address],
      amounts: [bn(fromTokenUnits(5))]
    });

    // toBlock must be in the past
    await expectRejected(d.rewards.distributeStakingRewards(
        fromTokenUnits(5),
        21,
        (r.blockNumber + 10000),
        1,
        0,
        [v2.address],
        [fromTokenUnits(5)],
        {from: v2.address}
    ), /toBlock must be in the past/);

  });

  it('allows distributing rewards from both orbs address and ethereum address accounts', async () => {
    const d = await Driver.new();

    const {v} = await d.newGuardian(fromTokenUnits(1000), false, false, true);

    const delegator = d.newParticipant();

    /* top up staking rewards pool */
    const g = d.functionalManager;

    const annualRate = 12000;
    const poolAmount = fromTokenUnits(20000000);
    const annualCap = fromTokenUnits(20000000);

    await d.rewards.setAnnualStakingRewardsRate(annualRate, annualCap, {from: g.address});

    await g.assignAndApproveOrbs(poolAmount, d.stakingRewardsWallet.address);
    await d.stakingRewardsWallet.topUp(poolAmount, {from: g.address});

    await evmIncreaseTime(d.web3, YEAR_IN_SECONDS);

    await d.rewards.assignRewards();

    let r = await d.rewards.distributeStakingRewards(
        fromTokenUnits(6),
        0,
        100,
        1,
        0,
        [v.address, delegator.address],
        [fromTokenUnits(1), fromTokenUnits(5)],
        {from: v.address}
      );
    expect(r).to.have.a.stakingRewardsDistributedEvent({
      distributer: v.address,
      fromBlock: bn(0),
      toBlock: bn(100),
      split: bn(1),
      txIndex: bn(0),
      to: [v.address, delegator.address],
      amounts: [fromTokenUnits(1), fromTokenUnits(5)]
    });

    r = await d.rewards.distributeStakingRewards(
        fromTokenUnits(6),
        0,
        100,
        1,
        1,
        [v.address, delegator.address],
        [fromTokenUnits(1), fromTokenUnits(5)],
        {from: v.orbsAddress}
    );
    expect(r).to.have.a.stakingRewardsDistributedEvent({
      distributer: v.address,
      fromBlock: bn(0),
      toBlock: bn(100),
      split: bn(1),
      txIndex: bn(1),
      to: [v.address, delegator.address],
      amounts: [fromTokenUnits(1), fromTokenUnits(5)]
    });
  });

  it('any address in distribute can be the main address of the sender', async () => {
    const d = await Driver.new();

    const {v} = await d.newGuardian(fromTokenUnits(1000), false, false, true);

    const delegator = d.newParticipant();

    /* top up staking rewards pool */
    const g = d.functionalManager;

    const annualRate = 12000;
    const poolAmount = fromTokenUnits(20000000);
    const annualCap = fromTokenUnits(20000000);

    await d.rewards.setAnnualStakingRewardsRate(annualRate, annualCap, {from: g.address});

    await g.assignAndApproveOrbs(poolAmount, d.stakingRewardsWallet.address);
    await d.stakingRewardsWallet.topUp(poolAmount, {from: g.address});

    await evmIncreaseTime(d.web3, YEAR_IN_SECONDS);

    await d.rewards.assignRewards();

    await d.rewards.distributeStakingRewards(
        fromTokenUnits(5),
        0,
        100,
        1,
        0,
        [delegator.address],
        [fromTokenUnits(5)],
        {from: v.address}
    );

    await d.rewards.distributeStakingRewards(
        fromTokenUnits(2),
        0,
        100,
        1,
        1,
        [delegator.address, v.address],
        [fromTokenUnits(1), fromTokenUnits(1)],
        {from: v.address}
    );

    await d.rewards.distributeStakingRewards(
        fromTokenUnits(2),
        0,
        100,
        1,
        2 ,
        [v.address, delegator.address],
        [fromTokenUnits(1), fromTokenUnits(1)],
        {from: v.address}
    );
  });

  it('enforces delegators portion in the distribution is less than configured threshold', async () => {
    const d = await Driver.new();

    const {v} = await d.newGuardian(fromTokenUnits(100000000), false, false, true);

    const delegator = d.newParticipant();

    /* top up staking rewards pool */
    const g = d.functionalManager;

    const annualRate = 12000;
    const poolAmount = fromTokenUnits(20000000);
    const annualCap = fromTokenUnits(20000000);

    await d.rewards.setAnnualStakingRewardsRate(annualRate, annualCap, {from: g.address});

    await g.assignAndApproveOrbs(poolAmount, d.stakingRewardsWallet.address);
    await d.stakingRewardsWallet.topUp(poolAmount, {from: g.address});

    await evmIncreaseTime(d.web3, YEAR_IN_SECONDS);

    await d.rewards.assignRewards();

    let r = await d.rewards.setMaxDelegatorsStakingRewardsPercentMille(66666, {from: d.functionalManager.address});
    expect(r).to.have.a.maxDelegatorsStakingRewardsChangedEvent({maxDelegatorsStakingRewardsPercentMille: bn(66666)});

    await expectRejected(d.rewards.distributeStakingRewards(
        fromTokenUnits(100000),
        0,
        100,
        1,
        0,
        [v.address, delegator.address],
        [fromTokenUnits(33333), fromTokenUnits(66667)],
        {from: v.address}
    ), /Total delegators reward must be less then maxDelegatorsStakingRewardsPercentMille of total amount/);

    await expectRejected(d.rewards.distributeStakingRewards(
        fromTokenUnits(2),
        0,
        100,
        1,
        0,
        [delegator.address],
        [fromTokenUnits(2)],
        {from: v.address}
    ), /Total delegators reward must be less then maxDelegatorsStakingRewardsPercentMille of total amount/);

    await d.rewards.distributeStakingRewards(
        fromTokenUnits(100000),
        0,
        100,
        1,
        0,
        [v.address, delegator.address],
        [fromTokenUnits(33334), fromTokenUnits(66666)],
        {from: v.address}
    );

    // +1 for rounding errors should allow these
    await d.rewards.distributeStakingRewards(
        fromTokenUnits(99999),
        0,
        100,
        1,
        1,
        [v.address, delegator.address],
        [fromTokenUnits(33333), fromTokenUnits(66666)],
        {from: v.address}
    );

    await d.rewards.distributeStakingRewards(
        fromTokenUnits(1),
        0,
        100,
        1,
        2,
        [delegator.address],
        [fromTokenUnits(1)],
        {from: v.address}
    );

    // guardian reward can be split to multiple entries
    await d.rewards.distributeStakingRewards(
        fromTokenUnits(5),
        0,
        100,
        1,
        3,
        [v.address, delegator.address, v.address],
        [fromTokenUnits(1), fromTokenUnits(2), fromTokenUnits(2)],
        {from: v.address}
    );

    // Distribute only to guardian
    await d.rewards.distributeStakingRewards(
        fromTokenUnits(1),
        0,
        100,
        1,
        4,
        [v.address],
        [fromTokenUnits(1)],
        {from: v.address}
    );
  });

  it("only commits the stake change of the sender's guardian address", async () => {
    const d = await Driver.new();

    const {v: v1} = await d.newGuardian(fromTokenUnits(100000000), false, false, true);
    const {v: v2} = await d.newGuardian(fromTokenUnits(100000000), false, false, true);

    /* top up staking rewards pool */
    const g = d.functionalManager;

    const annualRate = 12000;
    const annualCap = fromTokenUnits(20000000);
    const poolAmount = annualCap.mul(bn(2));

    await d.rewards.setAnnualStakingRewardsRate(annualRate, annualCap, {from: g.address});

    await g.assignAndApproveOrbs(poolAmount, d.stakingRewardsWallet.address);
    await d.stakingRewardsWallet.topUp(poolAmount, {from: g.address});

    await evmIncreaseTime(d.web3, YEAR_IN_SECONDS);

    await d.rewards.assignRewards();

    let r = await d.rewards.distributeStakingRewards(
        fromTokenUnits(2),
        0,
        100,
        1,
        0,
        [v1.address, v2.address],
        [fromTokenUnits(1), fromTokenUnits(1)],
        {from: v1.address}
    );
    await expectCommittee(d, {
      addrs: [v1.address, v2.address],
      weights: [fromTokenUnits(100000001), fromTokenUnits(100000000)]
    });
    expect(committeeSnapshotEvents(r).length).to.eq(1);

  });

  it("allows anyone to migrate staking rewards to a new contract", async () => {
    const d = await Driver.new();

    const {v: v1} = await d.newGuardian(fromTokenUnits(100000000), false, false, true);
    const {v: v2} = await d.newGuardian(fromTokenUnits(100000000), false, false, true);

    /* top up staking rewards pool */
    const g = d.functionalManager;

    const annualRate = 12000;
    const annualCap = fromTokenUnits(20000000);
    const poolAmount = annualCap.mul(bn(2));

    await d.rewards.setAnnualStakingRewardsRate(annualRate, annualCap, {from: g.address});

    await g.assignAndApproveOrbs(poolAmount, d.stakingRewardsWallet.address);
    await d.stakingRewardsWallet.topUp(poolAmount, {from: g.address});

    await evmIncreaseTime(d.web3, YEAR_IN_SECONDS);

    await d.rewards.assignRewards();

    const v1balance = bn(await d.rewards.getStakingRewardBalance(v1.address));
    expect(v1balance).to.be.bignumber.greaterThan(bn(0));

    // migrating to the same contract has no effect
    let r = await d.rewards.migrateStakingRewardsBalance(v1.address);
    expect(r).to.not.have.a.stakingRewardsMigrationAcceptedEvent();
    expect(r).to.not.have.a.stakingRewardsBalanceMigratedEvent();
    expect(bn(await d.rewards.getStakingRewardBalance(v1.address))).to.bignumber.eq(v1balance);

    const newRewardsContract = await d.web3.deploy('Rewards', [d.contractRegistry.address, d.registryAdmin.address, d.erc20.address, d.bootstrapToken.address,
      defaultDriverOptions.generalCommitteeAnnualBootstrap,
      defaultDriverOptions.certifiedCommitteeAnnualBootstrap,
      defaultDriverOptions.stakingRewardsAnnualRateInPercentMille,
      defaultDriverOptions.stakingRewardsAnnualCap,
      defaultDriverOptions.maxDelegatorsStakingRewardsPercentMille
    ], null, d.session);
    await d.contractRegistry.setContract('rewards', newRewardsContract.address, true, {from: d.registryAdmin.address});

    // migrating to the new contract
    r = await d.rewards.migrateStakingRewardsBalance(v1.address);
    expect(r).to.have.withinContract(newRewardsContract).a.stakingRewardsMigrationAcceptedEvent({
      from: d.rewards.address,
      guardian: v1.address,
      amount: v1balance
    });
    expect(r).to.have.withinContract(d.rewards).a.stakingRewardsBalanceMigratedEvent({
      guardian: v1.address,
      amount: v1balance,
      toRewardsContract: newRewardsContract.address
    });
    expect(bn(await d.rewards.getStakingRewardBalance(v1.address))).to.bignumber.eq(bn(0));
    expect(bn(await newRewardsContract.getStakingRewardBalance(v1.address))).to.bignumber.eq(v1balance);

    // anyone can migrate
    const migrator = d.newParticipant();
    await migrator.assignAndApproveOrbs(100, newRewardsContract.address);
    r = await newRewardsContract.acceptStakingRewardsMigration(v2.address, 100, {from: migrator.address});
    expect(r).to.have.withinContract(newRewardsContract).a.stakingRewardsMigrationAcceptedEvent({
      from: migrator.address,
      guardian: v2.address,
      amount: bn(100)
    });

  });



});
