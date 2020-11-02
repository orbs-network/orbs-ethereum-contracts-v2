import 'mocha';

import BN from "bn.js";
import {Driver, ZERO_ADDR} from "./driver";
import chai from "chai";
import {bn, evmIncreaseTime, expectRejected} from "./helpers";
import {GuardiansRegistrationContract} from "../typings/guardian-registration-contract";
import {chaiEventMatchersPlugin} from "./matchers";

chai.use(require('chai-bn')(BN));
chai.use(chaiEventMatchersPlugin);

const expect = chai.expect;

describe('guardian-registration', async () => {

  it("registers, updates and unregisters a guardian", async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    // register
    let r = await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website
    , {from: v.address});
    const registrationTime = await d.web3.txTimestamp(r);
    expect(r).to.have.a.guardianRegisteredEvent({
      guardian: v.address
    });
    expect(r).to.have.a.guardianDataUpdatedEvent({
      guardian: v.address,
      isRegistered: true,
      ip: v.ip,
      orbsAddr: v.orbsAddress,
      name: v.name,
      website: v.website,
      registrationTime: bn(registrationTime)
    });

    // get data
    expect(await d.guardiansRegistration.getGuardianData(v.address)).to.include({
      ip: v.ip,
      orbsAddr: v.orbsAddress,
      name: v.name,
      website: v.website,
      registrationTime: registrationTime.toString(),
      lastUpdateTime: registrationTime.toString()
    });

    const _v = d.newParticipant();

    // update
    r = await d.guardiansRegistration.updateGuardian(
        _v.ip,
        _v.orbsAddress,
        _v.name,
        _v.website
    , {from: v.address});
    expect(r).to.have.a.guardianDataUpdatedEvent({
      guardian: v.address,
      isRegistered: true,
      ip: _v.ip,
      orbsAddr: _v.orbsAddress,
      name: _v.name,
      website: _v.website
    });
    const secondUpdateTime = await d.web3.txTimestamp(r);

    // get data after update
    expect(await d.guardiansRegistration.getGuardianData(v.address)).to.include({
      ip: _v.ip,
      orbsAddr: _v.orbsAddress,
      name: _v.name,
      website: _v.website,
      registrationTime: registrationTime.toString(),
      lastUpdateTime: secondUpdateTime.toString()
    });

    r = await d.guardiansRegistration.unregisterGuardian({from: v.address});
    expect(r).to.have.a.guardianUnregisteredEvent({
      guardian: v.address
    });
    expect(r).to.have.a.guardianDataUpdatedEvent({
      guardian: v.address,
      isRegistered: false,
      ip: _v.ip,
      orbsAddr: _v.orbsAddress,
      name: _v.name,
      website: _v.website
    });
  });

  it("does not register if already registered", async () => {
    const d = await Driver.new();

    const v = d.newParticipant();
    let r = await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website
    , {from: v.address});
    expect(r).to.have.a.guardianRegisteredEvent({
      guardian: v.address
    });
    expect(r).to.have.a.guardianDataUpdatedEvent({
      guardian: v.address,
      isRegistered: true,
      ip: v.ip,
      orbsAddr: v.orbsAddress,
      name: v.name,
      website: v.website
    });

    await expectRejected(d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website
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
         {from: v.address}), /orbs address must be non zero/);

    let r = await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
         {from: v.address});
    expect(r).to.have.a.guardianRegisteredEvent({
      guardian: v.address
    });
    expect(r).to.have.a.guardianDataUpdatedEvent({
      guardian: v.address,
      isRegistered: true,
      ip: v.ip,
      orbsAddr: v.orbsAddress,
      name: v.name,
      website: v.website
    });

    await expectRejected(d.guardiansRegistration.updateGuardian(
        v.ip,
        ZERO_ADDR,
        v.name,
        v.website
        , {from: v.address}), /orbs address must be non zero/);

  });

  it("does not allow registration or update with missing mandatory fields (name)", async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    await expectRejected(d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        "",
        v.website
        , {from: v.address}), /name must be given/);

    let r = await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website
        , {from: v.address});
    expect(r).to.have.a.guardianRegisteredEvent({
      guardian: v.address
    });
    expect(r).to.have.a.guardianDataUpdatedEvent({
      guardian: v.address,
      isRegistered: true,
      ip: v.ip,
      orbsAddr: v.orbsAddress,
      name: v.name,
      website: v.website
    });

    await expectRejected(d.guardiansRegistration.updateGuardian(
        v.ip,
        v.orbsAddress,
        "",
        v.website
        , {from: v.address}), /name must be given/);
  });

  it('does not allow registering using an IP of an existing guardian', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website
        , {from: v.address});

    const v2 = d.newParticipant();

    await expectRejected(d.guardiansRegistration.registerGuardian(
        v.ip,
        v2.orbsAddress,
        v2.name,
        v2.website,
        {from: v2.address}), /ip is already in use/);
  });

  it('does not allow a registered guardian to set an IP of an existing guardian', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website
        , {from: v.address});

    const v2 = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v2.ip,
        v2.orbsAddress,
        v2.name,
        v2.website
        , {from: v2.address});

    await expectRejected(d.guardiansRegistration.updateGuardian(
        v.ip,
        v2.orbsAddress,
        v2.name,
        v2.website,
        {from: v2.address}), /ip is already in use/);
  });

  it('allows registering with an IP of a previously existing guardian that unregistered', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website
        , {from: v.address});

    await d.guardiansRegistration.unregisterGuardian({from: v.address});

    const v2 = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v.ip,
        v2.orbsAddress,
        v2.name,
        v2.website
        , {from: v2.address});
  });

  it('allows a registered guardian to set an IP of a previously existing guardian that unregistered', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website
        , {from: v.address});

    const v2 = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v2.ip,
        v2.orbsAddress,
        v2.name,
        v2.website
        , {from: v2.address});

    await d.guardiansRegistration.unregisterGuardian({from: v.address});

    await d.guardiansRegistration.updateGuardian(
        v.ip,
        v2.orbsAddress,
        v2.name,
        v2.website
    , {from: v2.address});

  });

  it('does not allow registering using an orbs address of an existing guardian', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website
        , {from: v.address});

    const v2 = d.newParticipant();

    await expectRejected(d.guardiansRegistration.registerGuardian(
        v2.ip,
        v.orbsAddress,
        v2.name,
        v2.website,
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
         {from: v.address});

    const v2 = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v2.ip,
        v2.orbsAddress,
        v2.name,
        v2.website,
         {from: v2.address});

    await expectRejected(d.guardiansRegistration.updateGuardian(
        v2.ip,
        v.orbsAddress,
        v2.name,
        v2.website,
        {from: v2.address}), /orbs address is already in use/);
  });

  it('does not allow registering or updating to an orbs address equal to the guardian address', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    await expectRejected(d.guardiansRegistration.registerGuardian(
        v.ip,
        v.address,
        v.name,
        v.website,
         {from: v.address}), /orbs address must be different than the guardian address/);

    await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
         {from: v.address});

    await expectRejected(d.guardiansRegistration.updateGuardian(
        v.ip,
        v.address,
        v.name,
        v.website,
        {from: v.address}), /orbs address must be different than the guardian address/);
  });

  it('allows registering with an orbs address of a previously existing guardian that unregistered', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
        {from: v.address});

    await d.guardiansRegistration.unregisterGuardian({from: v.address});

    const v2 = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v2.ip,
        v.orbsAddress,
        v2.name,
        v2.website,
         {from: v2.address});
  });

  it('allows a registered guardian to set an orbs address of a previously existing guardian that unregistered', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website,
        {from: v.address});

    const v2 = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v2.ip,
        v2.orbsAddress,
        v2.name,
        v2.website
        , {from: v2.address});

    await d.guardiansRegistration.unregisterGuardian({from: v.address});

    await d.guardiansRegistration.updateGuardian(
        v2.ip,
        v.orbsAddress,
        v2.name,
        v2.website
    , {from: v2.address});

  });

  it('does not allow an unregistered guardian to update', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    await expectRejected(d.guardiansRegistration.updateGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website
    , {from: v.address}), /not registered/);

  });

  it('allows a registered guardian to update without changing any detail', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website
        , {from: v.address});

    await d.guardiansRegistration.updateGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website
    , {from: v.address});

  });

  it('does not allow a registered guardian to update using its Orbs address', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website
        , {from: v.address});

    await expectRejected(d.guardiansRegistration.updateGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website
    , {from: v.orbsAddress}), /not registered/);
  });

  it('allows a registered guardian to update IP from both its orbs address and main address', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website
        , {from: v.address});

    let r = await d.guardiansRegistration.updateGuardianIp(
        "0xaaaaaaaa"
    , {from: v.orbsAddress});
    expect(r).to.have.a.guardianDataUpdatedEvent({
      guardian: v.address,
      isRegistered: true,
      ip: "0xaaaaaaaa"
    });

    r = await d.guardiansRegistration.updateGuardianIp(
        "0xbbbbbbbb"
    , {from: v.address});
    expect(r).to.have.a.guardianDataUpdatedEvent({
      guardian: v.address,
      isRegistered: true,
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
        v.website
        , {from: v.address});
    expect(r).to.have.a.guardianRegisteredEvent({
      guardian: v.address
    });
    expect(r).to.have.a.guardianDataUpdatedEvent({
      guardian: v.address,
      isRegistered: true,
      ip: v.ip,
      orbsAddr: v.orbsAddress,
      name: v.name,
      website: v.website
    });
    const key = 'key_' + Date.now().toString();

    // set
    const value = 'value_' + Date.now().toString();

    r = await d.guardiansRegistration.setMetadata(key, value, {from: v.address});
    expect(r).to.have.a.guardianMetadataChangedEvent({
      guardian: v.address,
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
      guardian: v.address,
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
      guardian: v.address,
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
        v.website
        , {from: v.address});
    expect(r).to.have.a.guardianRegisteredEvent({
      guardian: v.address
    });
    expect(r).to.have.a.guardianDataUpdatedEvent({
      guardian: v.address,
      isRegistered: true,
      ip: v.ip,
      orbsAddr: v.orbsAddress,
      name: v.name,
      website: v.website
    });

    expect(await d.guardiansRegistration.getGuardiansOrbsAddress([v.address])).to.deep.equal([v.orbsAddress])
  });

  it('converts orbs addrs to eth addrs', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();
    let r = await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website
        , {from: v.address});
    expect(r).to.have.a.guardianRegisteredEvent({
      guardian: v.address
    });
    expect(r).to.have.a.guardianDataUpdatedEvent({
      guardian: v.address,
      isRegistered: true,
      ip: v.ip,
      orbsAddr: v.orbsAddress,
      name: v.name,
      website: v.website
    });

    expect(await d.guardiansRegistration.getGuardiansOrbsAddress([v.address])).to.deep.equal([v.orbsAddress])
  });

  it('resolves ethereum address', async () => {
    const d = await Driver.new();

    const v = d.newParticipant();
    const v2 = d.newParticipant();

    await d.guardiansRegistration.registerGuardian(
        v2.ip,
        v.address,
        v2.name,
        v2.website,
        {from: v2.address});
    expect(await d.guardiansRegistration.resolveGuardianAddress(v2.address)).to.deep.equal(v2.address);
    expect(await d.guardiansRegistration.resolveGuardianAddress(v.address)).to.deep.equal(v2.address);

    await d.guardiansRegistration.registerGuardian(
        v.ip,
        v.orbsAddress,
        v.name,
        v.website
        , {from: v.address});

    expect(await d.guardiansRegistration.resolveGuardianAddress(v.address)).to.deep.equal(v.address);
    expect(await d.guardiansRegistration.resolveGuardianAddress(v.orbsAddress)).to.deep.equal(v.address);
    expect(await d.guardiansRegistration.resolveGuardianAddress(v2.address)).to.deep.equal(v2.address);
  });

  it('is able to migrate registered guardians from a previous contract', async () => {
    const d = await Driver.new();

    const v1 = d.newParticipant();
    let r = await v1.registerAsGuardian();
    const v1RegistrationTime = await d.web3.txTimestamp(r);
    await d.guardiansRegistration.setMetadata("ID_FORM_URL", "123", {from: v1.address});

    const v2 = d.newParticipant();
    r = await v2.registerAsGuardian();
    const v2RegistrationTime = await d.web3.txTimestamp(r);

    await evmIncreaseTime(d.web3, 5);

    v1.ip = "0x12121212";
    r = await d.guardiansRegistration.updateGuardianIp(v1.ip, {from: v1.address});
    const v1LastUpdateTime = await d.web3.txTimestamp(r);
    const v2LastUpdateTime = v2RegistrationTime;

    const newContract: GuardiansRegistrationContract = await d.web3.deploy('GuardiansRegistration', [d.contractRegistry.address, d.registryAdmin.address], null, d.session);

    r = await newContract.migrateGuardians([v1.address, v2.address], d.guardiansRegistration.address);
    expect(r).to.have.a.guardianDataUpdatedEvent({
      guardian: v1.address,
      orbsAddr: v1.orbsAddress,
      name: v1.name,
      website: v1.website,
      isRegistered: true,
      registrationTime: bn(v1RegistrationTime)
    });
    expect(r).to.have.a.guardianMetadataChangedEvent({key: "ID_FORM_URL", newValue: "123", oldValue: ""});
    expect(r).to.have.a.guardianDataUpdatedEvent({
      guardian: v2.address,
      orbsAddr: v2.orbsAddress,
      name: v2.name,
      website: v2.website,
      isRegistered: true,
      registrationTime: bn(v2RegistrationTime)
    });

    d.guardiansRegistration = null as any;

    const v1Data = await newContract.getGuardianData(v1.address);

    expect(v1Data.ip.toString()).to.eq(v1.ip);
    expect(v1Data.orbsAddr.toString()).to.eq(v1.orbsAddress);
    expect(v1Data.name.toString()).to.eq(v1.name);
    expect(v1Data.website.toString()).to.eq(v1.website);
    expect(v1Data.registrationTime.toString()).to.eq(v1RegistrationTime.toString());
    expect(v1Data.lastUpdateTime.toString()).to.eq(v1LastUpdateTime.toString());
    expect(await newContract.getMetadata(v1.address, "ID_FORM_URL")).to.eq("123");

    const v2Data = await newContract.getGuardianData(v2.address);

    expect(v2Data.ip.toString()).to.eq(v2.ip);
    expect(v2Data.orbsAddr.toString()).to.eq(v2.orbsAddress);
    expect(v2Data.name.toString()).to.eq(v2.name);
    expect(v2Data.website.toString()).to.eq(v2.website);
    expect(v2Data.registrationTime.toString()).to.eq(v2RegistrationTime.toString());
    expect(v2Data.lastUpdateTime.toString()).to.eq(v2LastUpdateTime.toString());

    expect(await newContract.resolveGuardianAddress(v1.orbsAddress)).to.eq(v1.address);
    await expectRejected(newContract.updateGuardianIp(v1.ip, {from: v2.address}), /ip is already in use/);
    await expectRejected(newContract.updateGuardian(v2.ip, v1.orbsAddress, v2.name, v2.website, {from: v2.address}), /orbs address is already in use/);
  });

});
