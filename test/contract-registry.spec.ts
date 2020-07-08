import 'mocha';

import BN from "bn.js";
import {Driver, expectRejected, ZERO_ADDR} from "./driver";
import chai from "chai";

chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const expect = chai.expect;

describe('contract-registry-high-level-flows', async () => {

  it('registers contracts only by functional owner and emits events', async () => {
    const d = await Driver.new();
    const owner = d.functionalOwner;
    const registry = d.contractRegistry;

    const contract1Name = "protocol";
    const addr1 = d.newParticipant().address;

    // set
    let r = await registry.set(contract1Name, addr1, {from: owner.address});
    expect(r).to.have.a.contractAddressUpdatedEvent({
      contractName: contract1Name,
      addr: addr1
    });

    // get
    expect(await registry.get(contract1Name)).to.equal(addr1);

    // update
    const addr2 = d.newParticipant().address;
    r = await registry.set(contract1Name, addr2, {from: owner.address});
    expect(r).to.have.a.contractAddressUpdatedEvent({
      contractName: contract1Name,
      addr: addr2
    });

    // get the updated address
    expect(await registry.get(contract1Name)).to.equal(addr2);

    // set another by non governor
    const nonGovernor = d.newParticipant();
    const contract2Name = "committee";
    const addr3 = d.newParticipant().address;
    await expectRejected(registry.set(contract2Name, addr3, {from: nonGovernor.address}));

    // now by governor
    r = await registry.set(contract2Name, addr3, {from: owner.address});
    expect(r).to.have.a.contractAddressUpdatedEvent({
      contractName: contract2Name,
      addr: addr3
    });
    expect(await registry.get(contract2Name)).to.equal(addr3);

  });

  it('reverts when getting a non existent entry', async () => {
    const d = await Driver.new();
    await expectRejected(d.contractRegistry.get("nonexistent" as any));
  });

  it('allows only the contract owner to update the address of the contract registry', async () => { // TODO - consider splitting and moving this
    const d = await Driver.new();
    const subscriber = await d.newSubscriber("tier", 1);

    const newAddr = d.newParticipant().address;
    await expectRejected(d.elections.setContractRegistry(newAddr, {from: d.functionalOwner.address}));
    await expectRejected(d.rewards.setContractRegistry(newAddr, {from: d.functionalOwner.address}));
    await expectRejected(d.subscriptions.setContractRegistry(newAddr, {from: d.functionalOwner.address}));
    await expectRejected(subscriber.setContractRegistry(newAddr, {from: d.functionalOwner.address}));

    let r = await d.elections.setContractRegistry(newAddr, {from: d.migrationOwner.address});
    expect(r).to.have.a.contractRegistryAddressUpdatedEvent({addr: newAddr});
    r = await d.rewards.setContractRegistry(newAddr, {from: d.migrationOwner.address});
    expect(r).to.have.a.contractRegistryAddressUpdatedEvent({addr: newAddr});
    r = await d.subscriptions.setContractRegistry(newAddr, {from: d.migrationOwner.address});
    expect(r).to.have.a.contractRegistryAddressUpdatedEvent({addr: newAddr});
    r = await subscriber.setContractRegistry(newAddr, {from: d.migrationOwner.address});
    expect(r).to.have.a.contractRegistryAddressUpdatedEvent({addr: newAddr});
  });

});
