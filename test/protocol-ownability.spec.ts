import 'mocha';


import BN from "bn.js";
import {Driver, DEPLOYMENT_SUBSET_MAIN, DEPLOYMENT_SUBSET_CANARY} from "./driver";
import chai from "chai";
import {bn, evmIncreaseTimeForQueries, expectRejected, getTopBlockTimestamp} from "./helpers";
import {chaiEventMatchersPlugin} from "./matchers";

chai.use(require('chai-bn')(BN));
chai.use(chaiEventMatchersPlugin);

const expect = chai.expect;

describe('protocol-contract', async () => {

  // functional owner

  it('allows only the functional owner to set protocol version', async () => {
    const d = await Driver.new();

    let currTime: number = await getTopBlockTimestamp(d);
    await expectRejected(d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 2, currTime + 100, {from: d.migrationManager.address}), /sender is not the functional manager/);
    await d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 2, currTime + 100, {from: d.functionalManager.address});
  });

  // registry manager

  it('allows only the registry manager to set contract registry', async () => {
    const d = await Driver.new();

    const newRegistry = await d.web3.deploy('ContractRegistry', [d.contractRegistry.address, d.registryAdmin.address]);

    await expectRejected(d.protocol.setContractRegistry(newRegistry.address, {from: d.functionalManager.address}), /sender is not an admin/);
    await d.protocol.setContractRegistry(newRegistry.address, {from: d.registryAdmin.address});
  });

  it('only current registry manager can transfer registry ownership', async () => {
    const d = await Driver.new();

    const newOwner = d.newParticipant();
    await expectRejected(d.protocol.transferRegistryManagement(newOwner.address, {from: d.functionalManager.address}), /caller is not the registryAdmin/);
    await d.protocol.transferRegistryManagement(newOwner.address, {from: d.registryAdmin.address});

  });

  it('does not transfer registry ownership until claimed by new owner', async () => {
    const d = await Driver.new();

    const newManager = d.newParticipant();
    await d.protocol.transferRegistryManagement(newManager.address, {from: d.registryAdmin.address});

    const newRegistry = await d.web3.deploy('ContractRegistry', [d.contractRegistry.address, d.registryAdmin.address]);
    await expectRejected(d.protocol.setContractRegistry(newRegistry.address, {from: newManager.address}), /sender is not an admin/);
    await d.protocol.setContractRegistry(newRegistry.address, {from: d.registryAdmin.address});

    const notNewOwner = d.newParticipant();
    await expectRejected(d.protocol.claimRegistryManagement({from: notNewOwner.address}), /Caller is not the pending registryAdmin/);

    await d.protocol.claimRegistryManagement({from: newManager.address});

    const newRegistry2 = await d.web3.deploy('ContractRegistry', [newRegistry.address, d.registryAdmin.address]);
    await expectRejected(d.protocol.setContractRegistry(newRegistry2.address, {from: d.registryAdmin.address}), /sender is not an admin/);
    await d.protocol.setContractRegistry(newRegistry2.address, {from: newManager.address});
  });


});
