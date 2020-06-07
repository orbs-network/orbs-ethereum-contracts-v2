import 'mocha';


import BN from "bn.js";
import {Driver, DEPLOYMENT_SUBSET_MAIN, DEPLOYMENT_SUBSET_CANARY, expectRejected} from "./driver";
import chai from "chai";

chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const expect = chai.expect;

import {bn, evmIncreaseTimeForQueries, getTopBlockTimestamp} from "./helpers";

describe.only('protocol-contract', async () => {

  // functional owner

  it('allows only the migration owner to lock and unlock the contract', async () => {
    const d = await Driver.new();

    await expectRejected(d.protocol.lock({from: d.functionalOwner.address}));
    await d.protocol.lock({from: d.migrationOwner.address});
    await expectRejected(d.protocol.unlock({from: d.functionalOwner.address}));
    await d.protocol.unlock({from: d.migrationOwner.address});
  });

  it('rejects calls to createNewDeploymentSubset and setProtocolVersion when locked', async () => {
    const d = await Driver.new();

    await d.protocol.lock({from: d.migrationOwner.address});

    let currTime: number = await getTopBlockTimestamp(d);
    await expectRejected(d.protocol.createDeploymentSubset("newdeploymentsubset", 1, {from: d.functionalOwner.address}));
    await expectRejected(d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 2, currTime + 100, {from: d.functionalOwner.address}));

    await d.protocol.unlock({from: d.migrationOwner.address});

    currTime = await getTopBlockTimestamp(d);
    await d.protocol.createDeploymentSubset("newdeploymentsubset", 1, {from: d.functionalOwner.address});
    await d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 2, currTime + 100, {from: d.functionalOwner.address});

  });

});
