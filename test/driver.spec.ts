import 'mocha';

import * as _ from "lodash";
import BN from "bn.js";
import {Driver, DEPLOYMENT_SUBSET_MAIN, Participant} from "./driver";
import chai from "chai";

chai.use(require('chai-bn')(BN));
chai.use(require('./matchers'));

const expect = chai.expect;

describe('testkit', async () => {

  it('should instantiate a new driver object using existing contracts', async () => {
    const firstDriver = await Driver.new({maxCommitteeSize: 4});
    const secondDriver = await Driver.new({contractRegistryAddress: firstDriver.contractRegistry.address});

    expect(firstDriver.contractRegistry.address).to.equal(secondDriver.contractRegistry.address);
    expect(firstDriver.elections.address).to.equal(secondDriver.elections.address);
    expect(firstDriver.erc20.address).to.equal(secondDriver.erc20.address);
    expect(firstDriver.bootstrapToken.address).to.equal(secondDriver.bootstrapToken.address);
    expect(firstDriver.staking.address).to.equal(secondDriver.staking.address);
    expect(firstDriver.delegations.address).to.equal(secondDriver.delegations.address);
    expect(firstDriver.subscriptions.address).to.equal(secondDriver.subscriptions.address);
    expect(firstDriver.rewards.address).to.equal(secondDriver.rewards.address);
    expect(firstDriver.protocol.address).to.equal(secondDriver.protocol.address);
    expect(firstDriver.certification.address).to.equal(secondDriver.certification.address);
    expect(firstDriver.guardiansRegistration.address).to.equal(secondDriver.guardiansRegistration.address);
    expect(firstDriver.committee.address).to.equal(secondDriver.committee.address);
  })
});
