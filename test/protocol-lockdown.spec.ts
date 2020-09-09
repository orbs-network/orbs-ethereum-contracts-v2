import 'mocha';


import BN from "bn.js";
import {Driver, DEPLOYMENT_SUBSET_MAIN, DEPLOYMENT_SUBSET_CANARY} from "./driver";
import chai from "chai";
import {bn, evmIncreaseTimeForQueries, expectRejected, getTopBlockTimestamp} from "./helpers";
import {chaiEventMatchersPlugin} from "./matchers";

chai.use(require('chai-bn')(BN));
chai.use(chaiEventMatchersPlugin);

const expect = chai.expect;

describe('protocol-contract-lockdown', async () => {

  // functional owner

  it('allows the registry manager to lock and unlock the contract', async () => {
    const d = await Driver.new();

    const contractRegistry = await d.web3.deploy('ContractRegistry', [d.contractRegistry.address, d.registryAdmin.address]);
    await d.protocol.setContractRegistry(contractRegistry.address, {from: d.registryAdmin.address});

    await expectRejected(d.protocol.lock({from: d.functionalManager.address}), /caller is not a lock owner/);
    let r = await d.protocol.lock({from: d.registryAdmin.address});
    expect(r).to.have.a.lockedEvent();
    r = await d.protocol.unlock({from: d.registryAdmin.address});
    expect(r).to.have.a.unlockedEvent();
  });

  it('rejects calls to createNewDeploymentSubset and setProtocolVersion when locked', async () => {
    const d = await Driver.new();

    await d.protocol.lock({from: d.registryAdmin.address});

    let currTime: number = await getTopBlockTimestamp(d);
    await expectRejected(d.protocol.createDeploymentSubset("newdeploymentsubset", 1, {from: d.functionalManager.address}), /contract is locked for this operation/);
    await expectRejected(d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 2, currTime + 100, {from: d.functionalManager.address}), /contract is locked for this operation/);

    await d.protocol.unlock({from: d.registryAdmin.address});

    currTime = await getTopBlockTimestamp(d);
    await d.protocol.createDeploymentSubset("newdeploymentsubset", 1, {from: d.functionalManager.address});
    await d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 2, currTime + 100, {from: d.functionalManager.address});

  });

});
