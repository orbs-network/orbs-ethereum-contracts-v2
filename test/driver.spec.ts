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
    const secondDriver = await Driver.new({contractRegistryForExistingContractsAddress: firstDriver.contractRegistry.address});

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
  });

  it('should instantiate a new driver object using existing tokens and staking contracts', async () => {
    const dd = await Driver.new();

    const stakingContractAddress = dd.staking.address;
    const orbsTokenAddress =  dd.erc20.address;
    const bootstrapTokenAddress =  dd.bootstrapToken.address;

    const contractRegistryAddress = dd.contractRegistry.address;
    const delegationsAddress = dd.delegations.address;
    const rewardsAddress = dd.rewards.address;
    const electionsAddress = dd.elections.address;
    const subscriptionsAddress = dd.subscriptions.address;
    const protocolAddress = dd.protocol.address;
    const certificationAddress = dd.certification.address;
    const committeeAddress = dd.committee.address;
    const stakingRewardsWalletAddress = dd.stakingRewardsWallet.address;
    const bootstrapRewardsWalletAddress = dd.bootstrapRewardsWallet.address;
    const generalFeesWalletAddress = dd.generalFeesWallet.address;
    const certifiedFeesWalletAddress = dd.certifiedFeesWallet.address;
    const guardiansRegistrationAddress = dd.guardiansRegistration.address;
    const stakingContractHandlerAddress = dd.stakingContractHandler.address;

    const d = await Driver.new({
      stakingContractAddress,
      orbsTokenAddress,
      bootstrapTokenAddress,
      contractRegistryAddress,
      delegationsAddress,
      rewardsAddress,
      electionsAddress,
      subscriptionsAddress,
      protocolAddress,
      certificationAddress,
      committeeAddress,
      stakingRewardsWalletAddress,
      bootstrapRewardsWalletAddress,
      guardiansRegistrationAddress,
      stakingContractHandlerAddress,
      certifiedFeesWalletAddress,
      generalFeesWalletAddress
    });

    expect(d.staking.address).to.equal(stakingContractAddress);
    expect(d.erc20.address).to.equal(orbsTokenAddress);
    expect(d.bootstrapToken.address).to.equal(bootstrapTokenAddress);
    expect(d.contractRegistry.address).to.equal(contractRegistryAddress);
    expect(d.delegations.address).to.equal(delegationsAddress);
    expect(d.rewards.address).to.equal(rewardsAddress);
    expect(d.elections.address).to.equal(electionsAddress);
    expect(d.subscriptions.address).to.equal(subscriptionsAddress);
    expect(d.protocol.address).to.equal(protocolAddress);
    expect(d.certification.address).to.equal(certificationAddress);
    expect(d.committee.address).to.equal(committeeAddress);
    expect(d.stakingRewardsWallet.address).to.equal(stakingRewardsWalletAddress);
    expect(d.bootstrapRewardsWallet.address).to.equal(bootstrapRewardsWalletAddress);
    expect(d.guardiansRegistration.address).to.equal(guardiansRegistrationAddress);
  });


});
