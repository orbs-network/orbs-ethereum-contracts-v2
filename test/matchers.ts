import BN from "bn.js";

import {
  parseLogs
} from "./event-parsing";
import * as _ from "lodash";
import chai from "chai";
const expect = chai.expect;

import {
  SubscriptionChangedEvent,
  PaymentEvent,
  VcConfigRecordChangedEvent,
  VcOwnerChangedEvent,
  VcCreatedEvent,
  SubscriberAddedEvent,
  SubscriberRemovedEvent, GenesisRefTimeDelayChangedEvent, MinimumInitialVcPaymentChangedEvent
} from "../typings/subscriptions-contract";
import {
  StakeChangeEvent,
  VoteUnreadyCastedEvent,
  GuardianVotedUnreadyEvent,
  VoteOutCastedEvent,
  GuardianVotedOutEvent,
  VoteOutTimeoutSecondsChangedEvent,
  MinSelfStakePercentMilleChangedEvent,
  VoteUnreadyPercentMilleThresholdChangedEvent,
  VoteOutPercentMilleThresholdChangedEvent, StakeChangedEvent, GuardianStatusUpdatedEvent
} from "../typings/elections-contract";
import { MigratedStakeEvent, StakedEvent, UnstakedEvent } from "../typings/staking-contract";
import {
  ContractAddressUpdatedEvent,
  ContractRegistryUpdatedEvent,
  ManagerChangedEvent
} from "../typings/contract-registry-contract";
import {ProtocolVersionChangedEvent} from "../typings/protocol-contract";
import {
  AnnualStakingRewardsRateChangedEvent,
  BootstrapRewardsWithdrawnEvent,
  CertifiedCommitteeAnnualBootstrapChangedEvent,
  FeesWithdrawnEvent,
  GeneralCommitteeAnnualBootstrapChangedEvent,
  GuardianStakingRewardAssignedEvent,
  DefaultDelegatorsStakingRewardsChangedEvent,
  StakingRewardAssignedEvent,
  RewardsBalanceMigratedEvent,
  RewardsBalanceMigrationAcceptedEvent,
  StakingRewardsClaimedEvent,
  RewardDistributionDeactivatedEvent,
  RewardDistributionActivatedEvent,
  GuardianDelegatorsStakingRewardsPercentMilleUpdatedEvent,
  MaxDelegatorsStakingRewardsChangedEvent
} from "../typings/rewards-contract";
import {BootstrapRewardsAssignedEvent} from "../typings/rewards-contract";
import {FeesAssignedEvent} from "../typings/rewards-contract";
import {
  GuardianDataUpdatedEvent, GuardianMetadataChangedEvent,
  GuardianRegisteredEvent,
  GuardianUnregisteredEvent
} from "../typings/guardian-registration-contract";
import {
    DelegatedEvent,
    DelegatedStakeChangedEvent, DelegationImportFinalizedEvent, DelegationsImportedEvent
} from "../typings/delegations-contract";
import {
  MaxCommitteeSizeChangedEvent,
  CommitteeChangeEvent, CommitteeSnapshotEvent,
} from "../typings/committee-contract";
import {GuardianCertificationUpdateEvent} from "../typings/certification-contract";
import {Contract} from "../eth";
import {ContractRegistryAddressUpdatedEvent, LockedEvent, UnlockedEvent} from "../typings/base-contract";
import {transpose} from "./helpers";
import {compiledContracts, eventDefinitions} from "../compiled-contracts";
import {
    ClientSetEvent,
    EmergencyWithdrawalEvent,
    FundsAddedToPoolEvent,
    MaxAnnualRateSetEvent
} from "../typings/protocol-wallet-contract";
import {
  FeesAddedToBucketEvent, FeesWithdrawnFromBucketEvent,

} from "../typings/fees-wallet-contract";
import {
  NotifyDelegationsChangedEvent,
  StakeChangeBatchNotificationFailedEvent,
  StakeChangeBatchNotificationSkippedEvent,
  StakeChangeNotificationFailedEvent,
  StakeChangeNotificationSkippedEvent,
  StakeMigrationNotificationFailedEvent,
  StakeMigrationNotificationSkippedEvent
} from "../typings/stake-change-handler-contract";
import {Driver} from "./driver";

