import 'mocha';

import BN from "bn.js";
import {Driver, DEPLOYMENT_SUBSET_MAIN} from "./driver";
import chai from "chai";

chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const expect = chai.expect;

describe('compliance-contract', async () => {

    it('sets, gets, and updates validator compliance type', async () => {
        // TODO see that committees are updates as a result of changing compliance

        const d = await Driver.new();

        const v1 = d.newParticipant();

        // Get default
        const defaultCompliance = await d.compliance.isValidatorCompliant(v1.address);
        expect(defaultCompliance).to.equal(false);

        // Set
        let r = await d.compliance.setValidatorCompliance(v1.address, true, {from: d.functionalOwner.address});
        expect(r).to.have.a.validatorComplianceUpdateEvent({
            validator: v1.address,
            isCompliant: true
        });

        // Get after set
        let currentCompliance = await d.compliance.isValidatorCompliant(v1.address);
        expect(currentCompliance).to.equal(true);

        // Update
        r = await d.compliance.setValidatorCompliance(v1.address, false, {from: d.functionalOwner.address});
        expect(r).to.have.a.validatorComplianceUpdateEvent({
            validator: v1.address,
            isCompliant: false
        });

        // Get after update
        currentCompliance = await d.compliance.isValidatorCompliant(v1.address);
        expect(currentCompliance).to.equal(false);

    })

});
