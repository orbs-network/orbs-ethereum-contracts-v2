import 'mocha';

import * as _ from "lodash";
import BN from "bn.js";
import {Driver, DEPLOYMENT_SUBSET_MAIN, Participant} from "./driver";
import chai from "chai";
import {bn, bnSum, evmIncreaseTime, expectRejected, fromTokenUnits, toTokenUnits} from "./helpers";
import {chaiEventMatchersPlugin} from "./matchers";

chai.use(require('chai-bn')(BN));
chai.use(chaiEventMatchersPlugin);

const MONTH_IN_SECONDS = 30*24*60*60;

const expect = chai.expect;

async function sleep(ms): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
}

describe('initializable', async () => {

    it('should allow the initializer to act as all roles until init complete', async () => {
        const d = await Driver.new();

        const managed = await d.web3.deploy('ManagedContractTest' as any, [d.contractRegistry.address, d.registryAdmin.address]);

        await managed.adminOp({from: d.initializationAdmin.address});
        await managed.adminOp({from: d.registryAdmin.address});
        await managed.migrationManagerOp({from: d.initializationAdmin.address});
        await managed.migrationManagerOp({from: d.registryAdmin.address});
        await managed.nonExistentManagerOp({from: d.initializationAdmin.address});

        let r = await managed.initializationComplete();
        expect(r).to.have.a.initializationCompleteEvent();

        await expectRejected(managed.adminOp({from: d.initializationAdmin.address}), /sender is not an admin/);
        await managed.adminOp({from: d.registryAdmin.address});
        await expectRejected(managed.migrationManagerOp({from: d.initializationAdmin.address}), /sender is not the migration manager/);
        await managed.migrationManagerOp({from: d.registryAdmin.address});
        await expectRejected(managed.nonExistentManagerOp({from: d.initializationAdmin.address}), /sender is not the manager/);
    });

});