import 'mocha';

import BN from "bn.js";
import {defaultDriverOptions, Driver, ZERO_ADDR} from "./driver";
import chai from "chai";
import {subscriptionChangedEvents} from "./event-parsing";
import {bn, expectRejected} from "./helpers";
chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const expect = chai.expect;

describe('subscriptions-high-level-flows', async () => {

  it('registers and pays for a general VC', async () => {
    const d = await Driver.new();

    const monthlyRate = new BN(1000);
    const firstPayment = monthlyRate.mul(new BN(2));

    const subscriber = await d.newSubscriber("defaultTier", monthlyRate);
    // buy subscription for a new VC
    const appOwner = d.newParticipant();
    await d.erc20.assign(appOwner.address, firstPayment); // TODO extract assign+approve to driver in two places
    await d.erc20.approve(subscriber.address, firstPayment, {from: appOwner.address});

    let r = await subscriber.createVC("vc-name", firstPayment, false, "main",  {from: appOwner.address});

    expect(r).to.have.subscriptionChangedEvent();
    const firstSubsc = subscriptionChangedEvents(r).pop()!;

    const genesisRefTimeDelay = await d.subscriptions.getGenesisRefTimeDelay();
    const blockNumber = new BN(r.blockNumber);
    const blockTimestamp = new BN((await d.web3.eth.getBlock(blockNumber)).timestamp);
    const expectedGenRefTime = blockTimestamp.add(bn(genesisRefTimeDelay));
    const secondsInMonth = new BN(30 * 24 * 60 * 60);
    const payedDurationInSeconds = firstPayment.mul(secondsInMonth).div(monthlyRate);
    let expectedExpiration = new BN(blockTimestamp).add(payedDurationInSeconds);

    expect(firstSubsc.vcid).to.exist;
    expect(firstSubsc.genRefTime).to.be.bignumber.equal(expectedGenRefTime);
    expect(firstSubsc.expiresAt).to.be.bignumber.equal(expectedExpiration);
    expect(firstSubsc.tier).to.equal("defaultTier");
    expect(firstSubsc.name).to.equal("vc-name");

    let vcid = bn(firstSubsc.vcid);
    expect(r).to.have.paymentEvent({vcid, by: appOwner.address, amount: firstPayment, tier: "defaultTier", rate: monthlyRate});

    // Buy more time
    const anotherPayer = d.newParticipant(); // Notice - anyone can pay for any VC without affecting ownership. TBD?
    const secondPayment = new BN(3000);
    await d.erc20.assign(anotherPayer.address, secondPayment);
    await d.erc20.approve(subscriber.address, secondPayment, {from: anotherPayer.address});

    r = await subscriber.extendSubscription(vcid, secondPayment, {from: anotherPayer.address});
    expect(r).to.have.paymentEvent({vcid, by: anotherPayer.address, amount: secondPayment, tier: "defaultTier", rate: monthlyRate});

    expect(r).to.have.subscriptionChangedEvent();
    const secondSubsc = subscriptionChangedEvents(r).pop()!;

    const extendedDurationInSeconds = secondPayment.mul(secondsInMonth).div(monthlyRate);
    expectedExpiration = new BN(firstSubsc.expiresAt).add(extendedDurationInSeconds);

    expect(secondSubsc.vcid).to.equal(firstSubsc.vcid);
    expect(secondSubsc.genRefTime).to.be.equal(firstSubsc.genRefTime);
    expect(secondSubsc.expiresAt).to.be.bignumber.equal(expectedExpiration);
    expect(secondSubsc.tier).to.equal("defaultTier");


    expect(await d.erc20.balanceOf(appOwner.address)).is.bignumber.equal('0');
    expect(await d.erc20.balanceOf(anotherPayer.address)).is.bignumber.equal('0');
    expect(await d.erc20.balanceOf(subscriber.address)).is.bignumber.equal('0');
    expect(await d.erc20.balanceOf(d.subscriptions.address)).is.bignumber.equal('0');

    expect(await d.erc20.balanceOf(d.generalFeesWallet.address)).is.bignumber.equal(firstPayment.add(secondPayment));
  });

  it('registers and pays for a certification VC', async () => {
    const d = await Driver.new();

    const monthlyRate = new BN(1000);
    const firstPayment = monthlyRate.mul(new BN(2));

    const subscriber = await d.newSubscriber("defaultTier", monthlyRate);
    // buy subscription for a new VC
    const appOwner = d.newParticipant();
    await d.erc20.assign(appOwner.address, firstPayment); // TODO extract assign+approve to driver in two places
    await d.erc20.approve(subscriber.address, firstPayment, {from: appOwner.address});

    let r = await subscriber.createVC("vc-name", firstPayment, true, "main",  {from: appOwner.address});

    expect(r).to.have.subscriptionChangedEvent();
    const firstSubsc = subscriptionChangedEvents(r).pop()!;

    const blockNumber = new BN(r.blockNumber);
    const blockTimestamp = new BN((await d.web3.eth.getBlock(blockNumber)).timestamp);
    const expectedGenRef = blockTimestamp.add(bn(3*60*60));
    const secondsInMonth = new BN(30 * 24 * 60 * 60);
    const payedDurationInSeconds = firstPayment.mul(secondsInMonth).div(monthlyRate);
    let expectedExpiration = new BN(blockTimestamp).add(payedDurationInSeconds);

    expect(firstSubsc.vcid).to.exist;
    expect(firstSubsc.genRefTime).to.be.bignumber.equal(expectedGenRef);
    expect(firstSubsc.expiresAt).to.be.bignumber.equal(expectedExpiration);
    expect(firstSubsc.tier).to.equal("defaultTier");

    let vcid = bn(firstSubsc.vcid);
    expect(r).to.have.paymentEvent({vcid, by: appOwner.address, amount: firstPayment, tier: "defaultTier", rate: monthlyRate});

    // Buy more time
    const anotherPayer = d.newParticipant(); // Notice - anyone can pay for any VC without affecting ownership. TBD?
    const secondPayment = new BN(3000);
    await d.erc20.assign(anotherPayer.address, secondPayment);
    await d.erc20.approve(subscriber.address, secondPayment, {from: anotherPayer.address});

    r = await subscriber.extendSubscription(vcid, secondPayment, {from: anotherPayer.address});
    expect(r).to.have.paymentEvent({vcid, by: anotherPayer.address, amount: secondPayment, tier: "defaultTier", rate: monthlyRate});

    expect(r).to.have.subscriptionChangedEvent();
    const secondSubsc = subscriptionChangedEvents(r).pop()!;

    const extendedDurationInSeconds = secondPayment.mul(secondsInMonth).div(monthlyRate);
    expectedExpiration = new BN(firstSubsc.expiresAt).add(extendedDurationInSeconds);

    expect(secondSubsc.vcid).to.equal(firstSubsc.vcid);
    expect(secondSubsc.genRefTime).to.be.equal(firstSubsc.genRefTime);
    expect(secondSubsc.expiresAt).to.be.bignumber.equal(expectedExpiration);
    expect(secondSubsc.tier).to.equal("defaultTier");


    expect(await d.erc20.balanceOf(appOwner.address)).is.bignumber.equal('0');
    expect(await d.erc20.balanceOf(anotherPayer.address)).is.bignumber.equal('0');
    expect(await d.erc20.balanceOf(subscriber.address)).is.bignumber.equal('0');
    expect(await d.erc20.balanceOf(d.subscriptions.address)).is.bignumber.equal('0');

    expect(await d.erc20.balanceOf(d.certifiedFeesWallet.address)).is.bignumber.equal(firstPayment.add(secondPayment));
  });

  it('adds and removes subscriber only by functional owner', async () => {
    const d = await Driver.new();
    const subscriber = await d.newSubscriber('tier', 1);

    await expectRejected(d.subscriptions.addSubscriber(subscriber.address, {from: d.contractsNonOwnerAddress}), /sender is not the functional manager/);
    let r = await d.subscriptions.addSubscriber(subscriber.address, {from: d.functionalManager.address});
    expect(r).to.have.a.subscriberAddedEvent({subscriber: subscriber.address})

    await expectRejected(d.subscriptions.removeSubscriber(subscriber.address, {from: d.contractsNonOwnerAddress}), /sender is not the functional manager/);
    r = await d.subscriptions.removeSubscriber(subscriber.address, {from: d.functionalManager.address});
    expect(r).to.have.a.subscriberRemovedEvent({subscriber: subscriber.address})
  });

  it('is able to create multiple VCs from the same subscriber', async () => {
    const d = await Driver.new();
    const subs = await d.newSubscriber("tier", 1);

    const owner = d.newParticipant();
    const amount = 10;

    await owner.assignAndApproveOrbs(amount, subs.address);
    let r = await subs.createVC("vc-name", amount, false, "main",  {from: owner.address});
    expect(r).to.have.a.subscriptionChangedEvent();

    await owner.assignAndApproveOrbs(amount, subs.address);
    r = await subs.createVC("vc-name", amount, false, "main",  {from: owner.address});
    expect(r).to.have.a.subscriptionChangedEvent();
  });

  it('sets, overrides, gets and clears a vc config field by and only by the vc owner', async () => {
    const d = await Driver.new();
    const subs = await d.newSubscriber("tier", 1);

    const owner = d.newParticipant();
    const amount = 10;

    await owner.assignAndApproveOrbs(amount, subs.address);
    let r = await subs.createVC("vc-name", amount, false, "main",  {from: owner.address});
    expect(r).to.have.a.subscriptionChangedEvent();
    const vcid = bn(subscriptionChangedEvents(r)[0].vcid);

    const key = 'key_' + Date.now().toString();

    // set
    const value = 'value_' + Date.now().toString();
    r = await d.subscriptions.setVcConfigRecord(vcid, key, value, {from: owner.address});
    expect(r).to.have.a.vcConfigRecordChangedEvent({
      vcid: vcid.toString(),
      key,
      value
    });

    // get
    const nonOwner = d.newParticipant();
    let v = await d.subscriptions.getVcConfigRecord(vcid, key, {from: nonOwner.address});
    expect(v).to.equal(value);

    // override
    const value2 = 'value2_' + Date.now().toString();
    r = await d.subscriptions.setVcConfigRecord(vcid, key, value2, {from: owner.address});
    expect(r).to.have.a.vcConfigRecordChangedEvent({
      vcid: vcid.toString(),
      key,
      value: value2
    });

    // get again
    v = await d.subscriptions.getVcConfigRecord(vcid, key, {from: nonOwner.address});
    expect(v).to.equal(value2);

    // clear
    r = await d.subscriptions.setVcConfigRecord(vcid, key, "", {from: owner.address});
    expect(r).to.have.a.vcConfigRecordChangedEvent({
      vcid: vcid.toString(),
      key,
      value: ""
    });

    // get again
    v = await d.subscriptions.getVcConfigRecord(vcid, key, {from: nonOwner.address});
    expect(v).to.equal("");

    // reject if set by non owner
    await expectRejected(d.subscriptions.setVcConfigRecord(vcid, key, value, {from: nonOwner.address}), /only vc owner can set a vc config record/);
  });

  it('allows VC owner to transfer ownership', async () => {
    const d = await Driver.new();
    const subs = await d.newSubscriber("tier", 1);

    const owner = d.newParticipant();

    const amount = 10;
    await owner.assignAndApproveOrbs(amount, subs.address);
    let r = await subs.createVC("vc-name", amount, false, "main", {from: owner.address});
    expect(r).to.have.a.subscriptionChangedEvent();
    const vcid = bn(subscriptionChangedEvents(r)[0].vcid);
    expect(r).to.have.a.vcCreatedEvent({
      vcid: vcid.toString(),
      owner: owner.address
    });

    const newOwner = d.newParticipant();

    const nonOwner = d.newParticipant();
    await expectRejected(d.subscriptions.setVcOwner(vcid, newOwner.address, {from: nonOwner.address}), /only the vc owner can transfer ownership/);

    r = await d.subscriptions.setVcOwner(vcid, newOwner.address, {from: owner.address});
    expect(r).to.have.a.vcOwnerChangedEvent({
      vcid: vcid.toString(),
      previousOwner: owner.address,
      newOwner: newOwner.address
    });

    await expectRejected(d.subscriptions.setVcOwner(vcid, owner.address, {from: owner.address}), /only the vc owner can transfer ownership/);

    r = await d.subscriptions.setVcOwner(vcid, owner.address, {from: newOwner.address});
    expect(r).to.have.a.vcOwnerChangedEvent({
      vcid: vcid.toString(),
      previousOwner: newOwner.address,
      newOwner: owner.address
    });

  });

  it('enforces initial payment is at least minimumInitialVcPayment', async () => {
    const d = await Driver.new();
    const subs = await d.newSubscriber("tier", 1);

    const owner = d.newParticipant();

    const amount = 10;
    await d.subscriptions.setMinimumInitialVcPayment(amount, {from: d.functionalManager.address});

    await owner.assignAndApproveOrbs(amount - 1, subs.address);
    expectRejected(subs.createVC("vc-name", amount - 1, false, "main", {from: owner.address}), /initial VC payment must be at least minimumInitialVcPayment/);

    await owner.assignAndApproveOrbs(amount, subs.address);
    await subs.createVC("vc-name", amount, false, "main", {from: owner.address});

    await owner.assignAndApproveOrbs(amount + 1, subs.address);
    let r = await subs.createVC("vc-name", amount + 1, false, "main", {from: owner.address});
    const vcid = bn(subscriptionChangedEvents(r)[0].vcid);

    // can be extended with any amount
    await owner.assignAndApproveOrbs(1, subs.address);
    await subs.extendSubscription(vcid, 1, {from: owner.address});
  });

  it('allows only the functional owner to set default genesis ref time delay', async () => {
    const d = await Driver.new();

    const newDelay = 4*60*60;
    await expectRejected(d.subscriptions.setGenesisRefTimeDelay(newDelay, {from: d.migrationManager.address}), /sender is not the functional manager/);
    let r = await d.subscriptions.setGenesisRefTimeDelay(newDelay, {from: d.functionalManager.address});
    expect(r).to.have.a.genesisRefTimeDelayChangedEvent({newGenesisRefTimeDelay: bn(newDelay)})

    const subs = await d.newSubscriber("tier", 1);

    const owner = d.newParticipant();

    const amount = 10;
    await owner.assignAndApproveOrbs(amount, subs.address);
    r = await subs.createVC("vc-name", amount, false, "main", {from: owner.address});
    expect(r).to.have.a.subscriptionChangedEvent({
      genRefTime: bn(await d.web3.txTimestamp(r) + newDelay)
    });
  });

  it('allows only the functional owner to set minimumInitialVcPayment', async () => {
    const d = await Driver.new();

    const newMin = 1000;
    await expectRejected(d.subscriptions.setMinimumInitialVcPayment(newMin, {from: d.migrationManager.address}), /sender is not the functional manager/);
    let r = await d.subscriptions.setMinimumInitialVcPayment(newMin, {from: d.functionalManager.address});
    expect(r).to.have.a.minimumInitialVcPaymentChangedEvent({newMinimumInitialVcPayment: bn(newMin)})

    expect(await d.subscriptions.getMinimumInitialVcPayment()).to.bignumber.eq(bn(newMin));
  });

  it('gets vc data', async () => {
    const d = await Driver.new();

    const subs = await d.newSubscriber("tier", 1);

    const owner = d.newParticipant();

    const amount = 10;
    await owner.assignAndApproveOrbs(amount, subs.address);
    let r = await subs.createVC("vc-name", amount, false, "main", {from: owner.address});

    const event = subscriptionChangedEvents(r)[0];
    const vcid = bn(event.vcid);
    const vcData = await d.subscriptions.getVcData(vcid);
    expect([
        vcData[0],
        vcData[1],
        vcData[2],
        vcData[3],
        vcData[4],
        vcData[5],
        vcData[6],
        vcData[7]
    ]).to.deep.eq([
      'vc-name' /* name */,
      'tier' /* tier */,
      '1' /* rate */,
      event.expiresAt /* expiresAt */,
      event.genRefTime /* genRefTime */,
      owner.address /* owner */,
      'main' /* deploymentSubset */,
      false /* isCertified */
    ])

  });

  it("gets settings", async () => {
    const d = await Driver.new({genesisRefTimeDelay: 123, minimumInitialVcPayment: 456});

    expect(await d.subscriptions.getGenesisRefTimeDelay()).to.eq("123");
    expect(await d.subscriptions.getMinimumInitialVcPayment()).to.eq("456");
  });

});