function bnEq(b1, b2, approx?: number) {
  b1 = new BN(b1);
  b2 = new BN(b2)
  if (!approx) return b1.eq(b2);
  return b1.sub(b2).abs().lte(BN.max(b1, b2).mul(new BN(approx)).div(new BN(100)));
}

export function isBNArrayEqual(a1: Array<any>, a2: Array<any>, approx?: number): boolean {
  return (
    a1.length == a2.length &&
    a1.find((v, i) => !bnEq(a1[i], a2[i], approx)) == null
  );
}

function comparePrimitive(a: any, b: any, approx?: number): boolean {
  if (BN.isBN(a) || BN.isBN(b)) {
    return bnEq(a, b, approx);
  } else {
    if (
      (Array.isArray(a) && BN.isBN(a[0])) ||
      (Array.isArray(b) && BN.isBN(b[0]))
    ) {
      return isBNArrayEqual(a, b, approx);
    }
    return _.isEqual(a, b);
  }
}

function objectMatches(obj, against, approx?: number): boolean {
    if (obj == null || against == null) return false;

    for (const k in against) {
      if (!comparePrimitive(obj[k], against[k], approx)) {
        return false;
      }
    }
    return true;
}

function compareEvents(actual: any, expected: any, transposeKey?: string, approx?: number): boolean {
  if (transposeKey != null) {
    const fields = Object.keys(expected);
    actual = transpose(actual, transposeKey, fields);
    expected = transpose(expected, transposeKey);
    return  Object.keys(expected).length == Object.keys(actual).length &&
        Object.keys(expected).find(key => !objectMatches(actual[key], expected[key], approx)) == null;
  } else {
    return objectMatches(actual, expected, approx);
  }
}

function stripEvent(event) {
  return _.pickBy(event, (v, k) => /[_0-9]/.exec(k[0]) == null);
}

const containEvent = (eventParser, transposeKey?: string) =>
  function(_super) {
    return function(this: any, data) {
      data = data || {};

      const contractAddress = chai.util.flag(this, "contractAddress");
      const approx = chai.util.flag(this, "approx");
      const logs = eventParser(this._obj, contractAddress).map(stripEvent);

      this.assert(
        logs.length != 0,
        "expected the event to exist",
        "expected no event to exist"
      );

      if (logs.length == 1) {
        const log = logs.pop();
        this.assert(
            compareEvents(log, data, transposeKey, approx),
            "expected #{this} to be #{exp} but got #{act}",
            "expected #{this} to not be #{act}",
            data, // expected
            log // actual
        );
      } else {
        for (const log of logs) {
          if (compareEvents(log, data, transposeKey, approx)) {
            return;
          }
        }
        this.assert(
          false,
          `No event with properties ${JSON.stringify(
            data
          )} found. Events are ${JSON.stringify(logs.map(l =>_.omitBy(l, (v, k) => /[0-9_]/.exec(k[0]))))}`
        ); // TODO make this log prettier
      }
    };
  };

const TransposeKeys = {
  "CommitteeSnapshot": "addrs",
};

interface CommitteeData {
  addrs: string[],
  weights: (number|BN)[],
  certification: boolean[]
}

export async function expectCommittee(d: Driver, expectedCommittee: Partial<CommitteeData> & {addrs: string[]}) {
  const curCommittee: any = await d.committee.getCommittee();
  const actualCommittee: CommitteeData = {
    addrs: curCommittee.addrs,
    weights: curCommittee.weights,
    certification: curCommittee.certification
  }

  chai.assert(
      compareEvents(actualCommittee, expectedCommittee, 'addrs'),
      `expected committee to be ${JSON.stringify(expectedCommittee)} but got ${JSON.stringify(actualCommittee)}`,
  );
}

