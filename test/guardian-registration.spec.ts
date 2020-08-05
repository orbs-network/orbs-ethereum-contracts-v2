import 'mocha';

import BN from "bn.js";
import {Driver, ZERO_ADDR} from "./driver";
import chai from "chai";
import {subscriptionChangedEvents} from "./event-parsing";
import {expectRejected} from "./helpers";

chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const expect = chai.expect;

// todo: test that committees are updated as a result of registration changes
describe('guardian-registration', async () => {

  it("registers, updates and unregisters a guardian", async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    // register
    let r = await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
        v.contact
    , {from: v.address});
    expect(r).to.have.a.guardianRegisteredEvent({
      addr: v.address
    });
    expect(r).to.have.a.guardianDataUpdatedEvent({
      addr: v.address,
      ip: v.ip,
      orbsAddr: v.orbsAddress,
      name: v.name,
      website: v.website,
      contact: v.contact
    });
    const registrationTime = await d.web3.txTimestamp(r);
    const firstUpdateTime = await d.web3.txTimestamp(r);

    // get data
    expect(await d.guardiansRegistration.getGuardianData(v.address)).to.include({
      ip: v.ip,
      orbsAddr: v.orbsAddress,
      name: v.name,
      website: v.website,
      contact: v.contact,
      registration_time: registrationTime.toString(),
      last_update_time: firstUpdateTime.toString()
    });

    const _v = d.newParticipant();

    // update
    r = await d.guardiansRegistration.updateGuardian(
        _v.ip,
        _v.orbsAddress,
        _v.name,
        _v.website,
        _v.contact
    , {from: v.address});
    expect(r).to.have.a.guardianDataUpdatedEvent({
      addr: v.address,
      ip: _v.ip,
      orbsAddr: _v.orbsAddress,
      name: _v.name,
      website: _v.website,
      contact: _v.contact
    });
    const secondUpdateTime = await d.web3.txTimestamp(r);

    // get data after update
    expect(await d.guardiansRegistration.getGuardianData(v.address)).to.include({
      ip: _v.ip,
      orbsAddr: _v.orbsAddress,
      name: _v.name,
      website: _v.website,
      contact: _v.contact,
      registration_time: registrationTime.toString(),
      last_update_time: secondUpdateTime.toString()
    });

    r = await d.guardiansRegistration.unregisterGuardian({from: v.address});
    expect(r).to.have.a.guardianUnregisteredEvent({
      addr: v.address
    })
  });

  it("does not register if already registered", async () => {
    const d = await Driver.new();

    const v = d.newParticipant();
    let r = await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
        v.contact
    , {from: v.address});
    expect(r).to.have.a.guardianRegisteredEvent({
      addr: v.address
    });
    expect(r).to.have.a.guardianDataUpdatedEvent({
      addr: v.address,
      ip: v.ip,
      orbsAddr: v.orbsAddress,
      name: v.name,
      website: v.website,
      contact: v.contact
    });

    await expectRejected(d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
        v.contact
    , {from: v.address}), /already registered/);
  });

  it("does not unregister if not registered", async () => {
    const d = await Driver.new();

    const v = d.newParticipant();
    await expectRejected(d.guardiansRegistration.unregisterGuardian({from:v.address}), /not registered/);
  });

  it("does not allow registration or update with missing mandatory fields (orbs address)", async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    await expectRejected(d.guardiansRegistration.registerGuardian(
        v.ip,
        ZERO_ADDR,
        v.name,
        v.website,
        v.contact
        , {from: v.address}), /orbs address must be non zero/);

    let r = await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
        v.contact
        , {from: v.address});
    expect(r).to.have.a.guardianRegisteredEvent({
      addr: v.address
    });
    expect(r).to.have.a.guardianDataUpdatedEvent({
      addr: v.address,
      ip: v.ip,
      orbsAddr: v.orbsAddress,
      name: v.name,
      website: v.website,
      contact: v.contact
    });

    await expectRejected(d.guardiansRegistration.updateGuardian(
        v.ip,
        ZERO_ADDR,
        v.name,
        v.website,
        v.contact
        , {from: v.address}), /orbs address must be non zero/);

  });

  it("does not allow registration or update with missing mandatory fields (name)", async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    await expectRejected(d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        "",
        v.website,
        v.contact
        , {from: v.address}), /name must be given/);

    let r = await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
        v.contact
        , {from: v.address});
    expect(r).to.have.a.guardianRegisteredEvent({
      addr: v.address
    });
    expect(r).to.have.a.guardianDataUpdatedEvent({
      addr: v.address,
      ip: v.ip,
      orbsAddr: v.orbsAddress,
      name: v.name,
      website: v.website,
      contact: v.contact
    });

    await expectRejected(d.guardiansRegistration.updateGuardian(
        v.ip,
        v.orbsAddress,
        "",
        v.website,
        v.contact
        , {from: v.address}), /name must be given/);
  });

  it("allow registration or update with empty contact field", async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    let r = await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
        "",
        {from: v.address});
    expect(r).to.have.a.guardianRegisteredEvent({
      addr: v.address
    });
    
    expect(r).to.have.a.guardianDataUpdatedEvent({
      addr: v.address,
      ip: v.ip,
      orbsAddr: v.orbsAddress,
      name: v.name,
      website: v.website,
      contact: ""
    });

    let r1 = await d.guardiansRegistration.updateGuardian(
      v.ip,
      v.orbsAddress,
      v.name,
      v.website,
      "",
      {from: v.address});

    expect(r1).to.have.a.guardianDataUpdatedEvent({
      addr: v.address,
      ip: v.ip,
      orbsAddr: v.orbsAddress,
      name: v.name,
      website: v.website,
      contact: ""
    });
  });

  it('does not allow registering using an IP of an existing guardian', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
        v.contact
        , {from: v.address});

    const v2 = d.newParticipant();

    await expectRejected(d.guardiansRegistration.registerGuardian(
        v.ip,
        v2.orbsAddress,
        v2.name,
        v2.website,
        v2.contact,
        {from: v2.address}), /ip is already in use/);
  });

  it('does not allow a registered guardian to set an IP of an existing guardian', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
        v.contact
        , {from: v.address});

    const v2 = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v2.ip,
        v2.orbsAddress,
        v2.name,
        v2.website,
        v2.contact
        , {from: v2.address});

    await expectRejected(d.guardiansRegistration.updateGuardian(
        v.ip,
        v2.orbsAddress,
        v2.name,
        v2.website,
        v2.contact,
        {from: v2.address}), /ip is already in use/);
  });

  it('allows registering with an IP of a previously existing guardian that unregistered', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
        v.contact
        , {from: v.address});

    await d.guardiansRegistration.unregisterGuardian({from: v.address});

    const v2 = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v.ip,
        v2.orbsAddress,
        v2.name,
        v2.website,
        v2.contact
        , {from: v2.address});
  });

  it('allows a registered guardian to set an IP of a previously existing guardian that unregistered', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
        v.contact
        , {from: v.address});

    const v2 = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v2.ip,
        v2.orbsAddress,
        v2.name,
        v2.website,
        v2.contact
        , {from: v2.address});

    await d.guardiansRegistration.unregisterGuardian({from: v.address});

    await d.guardiansRegistration.updateGuardian(
        v.ip,
        v2.orbsAddress,
        v2.name,
        v2.website,
        v2.contact
    , {from: v2.address});

  });

  it('does not allow registering using an orbs address of an existing guardian', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
        v.contact
        , {from: v.address});

    const v2 = d.newParticipant();

    await expectRejected(d.guardiansRegistration.registerGuardian(
        v2.ip,
        v.orbsAddress,
        v2.name,
        v2.website,
        v2.contact,
        {from: v2.address}), /orbs address is already in use/);
  });

  it('does not allow a registered guardian to set an orbs address of an existing guardian', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
        v.contact
        , {from: v.address});

    const v2 = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v2.ip,
        v2.orbsAddress,
        v2.name,
        v2.website,
        v2.contact
        , {from: v2.address});

    await expectRejected(d.guardiansRegistration.updateGuardian(
        v2.ip,
        v.orbsAddress,
        v2.name,
        v2.website,
        v2.contact,
        {from: v2.address}), /orbs address is already in use/);
  });

  it('allows registering with an orbs address of a previously existing guardian that unregistered', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
        v.contact
        , {from: v.address});

    await d.guardiansRegistration.unregisterGuardian({from: v.address});

    const v2 = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v2.ip,
        v.orbsAddress,
        v2.name,
        v2.website,
        v2.contact
        , {from: v2.address});
  });

  it('allows a registered guardian to set an orbs address of a previously existing guardian that unregistered', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
        v.contact
        , {from: v.address});

    const v2 = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v2.ip,
        v2.orbsAddress,
        v2.name,
        v2.website,
        v2.contact
        , {from: v2.address});

    await d.guardiansRegistration.unregisterGuardian({from: v.address});

    await d.guardiansRegistration.updateGuardian(
        v2.ip,
        v.orbsAddress,
        v2.name,
        v2.website,
        v2.contact
    , {from: v2.address});

  });

  it('does not allow an unregistered guardian to update', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    await expectRejected(d.guardiansRegistration.updateGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
        v.contact
    , {from: v.address}), /not registered/);

  });

  it('allows a registered guardian to update without changing any detail', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
        v.contact
        , {from: v.address});

    await d.guardiansRegistration.updateGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
        v.contact
    , {from: v.address});

  });

  it('does not allow a registered guardian to update using its Orbs address', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
        v.contact
        , {from: v.address});

    await expectRejected(d.guardiansRegistration.updateGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
        v.contact
    , {from: v.orbsAddress}), /not registered/);
  });

  it('allows a registered guardian to update IP from both its orbs address and main address', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
        v.contact
        , {from: v.address});

    let r = await d.guardiansRegistration.updateGuardianIp(
        "0xaaaaaaaa"
    , {from: v.orbsAddress});
    expect(r).to.have.a.guardianDataUpdatedEvent({
      addr: v.address,
      ip: "0xaaaaaaaa"
    });

    r = await d.guardiansRegistration.updateGuardianIp(
        "0xbbbbbbbb"
    , {from: v.address});
    expect(r).to.have.a.guardianDataUpdatedEvent({
      addr: v.address,
      ip: "0xbbbbbbbb"
    });
  });

  it('sets, overrides, gets and clears guardian metadata', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();
    let r = await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
        v.contact
        , {from: v.address});
    expect(r).to.have.a.guardianRegisteredEvent({
      addr: v.address
    });
    expect(r).to.have.a.guardianDataUpdatedEvent({
      addr: v.address,
      ip: v.ip,
      orbsAddr: v.orbsAddress,
      name: v.name,
      website: v.website,
      contact: v.contact
    });
    const key = 'key_' + Date.now().toString();

    // set
    const value = 'value_' + Date.now().toString();

    r = await d.guardiansRegistration.setMetadata(key, value, {from: v.address});
    expect(r).to.have.a.guardianMetadataChangedEvent({
      addr: v.address,
      key,
      oldValue: "",
      newValue: value
    });

    // get
    const notGuardian = d.newParticipant();
    let retreivedValue = await d.guardiansRegistration.getMetadata(v.address, key, {from: notGuardian.address});
    expect(retreivedValue).to.equal(value);

    // override
    const value2 = 'value2_' + Date.now().toString();
    r = await d.guardiansRegistration.setMetadata(key, value2, {from: v.address});
    expect(r).to.have.a.guardianMetadataChangedEvent({
      addr: v.address,
      key,
      oldValue: value,
      newValue: value2
    });

    // get again
    retreivedValue = await d.guardiansRegistration.getMetadata(v.address, key, {from: notGuardian.address});
    expect(retreivedValue).to.equal(value2);

    // clear
    r = await d.guardiansRegistration.setMetadata(key, "", {from: v.address});
    expect(r).to.have.a.guardianMetadataChangedEvent({
      addr: v.address,
      key,
      oldValue: value2,
      newValue: ""
    });

    // get again
    retreivedValue = await d.guardiansRegistration.getMetadata(v.address, key, {from: notGuardian.address});
    expect(retreivedValue).to.equal("");
  });

  it('converts eth addrs to orbs addrs', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();
    let r = await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
        v.contact
        , {from: v.address});
    expect(r).to.have.a.guardianRegisteredEvent({
      addr: v.address
    });
    expect(r).to.have.a.guardianDataUpdatedEvent({
      addr: v.address,
      ip: v.ip,
      orbsAddr: v.orbsAddress,
      name: v.name,
      website: v.website,
      contact: v.contact
    });

    expect(await d.guardiansRegistration.getOrbsAddresses([v.address])).to.deep.equal([v.orbsAddress])
  });

  it('converts orbs addrs to eth addrs', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();
    let r = await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
        v.contact
        , {from: v.address});
    expect(r).to.have.a.guardianRegisteredEvent({
      addr: v.address
    });
    expect(r).to.have.a.guardianDataUpdatedEvent({
      addr: v.address,
      ip: v.ip,
      orbsAddr: v.orbsAddress,
      name: v.name,
      website: v.website,
      contact: v.contact
    });

    expect(await d.guardiansRegistration.getOrbsAddresses([v.address])).to.deep.equal([v.orbsAddress])
  });

  it('resolves ethereum address', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();
    await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
        v.contact
        , {from: v.address});

    expect(await d.guardiansRegistration.resolveGuardianAddress(v.address)).to.deep.equal(v.address);
    expect(await d.guardiansRegistration.resolveGuardianAddress(v.orbsAddress)).to.deep.equal(v.address);

    const v2 = d.newParticipant();
    await d.guardiansRegistration.registerGuardian(
        v2.ip,
        v.address,
        v2.name,
        v2.website,
        v2.contact
        , {from: v2.address});
    expect(await d.guardiansRegistration.resolveGuardianAddress(v.address)).to.deep.equal(v.address);
  });


});
