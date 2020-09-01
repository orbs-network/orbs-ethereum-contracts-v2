import 'mocha';


import BN from "bn.js";
import {Driver} from "./driver";
import chai from "chai";

chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const expect = chai.expect;

import {bn, evmIncreaseTime, evmIncreaseTimeForQueries, expectRejected, getTopBlockTimestamp} from "./helpers";

const YEAR_IN_SECONDS = 365*24*60*60;

describe('protocol-contract', async () => {

  it('returns erc20 address using getter', async () => {
    const d = await Driver.new();
    expect(await d.stakingRewardsWallet.getToken()).to.eq(d.erc20.address);
  });

  it('tops up the wallet', async () => {
    const d = await Driver.new();
    const amount = bn(1000);
    const p = d.newParticipant();

    await p.assignAndApproveOrbs(amount, d.stakingRewardsWallet.address);
    let r = await d.stakingRewardsWallet.topUp(amount, {from: p.address});
    expect(r).to.have.a.fundsAddedToPoolEvent({added: amount, total: amount});

    await p.assignAndApproveOrbs(amount, d.stakingRewardsWallet.address);
    r = await d.stakingRewardsWallet.topUp(amount, {from: p.address});
    expect(r).to.have.a.fundsAddedToPoolEvent({added: amount, total: amount.add(amount)});

    expect(await d.stakingRewardsWallet.getBalance()).to.bignumber.eq(amount.add(amount));
    expect(await d.erc20.balanceOf(d.stakingRewardsWallet.address)).to.bignumber.eq(amount.add(amount));
  });


  it('ensures only client can withdraw', async () => {
    const d = await Driver.new();
    const amount = bn(1000);
    const p = d.newParticipant();

    await p.assignAndApproveOrbs(amount, d.stakingRewardsWallet.address);
    await d.stakingRewardsWallet.topUp(amount, {from: p.address});

    const client = d.newParticipant();
    await d.stakingRewardsWallet.setClient(client.address, {from: d.functionalManager.address});
    await d.stakingRewardsWallet.setMaxAnnualRate(amount, {from: d.migrationManager.address});

    await evmIncreaseTime(d.web3, YEAR_IN_SECONDS);

    await expectRejected(d.stakingRewardsWallet.withdraw(amount, {from: p.address}), /caller is not the wallet client/);
    await d.stakingRewardsWallet.withdraw(amount, {from: client.address});
    expect(await d.erc20.balanceOf(client.address)).to.eq(amount.toString());
  });

  it('allows only the functional owner to set a client', async () => {
    const d = await Driver.new();
    const amount = bn(1000);
    const p = d.newParticipant();

    await p.assignAndApproveOrbs(amount, d.stakingRewardsWallet.address);
    await d.stakingRewardsWallet.topUp(amount, {from: p.address});

    const client = d.newParticipant();
    await expectRejected(d.stakingRewardsWallet.setClient(client.address, {from: d.migrationManager.address}), /caller is not the functionalOwner/);
    let r = await d.stakingRewardsWallet.setClient(client.address, {from: d.functionalManager.address});
    expect(r).to.have.a.clientSetEvent({client: client.address});

    await d.stakingRewardsWallet.setMaxAnnualRate(amount, {from: d.migrationManager.address});

    await evmIncreaseTime(d.web3, YEAR_IN_SECONDS);

    await expectRejected(d.stakingRewardsWallet.withdraw(amount, {from: p.address}), /caller is not the wallet client/);
    await d.stakingRewardsWallet.withdraw(amount, {from: client.address});
    expect(await d.erc20.balanceOf(client.address)).to.eq(amount.toString());
  });

  it('allows only the migration owner to set a new rate', async () => {
    const d = await Driver.new();
    const amount = bn(1000);
    const p = d.newParticipant();

    await p.assignAndApproveOrbs(amount, d.stakingRewardsWallet.address);
    await d.stakingRewardsWallet.topUp(amount, {from: p.address});

    const client = d.newParticipant();
    await d.stakingRewardsWallet.setClient(client.address, {from: d.functionalManager.address});

    await expectRejected(d.stakingRewardsWallet.setMaxAnnualRate(amount, {from: d.functionalManager.address}), /caller is not the migrationOwner/);
    let r = await d.stakingRewardsWallet.setMaxAnnualRate(amount, {from: d.migrationManager.address});
    expect(r).to.have.a.maxAnnualRateSetEvent({ maxAnnualRate: amount });

    await evmIncreaseTime(d.web3, YEAR_IN_SECONDS / 2);

    await expectRejected(d.stakingRewardsWallet.withdraw(amount.mul(bn(3)).div(bn(4)), {from: client.address}), /requested amount is larger than allowed by rate/);
    await d.stakingRewardsWallet.withdraw(amount.div(bn(2)), {from: client.address});
    expect(await d.erc20.balanceOf(client.address)).to.eq(amount.div(bn(2)).toString());
  });

  it('allows to withdraw according to rate', async () => {
    const d = await Driver.new();
    const amount = bn(1000);
    const p = d.newParticipant();

    await p.assignAndApproveOrbs(amount, d.stakingRewardsWallet.address);
    await d.stakingRewardsWallet.topUp(amount, {from: p.address});

    const client = d.newParticipant();
    await d.stakingRewardsWallet.setClient(client.address, {from: d.functionalManager.address});
    await d.stakingRewardsWallet.setMaxAnnualRate(amount, {from: d.migrationManager.address});

    await evmIncreaseTime(d.web3, YEAR_IN_SECONDS / 2);

    await expectRejected(d.stakingRewardsWallet.withdraw(amount.mul(bn(3)).div(bn(4)), {from: client.address}), /requested amount is larger than allowed by rate/);
    await d.stakingRewardsWallet.withdraw(amount.div(bn(2)), {from: client.address});
    expect(await d.erc20.balanceOf(client.address)).to.eq(amount.div(bn(2)).toString());
  });

  it('allows to withdraw according to rate (no leaky bucket)', async () => {
    const d = await Driver.new();
    const amount = bn(1000);
    const p = d.newParticipant();

    await p.assignAndApproveOrbs(amount, d.stakingRewardsWallet.address);
    await d.stakingRewardsWallet.topUp(amount, {from: p.address});

    const client = d.newParticipant();
    await d.stakingRewardsWallet.setClient(client.address, {from: d.functionalManager.address});
    await d.stakingRewardsWallet.setMaxAnnualRate(amount, {from: d.migrationManager.address});

    await evmIncreaseTime(d.web3, YEAR_IN_SECONDS / 2);

    await d.stakingRewardsWallet.withdraw(1, {from: client.address});

    await evmIncreaseTime(d.web3, YEAR_IN_SECONDS / 2);

    await expectRejected(d.stakingRewardsWallet.withdraw(amount.mul(bn(3)).div(bn(4)), {from: client.address}), /requested amount is larger than allowed by rate/);
  });

  it('rate change applies retroactively', async () => {
    const d = await Driver.new();
    const amount = bn(1000);
    const p = d.newParticipant();

    await p.assignAndApproveOrbs(amount, d.stakingRewardsWallet.address);
    await d.stakingRewardsWallet.topUp(amount, {from: p.address});

    const client = d.newParticipant();
    await d.stakingRewardsWallet.setClient(client.address, {from: d.functionalManager.address});
    await d.stakingRewardsWallet.setMaxAnnualRate(amount, {from: d.migrationManager.address});

    await evmIncreaseTime(d.web3, YEAR_IN_SECONDS);
    await d.stakingRewardsWallet.setMaxAnnualRate(1, {from: d.migrationManager.address});

    await expectRejected(d.stakingRewardsWallet.withdraw(2, {from: client.address}), /requested amount is larger than allowed by rate/);
    await d.stakingRewardsWallet.withdraw(1, {from: client.address});

    await evmIncreaseTime(d.web3, YEAR_IN_SECONDS / 2);

    await expectRejected(d.stakingRewardsWallet.withdraw(amount.mul(bn(3)).div(bn(4)), {from: client.address}), /requested amount is larger than allowed by rate/);
  });

  it('performs emergency withdrawal only by the migration manager', async () => {
    const d = await Driver.new();
    const amount = bn(1000);
    const p = d.newParticipant();

    await p.assignAndApproveOrbs(amount, d.stakingRewardsWallet.address);
    await d.stakingRewardsWallet.topUp(amount, {from: p.address});

    await expectRejected(d.stakingRewardsWallet.emergencyWithdraw({from: d.functionalManager.address}), /caller is not the migrationOwner/);
    let r = await d.stakingRewardsWallet.emergencyWithdraw({from: d.migrationManager.address});
    expect(r).to.have.a.emergencyWithdrawalEvent({addr: d.migrationManager.address});

    expect(await d.erc20.balanceOf(d.migrationManager.address)).to.bignumber.eq(amount);
  });

  it('skips ERC20 withdrawal when amount is zero', async () => {
    const d = await Driver.new();

    const client = d.newParticipant();
    await d.stakingRewardsWallet.setClient(client.address, {from: d.functionalManager.address});
    await d.stakingRewardsWallet.setMaxAnnualRate(1000, {from: d.migrationManager.address});

    await client.assignAndApproveOrbs(1000, d.stakingRewardsWallet.address);
    await d.stakingRewardsWallet.topUp(1000, {from: client.address});

    await evmIncreaseTime(d.web3, YEAR_IN_SECONDS);

    let r = await d.stakingRewardsWallet.withdraw(0, {from: client.address});
    expect(r).to.not.have.a.transferEvent();

    await evmIncreaseTime(d.web3, YEAR_IN_SECONDS);

    r = await d.stakingRewardsWallet.withdraw(1, {from: client.address});
    expect(r).to.have.a.transferEvent();
  });

});

