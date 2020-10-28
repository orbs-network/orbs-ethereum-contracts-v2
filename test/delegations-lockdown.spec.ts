import 'mocha';


import BN from "bn.js";
import {Driver} from "./driver";
import chai from "chai";
import {expectRejected} from "./helpers";
import {chaiEventMatchersPlugin} from "./matchers";

chai.use(require('chai-bn')(BN));
chai.use(chaiEventMatchersPlugin);

const expect = chai.expect;

describe('delegations-contract-lockdown', async () => {

  // functional owner

  it('allows only the migration manager to lock and unlock the contract', async () => {
    const d = await Driver.new();

    const contractRegistry = await d.web3.deploy('ContractRegistry', [d.contractRegistry.address, d.registryAdmin.address]);
    await d.protocol.setContractRegistry(contractRegistry.address, {from: d.registryAdmin.address});

    await expectRejected(d.protocol.lock({from: d.functionalManager.address}), /sender is not the migration manager/);
    let r = await d.delegations.lock({from: d.registryAdmin.address});
    expect(r).to.have.a.lockedEvent();
    r = await d.delegations.unlock({from: d.registryAdmin.address});
    expect(r).to.have.a.unlockedEvent();

    r = await d.delegations.lock({from: d.migrationManager.address});
    expect(r).to.have.a.lockedEvent();
    r = await d.delegations.unlock({from: d.migrationManager.address});
    expect(r).to.have.a.unlockedEvent();
  });

  it('rejects calls to delegate when locked', async () => {
    const d = await Driver.new();

    await d.delegations.lock({from: d.registryAdmin.address});

    const p = d.newParticipant();
    await expectRejected(d.delegations.delegate(p.address, {from: p.address}), /contract is locked for this operation/);

    await d.delegations.unlock({from: d.registryAdmin.address});

    await d.delegations.delegate(p.address, {from: p.address})
  });

});
