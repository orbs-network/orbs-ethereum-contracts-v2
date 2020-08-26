import 'mocha';

import * as _ from "lodash";
import BN from "bn.js";
import {Driver, DEPLOYMENT_SUBSET_MAIN, Participant} from "./driver";
import chai from "chai";
import {
    feesAddedToBucketEvents, feesAssignedEvents,
    subscriptionChangedEvents,
    vcCreatedEvents
} from "./event-parsing";
import {bn, bnSum, evmIncreaseTime, expectRejected, fromTokenUnits, toTokenUnits} from "./helpers";
import {FeesAddedToBucketEvent} from "../typings/fees-wallet-contract";
import {FeesAssignedEvent} from "../typings/rewards-contract";

chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const MONTH_IN_SECONDS = 30*24*60*60;

const expect = chai.expect;

async function sleep(ms): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
}

describe('initializable', async () => {

    it('should allow the initializer to act as all roles until init complete', async () => {
        const d = await Driver.new();

        const managed = await d.web3.deploy('ManagedContractTest' as any, [d.contractRegistry.address, d.registryManager.address]);

        await managed.adminOp({from: d.initializationManager.address});
        await managed.adminOp({from: d.registryManager.address});
        await managed.migrationManagerOp({from: d.initializationManager.address});
        await managed.migrationManagerOp({from: d.registryManager.address});
        await managed.nonExistentManagerOp({from: d.initializationManager.address});

        let r = await managed.initializationComplete();
        expect(r).to.have.a.initializationCompleteEvent();

        await expectRejected(managed.adminOp({from: d.initializationManager.address}), /sender is not an admin/);
        await managed.adminOp({from: d.registryManager.address});
        await expectRejected(managed.migrationManagerOp({from: d.initializationManager.address}), /sender is not the migration manager/);
        await managed.migrationManagerOp({from: d.registryManager.address});
        await expectRejected(managed.nonExistentManagerOp({from: d.initializationManager.address}), /sender is not the manager/);
    });

});