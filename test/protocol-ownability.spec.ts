import 'mocha';


import BN from "bn.js";
import {Driver, DEPLOYMENT_SUBSET_MAIN, DEPLOYMENT_SUBSET_CANARY, expectRejected} from "./driver";
import chai from "chai";

chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const expect = chai.expect;

import {bn, evmIncreaseTimeForQueries, getTopBlockTimestamp} from "./helpers";

describe('protocol-contract', async () => {

  // functional owner

  it('allows only the functional owner to set protocol version', async () => {
    const d = await Driver.new();

    let currTime: number = await getTopBlockTimestamp(d);
    await expectRejected(d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 2, currTime + 100, {from: d.migrationOwner.address}));
    await d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 2, currTime + 100, {from: d.functionalOwner.address});
  });

  it('only current functional owner can transfer functional ownership', async () => {
    const d = await Driver.new();

    const newOwner = d.newParticipant();
    await expectRejected(d.protocol.transferFunctionalOwnership(newOwner.address, {from: d.migrationOwner.address}));
    await d.protocol.transferFunctionalOwnership(newOwner.address, {from: d.functionalOwner.address});

  });

  it('does not transfer functional ownership until claimed by new owner', async () => {
    const d = await Driver.new();

    const newOwner = d.newParticipant();
    await d.protocol.transferFunctionalOwnership(newOwner.address, {from: d.functionalOwner.address});

    let currTime: number = await getTopBlockTimestamp(d);
    await expectRejected(d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 2, currTime + 100, {from: newOwner.address}));
    await d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 3, currTime + 100, {from: d.functionalOwner.address});

    const notNewOwner = d.newParticipant();
    await expectRejected(d.protocol.claimFunctionalOwnership({from: notNewOwner.address}));

    await d.protocol.claimFunctionalOwnership({from: newOwner.address});
    await expectRejected(d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 4, currTime + 100, {from: d.functionalOwner.address}));
    await d.protocol.setProtocolVersion(DEPLOYMENT_SUBSET_MAIN, 4, currTime + 100, {from: newOwner.address});
  });

  // migration owner

  it('allows only the migration owner to set contract registry', async () => {
    const d = await Driver.new();

    const newAddr = d.newParticipant().address;

    await expectRejected(d.protocol.setContractRegistry(newAddr, {from: d.functionalOwner.address}));
    await d.protocol.setContractRegistry(newAddr, {from: d.migrationOwner.address});
  });

  it('only current migration owner can transfer migration ownership', async () => {
    const d = await Driver.new();

    const newOwner = d.newParticipant();
    await expectRejected(d.protocol.transferMigrationOwnership(newOwner.address, {from: d.functionalOwner.address}));
    await d.protocol.transferMigrationOwnership(newOwner.address, {from: d.migrationOwner.address});

  });

  it('does not transfer migration ownership until claimed by new owner', async () => {
    const d = await Driver.new();

    const newOwner = d.newParticipant();
    await d.protocol.transferMigrationOwnership(newOwner.address, {from: d.migrationOwner.address});

    const newAddr = d.newParticipant().address;
    await expectRejected(d.protocol.setContractRegistry(newAddr, {from: newOwner.address}));
    await d.protocol.setContractRegistry(newAddr, {from: d.migrationOwner.address});

    const notNewOwner = d.newParticipant();
    await expectRejected(d.protocol.claimMigrationOwnership({from: notNewOwner.address}));

    await d.protocol.claimMigrationOwnership({from: newOwner.address});
    await expectRejected(d.protocol.setContractRegistry(newAddr, {from: d.migrationOwner.address}));
    await d.protocol.setContractRegistry(newAddr, {from: newOwner.address});
  });


});
