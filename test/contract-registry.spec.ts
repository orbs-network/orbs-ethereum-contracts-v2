import 'mocha';

import BN from "bn.js";
import {Driver, ZERO_ADDR} from "./driver";
import chai from "chai";
import {bn, contractId, expectRejected} from "./helpers";
import {ContractRegistryContract} from "../typings/contract-registry-contract";

chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const expect = chai.expect;

describe('contract-registry-high-level-flows', async () => {

  it('registers contracts only by registry manager and emits events', async () => {
    const d = await Driver.new();
    const owner = d.registryManager;
    const registry = d.contractRegistry;

    const contract1Name = "protocol";
    const addr1 = d.newParticipant().address;

    // set
    let r = await registry.setContract(contract1Name, addr1, false, {from: owner.address});
    expect(r).to.have.a.contractAddressUpdatedEvent({
      contractName: contract1Name,
      addr: addr1,
      managedContract: false
    });

    // get
    expect(await registry.getContract(contract1Name)).to.equal(addr1);

    // update
    const addr2 = d.newParticipant().address;
    r = await registry.setContract(contract1Name, addr2, false, {from: owner.address});
    expect(r).to.have.a.contractAddressUpdatedEvent({
      contractName: contract1Name,
      addr: addr2,
      managedContract: false
    });

    // get the updated address
    expect(await registry.getContract(contract1Name)).to.equal(addr2);

    // set another by non governor
    const nonGovernor = d.newParticipant();
    const contract2Name = "committee";
    const addr3 = d.newParticipant().address;
    await expectRejected(registry.setContract(contract2Name, addr3, false, {from: nonGovernor.address}), /sender is not an admin/);

    // now by governor
    r = await registry.setContract(contract2Name, addr3, false, {from: owner.address});
    expect(r).to.have.a.contractAddressUpdatedEvent({
      contractName: contract2Name,
      addr: addr3,
      managedContract: false
    });
    expect(await registry.getContract(contract2Name)).to.equal(addr3);

  });

  it('allows only the registry manager to update the address of the contract registry', async () => { // TODO - consider splitting and moving this
    const d = await Driver.new();
    const subscriber = await d.newSubscriber("tier", 1);

    const newAddr = d.newParticipant().address;
    await expectRejected(d.elections.setContractRegistry(newAddr, {from: d.functionalManager.address}), /sender is not an admin/);
    await expectRejected(d.rewards.setContractRegistry(newAddr, {from: d.functionalManager.address}), /sender is not an admin/);
    await expectRejected(d.subscriptions.setContractRegistry(newAddr, {from: d.functionalManager.address}), /sender is not an admin/);
    await expectRejected(subscriber.setContractRegistry(newAddr, {from: d.functionalManager.address}), /sender is not an admin/);

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
    await expectRejected(d.contractRegistry.setManager("newRole", p.address, {from: nonOwner.address}), /sender is not an admin/);

    let r = await d.contractRegistry.setManager("newRole", p.address, {from: d.registryManager.address});
    expect(r).to.have.a.managerChangedEvent({
      role: "newRole",
      newManager: p.address
    });
  });

  it('sets and unsets contracts, notifies only managed', async () => {
    const d = await Driver.new()

    const registry = await d.web3.deploy('ContractRegistry' as any, [d.registryManager.address]);
    const contract = () => d.web3.deploy('ManagedContractTest' as any, [registry.address, d.registryManager.address]);

    const c1 = await contract();
    expect(await c1.refreshContractsCount()).to.bignumber.eq(bn(0));

    await registry.setContract("c1", c1.address, true, {from: d.registryManager.address});
    expect(await c1.refreshContractsCount()).to.bignumber.eq(bn(1));

    const c2 = await contract();
    expect(await c2.refreshContractsCount()).to.bignumber.eq(bn(0));

    await registry.setContract("c2", c2.address, false, {from: d.registryManager.address});
    expect(await c1.refreshContractsCount()).to.bignumber.eq(bn(2));
    expect(await c2.refreshContractsCount()).to.bignumber.eq(bn(0));

    await registry.setContract("c2", ZERO_ADDR, false, {from: d.registryManager.address});
    expect(await c1.refreshContractsCount()).to.bignumber.eq(bn(3));
    expect(await c2.refreshContractsCount()).to.bignumber.eq(bn(0));
  });

  it('sets and unsets roles', async () => {
    const d = await Driver.new()

    const m1 = d.newParticipant().address;
    let r = await d.contractRegistry.setManager("role1", m1, {from: d.registryManager.address});
    expect(r).to.have.a.managerChangedEvent({
        role: "role1",
        newManager: m1
    });
    expect(await d.contractRegistry.getManager("role1")).to.eq(m1);

    r = await d.contractRegistry.setManager("role1", ZERO_ADDR, {from: d.registryManager.address});
    expect(r).to.have.a.managerChangedEvent({
      role: "role1",
      newManager: ZERO_ADDR
    });
    expect(await d.contractRegistry.getManager("role1")).to.eq(ZERO_ADDR);

    const m2 = d.newParticipant().address;
    r = await d.contractRegistry.setManager("role2", m2, {from: d.registryManager.address});
    expect(r).to.have.a.managerChangedEvent({
      role: "role2",
      newManager: m2
    });
    expect(await d.contractRegistry.getManager("role2")).to.eq(m2);

  });

  it('locks and unlocks all managed contracts, only by registryManager', async () => {
    const d = await Driver.new();

    const managedContracts = await d.contractRegistry.getManagedContracts();

    await expectRejected(d.contractRegistry.lockContracts({from: d.migrationManager.address}), /sender is not an admin/);
    await d.contractRegistry.lockContracts({from: d.registryManager.address});
    for (const contractAddr of managedContracts) {
      const contract = d.web3.getExisting("Lockable" as any, contractAddr);
      expect(await contract.isLocked()).to.be.true;
    }

    await expectRejected(d.contractRegistry.unlockContracts({from: d.migrationManager.address}), /sender is not an admin/);
    await d.contractRegistry.unlockContracts({from: d.registryManager.address});
    for (const contractAddr of managedContracts) {
      const contract = d.web3.getExisting("Lockable" as any, contractAddr);
      expect(await contract.isLocked()).to.be.false;
    }
  });

  it('allows the initialization manager to setContract,setRole,lock,unlock until initialization complete', async () => {
    const d = await Driver.new();

    const registry: ContractRegistryContract = await d.web3.deploy('ContractRegistry', [d.registryManager.address], {from: d.initializationManager.address});
    const managed =  await d.web3.deploy('ManagedContractTest' as any, [registry.address, d.registryManager.address]);

    const manager = d.newParticipant().address;

    let r = await registry.setContract('name', managed.address, true, {from: d.initializationManager.address});
    expect(r).to.have.a.contractAddressUpdatedEvent();
    r = await registry.setManager('role', manager, {from: d.initializationManager.address});
    expect(r).to.have.a.managerChangedEvent();
    r = await registry.lockContracts({from: d.initializationManager.address});
    expect(r).to.have.a.lockedEvent();
    r = await registry.unlockContracts({from: d.initializationManager.address});
    expect(r).to.have.a.unlockedEvent();

    r = await registry.setContract('name', managed.address, true, {from: d.registryManager.address});
    expect(r).to.have.a.contractAddressUpdatedEvent();
    r = await registry.setManager('role', manager, {from: d.registryManager.address});
    expect(r).to.have.a.managerChangedEvent();
    r = await registry.lockContracts({from: d.registryManager.address});
    expect(r).to.have.a.lockedEvent();
    r = await registry.unlockContracts({from: d.registryManager.address});
    expect(r).to.have.a.unlockedEvent();

    await registry.initializationComplete();

    await expectRejected(registry.setContract('name', managed.address, true, {from: d.initializationManager.address}), /sender is not an admin/);
    await expectRejected(registry.setManager('role', manager, {from: d.initializationManager.address}), /sender is not an admin/);
    await expectRejected(registry.lockContracts({from: d.initializationManager.address}), /sender is not an admin/);
    await expectRejected(registry.unlockContracts({from: d.initializationManager.address}), /sender is not an admin/);

    r = await registry.setContract('name', managed.address, true, {from: d.registryManager.address});
    expect(r).to.have.a.contractAddressUpdatedEvent();
    r = await registry.setManager('role', manager, {from: d.registryManager.address});
    expect(r).to.have.a.managerChangedEvent();
    r = await registry.lockContracts({from: d.registryManager.address});
    expect(r).to.have.a.lockedEvent();
    r = await registry.unlockContracts({from: d.registryManager.address});
    expect(r).to.have.a.unlockedEvent();
  });

});
