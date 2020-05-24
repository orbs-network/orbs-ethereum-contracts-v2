import 'mocha';


import BN from "bn.js";
import {Driver, DEPLOYMENT_SUBSET_MAIN, DEPLOYMENT_SUBSET_CANARY, expectRejected} from "./driver";
import chai from "chai";

chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const expect = chai.expect;

import {bn, evmIncreaseTimeForQueries, getTopBlockTimestamp} from "./helpers";

describe('protocol-contract', async () => {

  it('schedules a protocol version upgrade for the main, canary deployment subsets', async () => {
    const d = await Driver.new();

    let currTime: number = await getTopBlockTimestamp(d);
    let r = await d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 2, currTime + 100);
    expect(r).to.have.a.protocolChangedEvent({
      deploymentSubset: DEPLOYMENT_SUBSET_MAIN,
      currentVersion: bn(1),
      nextVersion: bn(2),
      fromTimestamp: bn(currTime + 100)
    });

    r = await d.protocol.createDeploymentSubset(DEPLOYMENT_SUBSET_CANARY, 2);
    expect(r).to.have.a.protocolChangedEvent({
      deploymentSubset: DEPLOYMENT_SUBSET_CANARY,
      currentVersion: bn(2),
      nextVersion: bn(2),
      fromTimestamp: bn(await d.web3.txTimestamp(r))
    });

    r = await d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_CANARY, 3, currTime + 100);
    expect(r).to.have.a.protocolChangedEvent({
      deploymentSubset: DEPLOYMENT_SUBSET_CANARY,
      currentVersion: bn(2),
      nextVersion: bn(3),
      fromTimestamp: bn(currTime + 100)
    });
  });

  it('does not allow protocol upgrade to be scheduled before the latest upgrade schedule when latest upgrade already took place', async () => {
    const d = await Driver.new();

    const currTime: number = await getTopBlockTimestamp(d);
    let r = await d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 2, currTime + 3);
    expect(r).to.have.a.protocolChangedEvent({
      deploymentSubset: DEPLOYMENT_SUBSET_MAIN,
      currentVersion: bn(1),
      nextVersion: bn(2),
      fromTimestamp: bn(currTime + 3)
    });

    await evmIncreaseTimeForQueries(d.web3, 3);

    await expectRejected(d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 3, currTime + 3));
    await expectRejected(d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 3, currTime + 2));
  });

  it('allows protocol upgrade to be scheduled before the latest upgrade schedule when latest upgrade did not yet take place', async () => {
    const d = await Driver.new();

    const currTime: number = await getTopBlockTimestamp(d);
    let r = await d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 2, currTime + 100);
    expect(r).to.have.a.protocolChangedEvent({
      deploymentSubset: DEPLOYMENT_SUBSET_MAIN,
      currentVersion: bn(1),
      nextVersion: bn(2),
      fromTimestamp: bn(currTime + 100)
    });

    await d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 4, currTime + 100);
    await d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 3, currTime + 99);
  });

  it('does not allow protocol upgrade to be scheduled in the past or now', async () => {
    const d = await Driver.new();

    const currTime: number = await getTopBlockTimestamp(d);
    await expectRejected(d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 2, currTime)); // fromTimestamps likely equal now
    await expectRejected(d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 2, currTime-1)); // fromTimestamps behind now
  });

  it('does not allow protocol downgrade', async () => {
    const d = await Driver.new();

    const currTime: number = await getTopBlockTimestamp(d);
    let r = await d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 3, currTime + 3);
    expect(r).to.have.a.protocolChangedEvent({
      deploymentSubset: DEPLOYMENT_SUBSET_MAIN,
      currentVersion: bn(1),
      nextVersion: bn(3),
      fromTimestamp: bn(currTime + 3)
    });

    await evmIncreaseTimeForQueries(d.web3, 3);

    await expectRejected(d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 2, currTime + 100));
  });

  it('allows upgrading to current version (an abort mechanism)', async () => {
    const d = await Driver.new();

    const currTime: number = await getTopBlockTimestamp(d);
    let r = await d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 3, currTime + 3);
    expect(r).to.have.a.protocolChangedEvent({
      deploymentSubset: DEPLOYMENT_SUBSET_MAIN,
      currentVersion: bn(1),
      nextVersion: bn(3),
      fromTimestamp: bn(currTime + 3)
    });

    await evmIncreaseTimeForQueries(d.web3, 3);

    r = await d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 4, currTime + 100);
    expect(r).to.have.a.protocolChangedEvent({
      deploymentSubset: DEPLOYMENT_SUBSET_MAIN,
      currentVersion: bn(3),
      nextVersion: bn(4),
      fromTimestamp: bn(currTime + 100)
    });

    r = await d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 3, currTime + 50);
    expect(r).to.have.a.protocolChangedEvent({
      deploymentSubset: DEPLOYMENT_SUBSET_MAIN,
      currentVersion: bn(3),
      nextVersion: bn(3),
      fromTimestamp: bn(currTime + 50)
    });
  });

  it('gets the current protocol version before and after an upgrade, on first and subsequent upgrades', async () => {
    const d = await Driver.new();

    let reportedVersion: BN = await d.protocol.getProtocolVersion(DEPLOYMENT_SUBSET_MAIN);
    expect(reportedVersion).to.be.bignumber.equal(bn(1));

    // first upgrade
    let currTime: number = await getTopBlockTimestamp(d);
    await d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 2, currTime + 3);

    reportedVersion = await d.protocol.getProtocolVersion(DEPLOYMENT_SUBSET_MAIN);
    expect(reportedVersion).to.be.bignumber.equal(bn(1));

    await evmIncreaseTimeForQueries(d.web3, 3);

    reportedVersion = await d.protocol.getProtocolVersion(DEPLOYMENT_SUBSET_MAIN);
    expect(reportedVersion).to.be.bignumber.equal(bn(2));

    // the second upgrade
    currTime = await getTopBlockTimestamp(d);
    await d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 3, currTime + 3);

    reportedVersion = await d.protocol.getProtocolVersion(DEPLOYMENT_SUBSET_MAIN);
    expect(reportedVersion).to.be.bignumber.equal(bn(2));

    await evmIncreaseTimeForQueries(d.web3, 6);

    reportedVersion = await d.protocol.getProtocolVersion(DEPLOYMENT_SUBSET_MAIN);
    expect(reportedVersion).to.be.bignumber.equal(bn(3));

  });

  it('distinguishes between different deployment subsets when calling getProtocolVersion', async () => {
    const d = await Driver.new();

    const currTime: number = await getTopBlockTimestamp(d);
    await d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 2, currTime + 100);

    // future upgrade should not affect the current version
    let reportedVersionMain = await d.protocol.getProtocolVersion(DEPLOYMENT_SUBSET_MAIN);
    expect(reportedVersionMain).to.be.bignumber.equal(bn(1));

    // create a second deployment subset
    await d.protocol.createDeploymentSubset(DEPLOYMENT_SUBSET_CANARY, 3);

    let reportedVersionCanary = await d.protocol.getProtocolVersion(DEPLOYMENT_SUBSET_CANARY);
    expect(reportedVersionCanary).to.be.bignumber.equal(bn(3));

    // should not affect DEPLOYMENT_SUBSET_MAIN
    reportedVersionMain = await d.protocol.getProtocolVersion(DEPLOYMENT_SUBSET_MAIN);
    expect(reportedVersionMain).to.be.bignumber.equal(bn(1));

    await evmIncreaseTimeForQueries(d.web3, 100); // upgrade of DEPLOYMENT_SUBSET_MAIN kicks in

    reportedVersionMain = await d.protocol.getProtocolVersion(DEPLOYMENT_SUBSET_MAIN);
    expect(reportedVersionMain).to.be.bignumber.equal(bn(2));

    // should not affect DEPLOYMENT_SUBSET_CANARY
    reportedVersionCanary = await d.protocol.getProtocolVersion(DEPLOYMENT_SUBSET_CANARY);
    expect(reportedVersionCanary).to.be.bignumber.equal(bn(3));
  });
});
