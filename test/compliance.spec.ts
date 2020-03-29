import 'mocha';

import * as _ from "lodash";
import BN from "bn.js";
import {Driver, DEPLOYMENT_SUBSET_MAIN, CONFORMANCE_TYPE_GENERAL, CONFORMANCE_TYPE_COMPLIANCE} from "./driver";
import chai from "chai";
import {bn, evmIncreaseTime} from "./helpers";
import {TransactionReceipt} from "web3-core";
import {Web3Driver} from "../eth";

chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const expect = chai.expect;

describe('compliance-contract', async () => {

    it('sets, gets, and updates validator compliance type', async () => {
        // TODO see that committees are updates as a result of changing compliance

        const d = await Driver.new();

        const v1 = d.newParticipant();

        // Get default
        const defaultCompliance = await d.compliance.getValidatorCompliance(v1.address);
        expect(defaultCompliance).to.equal(CONFORMANCE_TYPE_GENERAL);

        // Set
        let r = await d.compliance.setValidatorCompliance(v1.address, CONFORMANCE_TYPE_COMPLIANCE);
        expect(r).to.have.a.validatorConformanceUpdateEvent({
            validator: v1.address,
            conformanceType: CONFORMANCE_TYPE_COMPLIANCE
        });

        // Get after set
        let currentCompliance = await d.compliance.getValidatorCompliance(v1.address);
        expect(currentCompliance).to.equal(CONFORMANCE_TYPE_COMPLIANCE);

        // Update
        r = await d.compliance.setValidatorCompliance(v1.address, CONFORMANCE_TYPE_GENERAL);
        expect(r).to.have.a.validatorConformanceUpdateEvent({
            validator: v1.address,
            conformanceType: CONFORMANCE_TYPE_GENERAL
        });

        // Get after update
        currentCompliance = await d.compliance.getValidatorCompliance(v1.address);
        expect(currentCompliance).to.equal(CONFORMANCE_TYPE_GENERAL);

    })

});