export const chaiEventMatchersPlugin = function(chai) {
  for (const event of eventDefinitions) {
    chai.Assertion.overwriteMethod(event.name[0].toLowerCase() + event.name.substr(1) + 'Event',
        containEvent(
            (txResult, contractAddress?: string) => parseLogs(txResult, compiledContracts[event.contractName], event.signature, contractAddress),
            TransposeKeys[event.name]
        )
    );
  }

  chai.Assertion.addChainableMethod("withinContract", function (this: any, contract: Contract) {
    chai.util.flag(this, "contractAddress", contract.address);
  })

  chai.Assertion.addChainableMethod("approx", function (this: any, p: number) {
    chai.util.flag(this, "approx", p || 2);
  })
};

declare global {
  export namespace Chai {
    export interface TypeComparison {
      delegatedEvent(data?: Partial<DelegatedEvent>): void;
      delegatedStakeChangedEvent(data?: Partial<DelegatedStakeChangedEvent>): void;
      committeeChangeEvent(data?: Partial<CommitteeChangeEvent>): void;
      committeeSnapshotEvent(data?: Partial<CommitteeSnapshotEvent>): void;
      guardianRegisteredEvent(data?: Partial<GuardianRegisteredEvent>): void;
      guardianMetadataChangedEvent(data?: Partial<GuardianMetadataChangedEvent>): void;
      guardianUnregisteredEvent(data?: Partial<GuardianUnregisteredEvent>): void;
      guardianDataUpdatedEvent(data?: Partial<GuardianDataUpdatedEvent>): void;
      stakeChangedEvent(data?: Partial<StakeChangeEvent>): void; // Elections?
      stakedEvent(data?: Partial<StakedEvent>): void;
      unstakedEvent(data?: Partial<UnstakedEvent>): void;
      subscriptionChangedEvent(data?: Partial<SubscriptionChangedEvent>): void;
      paymentEvent(data?: Partial<PaymentEvent>): void;
      vcConfigRecordChangedEvent(data?: Partial<VcConfigRecordChangedEvent>): void;
      vcCreatedEvent(data?: Partial<VcCreatedEvent>): void;
      vcOwnerChangedEvent(data?: Partial<VcOwnerChangedEvent>): void;
      contractAddressUpdatedEvent(data?: Partial<ContractAddressUpdatedEvent>): void;
      voteUnreadyCastedEvent(data?: Partial<VoteUnreadyCastedEvent>): void;
      guardianVotedUnreadyEvent(data?: Partial<GuardianVotedUnreadyEvent>): void;
      guardianVotedOutEvent(data?: Partial<GuardianVotedOutEvent>): void;
      voteOutCastedEvent(data?: Partial<VoteOutCastedEvent>): void;
      protocolVersionChangedEvent(data?: Partial<ProtocolVersionChangedEvent>): void;
      guardianCertificationUpdateEvent(data?: Partial<GuardianCertificationUpdateEvent>)
      stakingRewardsAssignedEvent(data?: Partial<StakingRewardAssignedEvent>);
      feesAssignedEvent(data?: Partial<FeesAssignedEvent>)
      feesAddedToBucketEvent(data?: Partial<FeesAddedToBucketEvent>);
      bootstrapRewardsAssignedEvent(data?: Partial<BootstrapRewardsAssignedEvent>)
      voteUnreadyTimeoutSecondsChangedEvent(data?: Partial<VoteOutTimeoutSecondsChangedEvent>);
      minSelfStakePercentMilleChangedEvent(data?: Partial<MinSelfStakePercentMilleChangedEvent>);
      voteOutPercentMilleThresholdChangedEvent(data?: Partial<VoteUnreadyPercentMilleThresholdChangedEvent>);
      voteUnreadyPercentMilleThresholdChangedEvent(data?: Partial<VoteOutPercentMilleThresholdChangedEvent>);
      lockedEvent(data?: Partial<LockedEvent>);
      unlockedEvent(data?: Partial<UnlockedEvent>);
      maxCommitteeSizeChangedEvent(data?: Partial<MaxCommitteeSizeChangedEvent>);
      feesWithdrawnEvent(data?: Partial<FeesWithdrawnEvent>);
      feesWithdrawnFromBucketEvent(data?: Partial<FeesWithdrawnFromBucketEvent>);
      bootstrapRewardsWithdrawnEvent(data?: Partial<BootstrapRewardsWithdrawnEvent>);
      guardianStatusUpdatedEvent(data?: Partial<GuardianStatusUpdatedEvent>);
      contractRegistryAddressUpdatedEvent(data?: Partial<ContractRegistryAddressUpdatedEvent>)
      defaultDelegatorsStakingRewardsChangedEvent(data?: Partial<DefaultDelegatorsStakingRewardsChangedEvent>);
      maxDelegatorsStakingRewardsChangedEvent(data?: Partial<MaxDelegatorsStakingRewardsChangedEvent>);
      fundsAddedToPoolEvent(data?: Partial<FundsAddedToPoolEvent>);
      clientSetEvent(data?: Partial<ClientSetEvent>);
      maxAnnualRateSetEvent(data?: Partial<MaxAnnualRateSetEvent>);
      emergencyWithdrawalEvent(data?: Partial<EmergencyWithdrawalEvent>);
      delegationImportFinalizedEvent(data?: Partial<DelegationImportFinalizedEvent>);
      delegationsImportedEvent(data?: Partial<DelegationsImportedEvent>);
      transferEvent(data?: Partial<{from: string, to: string, value: string|BN}>);
      subscriberAddedEvent(data?: Partial<SubscriberAddedEvent>);
      subscriberRemovedEvent(data?: Partial<SubscriberRemovedEvent>);
      genesisRefTimeDelayChangedEvent(data?: Partial<GenesisRefTimeDelayChangedEvent>);
      minimumInitialVcPaymentChangedEvent(data?: Partial<MinimumInitialVcPaymentChangedEvent>);
      rewardsBalanceMigratedEvent(data?: Partial<RewardsBalanceMigratedEvent>);
      rewardsBalanceMigrationAcceptedEvent(data?: Partial<RewardsBalanceMigrationAcceptedEvent>);
      stakeChangeNotificationFailedEvent(data?: Partial<StakeChangeNotificationFailedEvent>);
      stakeChangeBatchNotificationFailedEvent(data?: Partial<StakeChangeBatchNotificationFailedEvent>);
      stakeMigrationNotificationFailedEvent(data?: Partial<StakeMigrationNotificationFailedEvent>);
      stakeChangeNotificationSkippedEvent(data?: Partial<StakeChangeNotificationSkippedEvent>);
      stakeChangeBatchNotificationSkippedEvent(data?: Partial<StakeChangeBatchNotificationSkippedEvent>);
      stakeMigrationNotificationSkippedEvent(data?: Partial<StakeMigrationNotificationSkippedEvent>);
      migratedStakeEvent(data?: Partial<MigratedStakeEvent>);
      managerChangedEvent(data?: Partial<ManagerChangedEvent>);
      initializationCompleteEvent(data?: {});
      annualStakingRewardsRateChangedEvent(data?: Partial<AnnualStakingRewardsRateChangedEvent>);
      generalCommitteeAnnualBootstrapChangedEvent(data?: Partial<GeneralCommitteeAnnualBootstrapChangedEvent>);
      certifiedCommitteeAnnualBootstrapChangedEvent(data?: Partial<CertifiedCommitteeAnnualBootstrapChangedEvent>);
      contractRegistryUpdatedEvent(data?: Partial<ContractRegistryUpdatedEvent>);
      notifyDelegationsChangedEvent(data?: Partial<NotifyDelegationsChangedEvent>);
      guardianStakingRewardAssignedEvent(data?: Partial<GuardianStakingRewardAssignedEvent>);
      stakeChangedEvent(data?: Partial<StakeChangedEvent>);
      stakingRewardsClaimedEvent(data?: Partial<StakingRewardsClaimedEvent>);
      rewardDistributionDeactivatedEvent(data?: Partial<RewardDistributionDeactivatedEvent>);
      rewardDistributionActivatedEvent(data?: Partial<RewardDistributionActivatedEvent>);
      guardianDelegatorsStakingRewardsPercentMilleUpdatedEvent(data?: Partial<GuardianDelegatorsStakingRewardsPercentMilleUpdatedEvent>);

      withinContract(contract: Contract): Assertion;
      approx(): Assertion;
    }

    export interface Assertion {
      bignumber: Assertion;
    }
  }
}
