import 'mocha';

import * as _ from "lodash";
import BN from "bn.js";
import {Driver, DEPLOYMENT_SUBSET_MAIN} from "./driver";
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

        const General = "General";
        const Compliance = "Compliance";

        const v1 = d.newParticipant();

        // Get default
        const defaultCompliance = await d.compliance.getValidatorCompliance(v1.address);
        expect(defaultCompliance).to.equal(General);

        // Set
        let r = await d.compliance.setValidatorCompliance(v1.address, Compliance);
        expect(r).to.have.a.validatorConformanceUpdateEvent({
            validator: v1.address,
            conformanceType: Compliance
        });

        // Get after set
        let currentCompliance = await d.compliance.getValidatorCompliance(v1.address);
        expect(currentCompliance).to.equal(Compliance);

        // Update
        r = await d.compliance.setValidatorCompliance(v1.address, General);
        expect(r).to.have.a.validatorConformanceUpdateEvent({
            validator: v1.address,
            conformanceType: General
        });

        // Get after update
        currentCompliance = await d.compliance.getValidatorCompliance(v1.address);
        expect(currentCompliance).to.equal(General);

    })

});
