import 'mocha';

import BN from "bn.js";
import {Driver, ZERO_ADDR} from "./driver";
import chai from "chai";
import {bn, contractId, expectRejected} from "./helpers";

chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const expect = chai.expect;

describe('contract-registry-high-level-flows', async () => {

  it('registers contracts only by functional owner and emits events', async () => {
    const d = await Driver.new();
    const owner = d.registryManager;
    const registry = d.contractRegistry;

    const contract1Name = "protocol";
    const addr1 = d.newParticipant().address;

    // set
    let r = await registry.setContracts([contractId(contract1Name)], [addr1], [false], {from: owner.address});
    expect(r).to.have.a.contractAddressUpdatedEvent({
      contractId: contractId(contract1Name),
      addr: addr1
    });

    // get
    expect((await registry.getContracts([contractId(contract1Name)]))[0]).to.equal(addr1);

    // update
    const addr2 = d.newParticipant().address;
    r = await registry.setContracts([contractId(contract1Name)], [addr2], [false], {from: owner.address});
    expect(r).to.have.a.contractAddressUpdatedEvent({
      contractId: contractId(contract1Name),
      addr: addr2
    });

    // get the updated address
    expect((await registry.getContracts([contractId(contract1Name)]))[0]).to.equal(addr2);

    // set another by non governor
    const nonGovernor = d.newParticipant();
    const contract2Name = "committee";
    const addr3 = d.newParticipant().address;
    await expectRejected(registry.setContracts([contractId(contract2Name)], [addr3], [false], {from: nonGovernor.address}), /caller is not the registryManager/);

    // now by governor
    r = await registry.setContracts([contractId(contract2Name)], [addr3], [false], {from: owner.address});
    expect(r).to.have.a.contractAddressUpdatedEvent({
      contractId: contractId(contract2Name),
      addr: addr3
    });
    expect((await registry.getContracts([contractId(contract2Name)]))[0]).to.equal(addr3);

  });

  it('reverts when getting a non existent entry', async () => {
    const d = await Driver.new();
    await expectRejected(d.contractRegistry.getContracts([contractId("nonexistent") as any]), /the contract id is not registered/);
  });

  it('allows only the registry manager to update the address of the contract registry', async () => { // TODO - consider splitting and moving this
    const d = await Driver.new();
    const subscriber = await d.newSubscriber("tier", 1);

    const newAddr = d.newParticipant().address;
    await expectRejected(d.elections.setContractRegistry(newAddr, {from: d.functionalManager.address}), /caller is not the registryManager/);
    await expectRejected(d.rewards.setContractRegistry(newAddr, {from: d.functionalManager.address}), /caller is not the registryManager/);
    await expectRejected(d.subscriptions.setContractRegistry(newAddr, {from: d.functionalManager.address}), /caller is not the registryManager/);
    await expectRejected(subscriber.setContractRegistry(newAddr, {from: d.functionalManager.address}), /caller is not the registryManager/);

    let r = await d.elections.setContractRegistry(newAddr, {from: d.registryManager.address});
    expect(r).to.have.a.contractRegistryAddressUpdatedEvent({addr: newAddr});
    r = await d.rewards.setContractRegistry(newAddr, {from: d.registryManager.address});
    expect(r).to.have.a.contractRegistryAddressUpdatedEvent({addr: newAddr});
    r = await d.subscriptions.setContractRegistry(newAddr, {from: d.registryManager.address});
    expect(r).to.have.a.contractRegistryAddressUpdatedEvent({addr: newAddr});
    r = await subscriber.setContractRegistry(newAddr, {from: d.registryManager.address});
    expect(r).to.have.a.contractRegistryAddressUpdatedEvent({addr: newAddr});
  });

  it('sets a manager only by registry manager', async () => {
    const d = await Driver.new();

    const p = d.newParticipant();

    const nonOwner = d.newParticipant();
    await expectRejected(d.contractRegistry.setManager("newRole", p.address, {from: nonOwner.address}), /caller is not the registryManager/);

    let r = await d.contractRegistry.setManager("newRole", p.address, {from: d.registryManager.address});
    expect(r).to.have.a.managerChangedEvent({
      role: "newRole",
      newManager: p.address
    });
  });

  it('sets and unsets contracts, notifies only managed', async () => {
    const d = await Driver.new()

    const registry = await d.web3.deploy('ContractRegistry' as any, []);
    const contract = () => d.web3.deploy('ManagedContract' as any, [registry.address, d.registryManager.address]);

    const c1 = await contract();
    expect(await c1.refreshContractsCount()).to.bignumber.eq(bn(0));

    await registry.setContracts([contractId("c1")], [c1.address], [true]);
    expect(await c1.refreshContractsCount()).to.bignumber.eq(bn(1));

    const c2 = await contract();
    expect(await c2.refreshContractsCount()).to.bignumber.eq(bn(0));

    const c3 = await contract();
    expect(await c3.refreshContractsCount()).to.bignumber.eq(bn(0));

    await registry.setContracts([contractId("c2"), contractId("c3")], [c2.address, c3.address], [true, false]);
    expect(await c1.refreshContractsCount()).to.bignumber.eq(bn(2));
    expect(await c2.refreshContractsCount()).to.bignumber.eq(bn(1));
    expect(await c3.refreshContractsCount()).to.bignumber.eq(bn(0));

    await registry.setContracts([contractId("c2")], [ZERO_ADDR], [false]);
    expect(await c1.refreshContractsCount()).to.bignumber.eq(bn(3));
    expect(await c2.refreshContractsCount()).to.bignumber.eq(bn(1));
    expect(await c3.refreshContractsCount()).to.bignumber.eq(bn(0));
  });

  it('sets and unsets roles, notifies only managed', async () => {
    const d = await Driver.new()

    const registry = await d.web3.deploy('ContractRegistry' as any, []);
    const contract = () => d.web3.deploy('ManagedContract' as any, [registry.address, d.registryManager.address]);

    const c1 = await contract();
    expect(await c1.refreshManagersCount()).to.bignumber.eq(bn(0));

    await registry.setContracts([contractId("c1")], [c1.address], [true]);
    expect(await c1.refreshManagersCount()).to.bignumber.eq(bn(0));

    const m1 = d.newParticipant().address;
    await registry.setManager("role1", m1);
    expect(await c1.refreshManagersCount()).to.bignumber.eq(bn(1));

    const c2 = await contract();
    expect(await c2.refreshManagersCount()).to.bignumber.eq(bn(0));

    const c3 = await contract();
    expect(await c3.refreshManagersCount()).to.bignumber.eq(bn(0));

    await registry.setContracts([contractId("c2"), contractId("c3")], [c2.address, c3.address], [true, false]);
    expect(await c1.refreshManagersCount()).to.bignumber.eq(bn(1));
    expect(await c1.notifiedRole(1)).to.eq("role1");
    expect(await c1.notifiedManager(1)).to.eq(m1);
    expect(await c2.refreshManagersCount()).to.bignumber.eq(bn(0));
    expect(await c3.refreshManagersCount()).to.bignumber.eq(bn(0));

    await registry.setManager("role1", ZERO_ADDR);
    expect(await c1.refreshManagersCount()).to.bignumber.eq(bn(2));
    expect(await c1.notifiedRole(2)).to.eq("role1");
    expect(await c1.notifiedManager(2)).to.eq(ZERO_ADDR);
    expect(await c2.refreshManagersCount()).to.bignumber.eq(bn(1));
    expect(await c2.notifiedRole(1)).to.eq("role1");
    expect(await c2.notifiedManager(1)).to.eq(ZERO_ADDR);
    expect(await c3.refreshManagersCount()).to.bignumber.eq(bn(0));

    await registry.setContracts([contractId("c2")], [ZERO_ADDR], [false]);
    const m2 = d.newParticipant().address;
    await registry.setManager("role2", m2);
    expect(await c1.refreshManagersCount()).to.bignumber.eq(bn(3));
    expect(await c1.notifiedRole(3)).to.eq("role2");
    expect(await c1.notifiedManager(3)).to.eq(m2);
    expect(await c2.refreshManagersCount()).to.bignumber.eq(bn(1));
    expect(await c3.refreshManagersCount()).to.bignumber.eq(bn(0));
  });

});
