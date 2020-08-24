import 'mocha';


import BN from "bn.js";
import {Driver, DEPLOYMENT_SUBSET_MAIN, DEPLOYMENT_SUBSET_CANARY} from "./driver";
import chai from "chai";

chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const expect = chai.expect;

import {bn, evmIncreaseTimeForQueries, expectRejected, getTopBlockTimestamp} from "./helpers";

describe('protocol-contract-lockdown', async () => {

  // functional owner

  it('allows only the migration owner and the contract registry to lock and unlock the contract', async () => {
    const d = await Driver.new();

    const contractRegistry = d.newParticipant();
    await d.protocol.setContractRegistry(contractRegistry.address, {from: d.registryManager.address});

    await expectRejected(d.protocol.lock({from: d.functionalManager.address}), /caller is not a lock owner/);
    let r = await d.protocol.lock({from: d.registryManager.address});
    expect(r).to.have.a.lockedEvent();
    r = await d.protocol.unlock({from: d.registryManager.address});
    expect(r).to.have.a.unlockedEvent();

    await d.protocol.lock({from: d.registryManager.address});

    await expectRejected(d.protocol.unlock({from: d.functionalManager.address}), /caller is not a lock owner/);
    r = await d.protocol.unlock({from: contractRegistry.address});
    expect(r).to.have.a.unlockedEvent();
    r = await d.protocol.lock({from: contractRegistry.address});
    expect(r).to.have.a.lockedEvent();
  });

  it('rejects calls to createNewDeploymentSubset and setProtocolVersion when locked', async () => {
    const d = await Driver.new();

    await d.protocol.lock({from: d.registryManager.address});

    let currTime: number = await getTopBlockTimestamp(d);
    await expectRejected(d.protocol.createDeploymentSubset("newdeploymentsubset", 1, {from: d.functionalManager.address}), /contract is locked for this operation/);
    await expectRejected(d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 2, currTime + 100, {from: d.functionalManager.address}), /contract is locked for this operation/);

    await d.protocol.unlock({from: d.registryManager.address});

    currTime = await getTopBlockTimestamp(d);
    await d.protocol.createDeploymentSubset("newdeploymentsubset", 1, {from: d.functionalManager.address});
    await d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 2, currTime + 100, {from: d.functionalManager.address});

  });

});
