import 'mocha';

import * as _ from "lodash";
import BN from "bn.js";
import {Driver, DEPLOYMENT_SUBSET_MAIN, Participant} from "./driver";
import chai from "chai";
import {feesAddedToBucketEvents, subscriptionChangedEvents, vcCreatedEvents} from "./event-parsing";
import {bn, bnSum, evmIncreaseTime, fromTokenUnits, toTokenUnits} from "./helpers";
import {TransactionReceipt} from "web3-core";
import {Web3Driver} from "../eth";
import {FeesAddedToBucketEvent} from "../typings/rewards-contract";
import {Contracts} from "../typings/contracts";

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
    expect(firstDriver.externalToken.address).to.equal(secondDriver.externalToken.address);
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

    const stakingContractAddress = dd.newParticipant().address;
    const orbsTokenAddress =  dd.newParticipant().address;
    const bootstrapTokenAddress =  dd.newParticipant().address;

    const contractRegistryAddress = dd.newParticipant().address;
    const delegationsAddress = dd.newParticipant().address;
    const rewardsAddress = dd.newParticipant().address;
    const electionsAddress = dd.newParticipant().address;
    const subscriptionsAddress = dd.newParticipant().address;
    const protocolAddress = dd.newParticipant().address;
    const certificationAddress = dd.newParticipant().address;
    const committeeAddress = dd.newParticipant().address;
    const stakingRewardsWalletAddress = dd.newParticipant().address;
    const bootstrapRewardsWalletAddress = dd.newParticipant().address;
    const guardiansRegistrationAddress = dd.newParticipant().address;

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
    });

    expect(d.staking.address).to.equal(stakingContractAddress);
    expect(d.erc20.address).to.equal(orbsTokenAddress);
    expect(d.externalToken.address).to.equal(bootstrapTokenAddress);
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
