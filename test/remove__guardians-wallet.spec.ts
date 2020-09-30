// import 'mocha';
//
// import * as _ from "lodash";
// import BN from "bn.js";
// import {Driver, DEPLOYMENT_SUBSET_MAIN, Participant, expectRejected} from "./driver";
// import chai from "chai";
// import {
//   feesAddedToBucketEvents,
//   rewardsAssignedEvents,
//   subscriptionChangedEvents,
//   vcCreatedEvents
// } from "./event-parsing";
// import {bn, bnSum, evmIncreaseTime, fromTokenUnits, toTokenUnits} from "./helpers";
// import {TransactionReceipt} from "web3-core";
// import {Web3Driver} from "../eth";
//
// chai.use(require('chai-bn')(BN));
// chai.use(chaiEventMatchersPlugin);
//
// const MONTH_IN_SECONDS = 30*24*60*60;
//
// async function txTimestamp(web3: Web3Driver, r: TransactionReceipt): Promise<number> { // TODO move
//   return (await web3.eth.getBlock(r.blockNumber)).timestamp as number;
// }
//
// const expect = chai.expect;
//
// async function sleep(ms): Promise<void> {
//   return new Promise(resolve => setTimeout(resolve, ms));
// }
//
// describe('guardians-wallet-contract', async () => {
//
//   it('should assign rewards and update balances', async () => {
//     const d = await Driver.new();
//
//     const guardians = [d.newParticipant(), d.newParticipant()];
//     const stakingRewards = [fromTokenUnits(1), fromTokenUnits(2)];
//     const bootstrapRewards = [fromTokenUnits(3), fromTokenUnits(4)];
//     const fees = [fromTokenUnits(5), fromTokenUnits(6)];
//
//     const assigner = d.newParticipant();
//     await assigner.assignAndApproveOrbs(bnSum(stakingRewards).add(bnSum(fees)), d.rewards.address);
//     await assigner.assignAndApproveExternalToken(bnSum(bootstrapRewards), d.rewards.address);
//
//     let r = await d.rewards.assignRewardsToGuardians(
//         guardians.map(v => v.address),
//         stakingRewards,
//         fees,
//         bootstrapRewards
//     , {from: assigner.address});
//     expect(r).to.have.a.rewardsAssignedEvent({
//       assignees: guardians.map(v => v.address),
//       stakingRewards,
//       fees,
//       bootstrapRewards
//     });
//
//     expect(await d.rewards.getFeeBalance(guardians[0].address)).to.be.bignumber.eq(fees[0]);
//     expect(await d.rewards.getFeeBalance(guardians[1].address)).to.be.bignumber.eq(fees[1]);
//     expect(await d.rewards.getStakingRewardBalance(guardians[0].address)).to.be.bignumber.eq(stakingRewards[0]);
//     expect(await d.rewards.getStakingRewardBalance(guardians[1].address)).to.be.bignumber.eq(stakingRewards[1]);
//     expect(await d.rewards.getBootstrapBalance(guardians[0].address)).to.be.bignumber.eq(bootstrapRewards[0]);
//     expect(await d.rewards.getBootstrapBalance(guardians[1].address)).to.be.bignumber.eq(bootstrapRewards[1]);
//   });
//
//   it('withdraws to guardian address even if sent from orbs address, and updates balances', async () => {
//     const d = await Driver.new();
//
//     const guardians = [
//       (await d.newGuardian(fromTokenUnits(1), false, false, true)).v,
//       (await d.newGuardian(fromTokenUnits(1), false, false, true)).v,
//     ];
//
//     const stakingRewards = [fromTokenUnits(1), fromTokenUnits(2)];
//     const bootstrapRewards = [fromTokenUnits(3), fromTokenUnits(4)];
//     const fees = [fromTokenUnits(5), fromTokenUnits(6)];
//
//     const assigner = d.newParticipant();
//     await assigner.assignAndApproveOrbs(bnSum(stakingRewards).add(bnSum(fees)), d.rewards.address);
//     await assigner.assignAndApproveExternalToken(bnSum(bootstrapRewards), d.rewards.address);
//
//     let r = await d.rewards.assignRewardsToGuardians(
//         guardians.map(v => v.address),
//         stakingRewards,
//         fees,
//         bootstrapRewards
//     , {from: assigner.address});
//
//     await d.rewards.withdrawFees({from: guardians[0].address});
//     await d.rewards.withdrawBootstrapFunds({from: guardians[0].address});
//     r = await d.rewards.distributeStakingRewards(
//         stakingRewards[0],
//         0,
//         1,
//         1,
//         0,
//         [guardians[0].address],
//         [stakingRewards[0]],
//         {from: guardians[0].address}
//     );
//     expect(r).to.have.a.stakedEvent({stakeOwner: guardians[0].address, amount: stakingRewards[0]});
//     expect(await d.erc20.balanceOf(guardians[0].address)).to.bignumber.eq(fees[0]);
//     expect(await d.bootstrapToken.balanceOf(guardians[0].address)).to.bignumber.eq(bootstrapRewards[0]);
//
//     await d.rewards.withdrawFees({from: guardians[1].orbsAddress});
//     await d.rewards.withdrawBootstrapFunds({from: guardians[1].orbsAddress});
//
//     r = await d.rewards.distributeStakingRewards(
//         stakingRewards[1],
//         0,
//         1,
//         1,
//         0,
//         [guardians[1].address],
//         [stakingRewards[1]],
//         {from: guardians[1].orbsAddress}
//     );
//     expect(r).to.have.a.stakedEvent({stakeOwner: guardians[1].address, amount: stakingRewards[1]});
//     expect(await d.erc20.balanceOf(guardians[1].address)).to.bignumber.eq(fees[1]);
//     expect(await d.bootstrapToken.balanceOf(guardians[1].address)).to.bignumber.eq(bootstrapRewards[1]);
//
//     expect(await d.rewards.getFeeBalance(guardians[0].address)).to.be.bignumber.eq(bn(0));
//     expect(await d.rewards.getFeeBalance(guardians[1].address)).to.be.bignumber.eq(bn(0));
//     expect(await d.rewards.getStakingRewardBalance(guardians[0].address)).to.be.bignumber.eq(bn(0));
//     expect(await d.rewards.getStakingRewardBalance(guardians[1].address)).to.be.bignumber.eq(bn(0));
//     expect(await d.rewards.getBootstrapBalance(guardians[0].address)).to.be.bignumber.eq(bn(0));
//     expect(await d.rewards.getBootstrapBalance(guardians[1].address)).to.be.bignumber.eq(bn(0));
//   });
//
//   it('performs emergency withdrawal only by the migration manager', async () => {
//     const d = await Driver.new();
//
//     const guardians = [d.newParticipant(), d.newParticipant()];
//     const stakingRewards = [fromTokenUnits(1), fromTokenUnits(2)];
//     const bootstrapRewards = [fromTokenUnits(3), fromTokenUnits(4)];
//     const fees = [fromTokenUnits(5), fromTokenUnits(6)];
//
//     const assigner = d.newParticipant();
//     await assigner.assignAndApproveOrbs(bnSum(stakingRewards).add(bnSum(fees)), d.rewards.address);
//     await assigner.assignAndApproveExternalToken(bnSum(bootstrapRewards), d.rewards.address);
//
//     let r = await d.rewards.assignRewardsToGuardians(
//         guardians.map(v => v.address),
//         stakingRewards,
//         fees,
//         bootstrapRewards
//         , {from: assigner.address});
//
//     await expectRejected(d.rewards.emergencyWithdraw({from: d.functionalOwner.address}));
//     r = await d.rewards.emergencyWithdraw({from: d.migrationOwner.address});
//     expect(r).to.have.a.emergencyWithdrawalEvent({addr: d.migrationOwner.address});
//
//     expect(await d.erc20.balanceOf(d.migrationOwner.address)).to.bignumber.eq(bnSum(stakingRewards).add(bnSum(fees)));
//     expect(await d.bootstrapToken.balanceOf(d.migrationOwner.address)).to.bignumber.eq(bnSum(bootstrapRewards));
//   });
//
// });
