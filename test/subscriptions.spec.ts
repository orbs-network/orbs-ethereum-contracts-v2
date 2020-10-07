import 'mocha';

import BN from "bn.js";
import {defaultDriverOptions, DEPLOYMENT_SUBSET_CANARY, DEPLOYMENT_SUBSET_MAIN, Driver, ZERO_ADDR} from "./driver";
import chai from "chai";
import {subscriptionChangedEvents} from "./event-parsing";
import {chaiEventMatchersPlugin} from "./matchers";
import {bn, expectRejected, fromTokenUnits, getBlockTimestamp} from "./helpers";
chai.use(require('chai-bn')(BN));
chai.use(chaiEventMatchersPlugin);

const expect = chai.expect;

async function sleep(ms): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

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
    const blockTimestamp = new BN(await getBlockTimestamp(d, blockNumber));
    const expectedGenRefTime = blockTimestamp.add(bn(genesisRefTimeDelay));
    const secondsInMonth = new BN(30 * 24 * 60 * 60);
    const payedDurationInSeconds = firstPayment.mul(secondsInMonth).div(monthlyRate);
    let expectedExpiration = new BN(blockTimestamp).add(payedDurationInSeconds);

    expect(firstSubsc.vcId).to.exist;
    expect(firstSubsc.genRefTime).to.be.bignumber.equal(expectedGenRefTime);
    expect(firstSubsc.expiresAt).to.be.bignumber.equal(expectedExpiration);
    expect(firstSubsc.tier).to.equal("defaultTier");
    expect(firstSubsc.name).to.equal("vc-name");

    let vcid = bn(firstSubsc.vcId);
    expect(r).to.have.paymentEvent({vcId: vcid, by: appOwner.address, amount: firstPayment, tier: "defaultTier", rate: monthlyRate});

    // Buy more time
    const anotherPayer = d.newParticipant(); // Notice - anyone can pay for any VC without affecting ownership. TBD?
    const secondPayment = new BN(3000);
    await d.erc20.assign(anotherPayer.address, secondPayment);
    await d.erc20.approve(subscriber.address, secondPayment, {from: anotherPayer.address});

    r = await subscriber.extendSubscription(vcid, secondPayment, {from: anotherPayer.address});
    expect(r).to.have.paymentEvent({vcId: vcid, by: anotherPayer.address, amount: secondPayment, tier: "defaultTier", rate: monthlyRate});

    expect(r).to.have.subscriptionChangedEvent();
    const secondSubsc = subscriptionChangedEvents(r).pop()!;

    const extendedDurationInSeconds = secondPayment.mul(secondsInMonth).div(monthlyRate);
    expectedExpiration = new BN(firstSubsc.expiresAt).add(extendedDurationInSeconds);

    expect(secondSubsc.vcId).to.equal(firstSubsc.vcId);
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
    const blockTimestamp = new BN(await getBlockTimestamp(d, blockNumber));
    const expectedGenRef = blockTimestamp.add(bn(3*60*60));
    const secondsInMonth = new BN(30 * 24 * 60 * 60);
    const payedDurationInSeconds = firstPayment.mul(secondsInMonth).div(monthlyRate);
    let expectedExpiration = new BN(blockTimestamp).add(payedDurationInSeconds);

    expect(firstSubsc.vcId).to.exist;
    expect(firstSubsc.genRefTime).to.be.bignumber.equal(expectedGenRef);
    expect(firstSubsc.expiresAt).to.be.bignumber.equal(expectedExpiration);
    expect(firstSubsc.tier).to.equal("defaultTier");

    let vcid = bn(firstSubsc.vcId);
    expect(r).to.have.paymentEvent({vcId: vcid, by: appOwner.address, amount: firstPayment, tier: "defaultTier", rate: monthlyRate});

    // Buy more time
    const anotherPayer = d.newParticipant(); // Notice - anyone can pay for any VC without affecting ownership. TBD?
    const secondPayment = new BN(3000);
    await d.erc20.assign(anotherPayer.address, secondPayment);
    await d.erc20.approve(subscriber.address, secondPayment, {from: anotherPayer.address});

    r = await subscriber.extendSubscription(vcid, secondPayment, {from: anotherPayer.address});
    expect(r).to.have.paymentEvent({vcId: vcid, by: anotherPayer.address, amount: secondPayment, tier: "defaultTier", rate: monthlyRate});

    expect(r).to.have.subscriptionChangedEvent();
    const secondSubsc = subscriptionChangedEvents(r).pop()!;

    const extendedDurationInSeconds = secondPayment.mul(secondsInMonth).div(monthlyRate);
    expectedExpiration = new BN(firstSubsc.expiresAt).add(extendedDurationInSeconds);

    expect(secondSubsc.vcId).to.equal(firstSubsc.vcId);
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
    const vcid = bn(subscriptionChangedEvents(r)[0].vcId);

    const key = 'key_' + Date.now().toString();

    // set
    const value = 'value_' + Date.now().toString();
    r = await d.subscriptions.setVcConfigRecord(vcid, key, value, {from: owner.address});
    expect(r).to.have.a.vcConfigRecordChangedEvent({
      vcId: vcid.toString(),
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
      vcId: vcid.toString(),
      key,
      value: value2
    });

    // get again
    v = await d.subscriptions.getVcConfigRecord(vcid, key, {from: nonOwner.address});
    expect(v).to.equal(value2);

    // clear
    r = await d.subscriptions.setVcConfigRecord(vcid, key, "", {from: owner.address});
    expect(r).to.have.a.vcConfigRecordChangedEvent({
      vcId: vcid.toString(),
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
    const vcid = bn(subscriptionChangedEvents(r)[0].vcId);
    expect(r).to.have.a.vcCreatedEvent({
      vcId: vcid.toString()
    });

    const newOwner = d.newParticipant();

    const nonOwner = d.newParticipant();
    await expectRejected(d.subscriptions.setVcOwner(vcid, newOwner.address, {from: nonOwner.address}), /only the vc owner can transfer ownership/);

    r = await d.subscriptions.setVcOwner(vcid, newOwner.address, {from: owner.address});
    expect(r).to.have.a.vcOwnerChangedEvent({
      vcId: vcid.toString(),
      previousOwner: owner.address,
      newOwner: newOwner.address
    });

    await expectRejected(d.subscriptions.setVcOwner(vcid, owner.address, {from: owner.address}), /only the vc owner can transfer ownership/);

    r = await d.subscriptions.setVcOwner(vcid, owner.address, {from: newOwner.address});
    expect(r).to.have.a.vcOwnerChangedEvent({
      vcId: vcid.toString(),
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
    const vcid = bn(subscriptionChangedEvents(r)[0].vcId);

    // can be extended with any amount
    await owner.assignAndApproveOrbs(1, subs.address);
    await subs.extendSubscription(vcid, 1, {from: owner.address});
  });


  it('extends subscription after expiration', async () => {
    const d = await Driver.new();
    const orbitonPerSecond = 30*24*60*60;
    const subs = await d.newSubscriber("tier", orbitonPerSecond);

    const owner = d.newParticipant();

    const oneSecondsWorth = 1;

    await d.subscriptions.setMinimumInitialVcPayment(oneSecondsWorth, {from: d.functionalManager.address});

    await owner.assignAndApproveOrbs(oneSecondsWorth, subs.address);
    let r = await subs.createVC("vc-name", oneSecondsWorth, false, "main", {from: owner.address});
    const vcid = bn(subscriptionChangedEvents(r)[0].vcId);
    const expiresAtOrig = bn(subscriptionChangedEvents(r)[0].expiresAt);

    // vc expires after one second
    expect(expiresAtOrig).to.be.bignumber.equal(bn(await getBlockTimestamp(d, r.blockNumber) + 1));

    // wait until after expiration
    await sleep(3 * 1000);

    await owner.assignAndApproveOrbs(oneSecondsWorth, subs.address);
    r = await subs.extendSubscription(vcid, oneSecondsWorth, {from: owner.address});
    const newExpiresAt = bn(subscriptionChangedEvents(r)[0].expiresAt);

    // vc expires only 1 second after being extended
    expect(newExpiresAt).to.be.bignumber.equal(bn(await getBlockTimestamp(d, r.blockNumber) + 1));
  });

  it('updates vc data on rate change', async () => {
    const d = await Driver.new();
    const orbitonPerSecond = 30*24*60*60;
    const subs = await d.newSubscriber("tier", orbitonPerSecond);

    const owner = d.newParticipant();

    const oneSecondsWorth = 1;

    await d.subscriptions.setMinimumInitialVcPayment(oneSecondsWorth, {from: d.functionalManager.address});

    await owner.assignAndApproveOrbs(oneSecondsWorth, subs.address);
    let r = await subs.createVC("vc-name", oneSecondsWorth, false, "main", {from: owner.address});
    const vcid = bn(subscriptionChangedEvents(r)[0].vcId);
    const expiresAtOrig = bn(subscriptionChangedEvents(r)[0].expiresAt);

    // vc expires after one second
    expect(expiresAtOrig).to.be.bignumber.equal(bn(await getBlockTimestamp(d, r.blockNumber) + 1));

    // wait until after expiration
    await sleep(3 * 1000);

    const subs2 = await d.newSubscriber("tier", orbitonPerSecond*2);
    await owner.assignAndApproveOrbs(oneSecondsWorth*2, subs2.address);
    r = await subs2.extendSubscription(vcid, oneSecondsWorth*2, {from: owner.address});
    const newExpiresAt = bn(subscriptionChangedEvents(r)[0].expiresAt);

    // vc expires only 1 second after being extended
    expect(newExpiresAt).to.be.bignumber.equal(bn(await getBlockTimestamp(d, r.blockNumber) + 1));
    expect(r).to.have.a.subscriptionChangedEvent({
      rate: bn(orbitonPerSecond*2)
    });
    expect((await d.subscriptions.getVcData(vcid))[2]).to.bignumber.eq(bn(orbitonPerSecond*2));
  });

  it('does not extend if tier does not match', async () => {
    const d = await Driver.new();
    const orbitonPerSecond = 30*24*60*60;
    const subs = await d.newSubscriber("tier", orbitonPerSecond);

    const owner = d.newParticipant();

    const oneSecondsWorth = 1;

    await d.subscriptions.setMinimumInitialVcPayment(oneSecondsWorth, {from: d.functionalManager.address});

    await owner.assignAndApproveOrbs(oneSecondsWorth, subs.address);
    let r = await subs.createVC("vc-name", oneSecondsWorth, false, "main", {from: owner.address});
    const vcid = bn(subscriptionChangedEvents(r)[0].vcId);
    const expiresAtOrig = bn(subscriptionChangedEvents(r)[0].expiresAt);

    // vc expires after one second
    expect(expiresAtOrig).to.be.bignumber.equal(bn(await getBlockTimestamp(d, r.blockNumber) + 1));

    // wait until after expiration
    await sleep(3 * 1000);

    const otherSubs = await d.newSubscriber("tier2", orbitonPerSecond);

    await owner.assignAndApproveOrbs(oneSecondsWorth, otherSubs.address);
    await expectRejected(otherSubs.extendSubscription(vcid, oneSecondsWorth, {from: owner.address}), /given tier must match the VC tier/);
  });

  it('allows only a subscriber to extend a vc', async () => {
    const d = await Driver.new();
    const orbitonPerSecond = 30*24*60*60;
    const subs = await d.newSubscriber("tier", orbitonPerSecond);

    const owner = d.newParticipant();

    const oneSecondsWorth = 1;

    await d.subscriptions.setMinimumInitialVcPayment(oneSecondsWorth, {from: d.functionalManager.address});

    await owner.assignAndApproveOrbs(oneSecondsWorth, subs.address);
    let r = await subs.createVC("vc-name", oneSecondsWorth, false, "main", {from: owner.address});
    const vcid = bn(subscriptionChangedEvents(r)[0].vcId);
    const expiresAtOrig = bn(subscriptionChangedEvents(r)[0].expiresAt);

    // vc expires after one second
    expect(expiresAtOrig).to.be.bignumber.equal(bn(await getBlockTimestamp(d, r.blockNumber) + 1));

    // wait until after expiration
    await sleep(3 * 1000);

    await owner.assignAndApproveOrbs(oneSecondsWorth, subs.address);
    await expectRejected(d.subscriptions.extendSubscription(vcid, oneSecondsWorth, "tier", fromTokenUnits(1000), owner.address, {from: owner.address}), /sender must be an authorized subscriber/);
  });

  it('extends subscription before expiration', async () => {
    const d = await Driver.new();
    const orbitonPerSecond = 30*24*60*60;
    const subs = await d.newSubscriber("tier", orbitonPerSecond);

    const owner = d.newParticipant();

    const oneHoursWorth = 60 * 60;

    await d.subscriptions.setMinimumInitialVcPayment(oneHoursWorth, {from: d.functionalManager.address});

    await owner.assignAndApproveOrbs(oneHoursWorth, subs.address);
    let r = await subs.createVC("vc-name", oneHoursWorth, false, "main", {from: owner.address});
    const vcid = bn(subscriptionChangedEvents(r)[0].vcId);
    const expiresAtOrig = bn(subscriptionChangedEvents(r)[0].expiresAt);

    // vc expires in one hour
    expect(expiresAtOrig).to.be.bignumber.equal(bn(await getBlockTimestamp(d, r.blockNumber) + 60 * 60));

    await owner.assignAndApproveOrbs(oneHoursWorth, subs.address);
    r = await subs.extendSubscription(vcid, oneHoursWorth, {from: owner.address});
    const newExpiresAt = bn(subscriptionChangedEvents(r)[0].expiresAt);

    // vc extended by 1 additional hour
    expect(newExpiresAt).to.be.bignumber.equal(expiresAtOrig.add(bn(60 * 60)));
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
    const vcid = bn(event.vcId);
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

    expect((await d.subscriptions.getSettings()).genesisRefTimeDelay).to.eq("123");
    expect((await d.subscriptions.getSettings()).minimumInitialVcPayment).to.eq("456");
  });

  it("imports VCs from previous contract", async () => {
    const d = await Driver.new();

    const owner = d.newParticipant();

    const amount = 10;
    const subs = await d.newSubscriber("tier", 1);
    await owner.assignAndApproveOrbs(amount, subs.address);
    let r = await subs.createVC("vc-name", amount, true, "main", {from: owner.address});

    const event = subscriptionChangedEvents(r)[0];
    const vcData = await d.subscriptions.getVcData(event.vcId);

    const newSubscriptions: any = await d.web3.deploy('Subscriptions', [
      d.contractRegistry.address,
      d.registryAdmin.address,
      d.erc20.address,
      3*60*60, 1, [event.vcId], 1000000, d.subscriptions.address]
    );

    expect(await newSubscriptions.getCreationTx()).to.have.a.subscriptionChangedEvent({
      vcId: event.vcId,
      name: "vc-name",
      tier: "tier",
      rate: bn(1),
      expiresAt: bn(vcData[3]),
      genRefTime: bn(vcData[4]),
      owner: owner.address,
      deploymentSubset: "main",
      isCertified: true
    });

    expect(await newSubscriptions.nextVcId()).to.bignumber.eq(bn(event.vcId).add(bn(1)));

  });

});
