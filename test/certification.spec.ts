import 'mocha';

import BN from "bn.js";
import {Driver, DEPLOYMENT_SUBSET_MAIN} from "./driver";
import chai from "chai";
import {chaiEventMatchersPlugin} from "./matchers";
import {expectRejected} from "./helpers";

chai.use(require('chai-bn')(BN));
chai.use(chaiEventMatchersPlugin);

const expect = chai.expect;

describe('certification-contract', async () => {

    it('sets, gets, and updates guardian certification type only by certification manager', async () => {
        // TODO see that committees are updates as a result of changing certification

        const d = await Driver.new();

        const v1 = d.newParticipant();

        // Get default
        const defaultCertification = await d.certification.isGuardianCertified(v1.address);
        expect(defaultCertification).to.equal(false);

        // Set
        await expectRejected(d.certification.setGuardianCertification(v1.address, true, {from: d.functionalManager.address}), /sender is not the certification manager/);

        let r = await d.certification.setGuardianCertification(v1.address, true, {from: d.certificationManager.address});
        expect(r).to.have.a.guardianCertificationUpdateEvent({
            guardian: v1.address,
            isCertified: true
        });

        // Get after set
        let currentCertification = await d.certification.isGuardianCertified(v1.address);
        expect(currentCertification).to.equal(true);

        // Update
        r = await d.certification.setGuardianCertification(v1.address, false, {from: d.certificationManager.address});
        expect(r).to.have.a.guardianCertificationUpdateEvent({
            guardian: v1.address,
            isCertified: false
        });

        // Get after update
        currentCertification = await d.certification.isGuardianCertified(v1.address);
        expect(currentCertification).to.equal(false);
    })

});
