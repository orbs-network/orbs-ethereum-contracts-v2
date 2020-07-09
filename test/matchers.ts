import BN from "bn.js";

import {
  parseLogs
} from "./event-parsing";
import * as _ from "lodash";
import chai from "chai";
const expect = chai.expect;

import {
  SubscriptionChangedEvent,
  PaymentEvent, VcConfigRecordChangedEvent, VcOwnerChangedEvent, VcCreatedEvent
} from "../typings/subscriptions-contract";
import {
  StakeChangeEvent,
  VoteUnreadyCastedEvent,
  ValidatorVotedUnreadyEvent,
  VoteOutCastedEvent,
  ValidatorVotedOutEvent,
  ValidatorVotedInEvent,
  VoteOutTimeoutSecondsChangedEvent,
  MaxDelegationRatioChangedEvent,
  VoteOutLockTimeoutSecondsChangedEvent,
  VoteUnreadyPercentageThresholdChangedEvent,
  VoteOutPercentageThresholdChangedEvent
} from "../typings/elections-contract";
import { StakedEvent, UnstakedEvent } from "../typings/staking-contract";
import {ContractAddressUpdatedEvent} from "../typings/contract-registry-contract";
import {ProtocolVersionChangedEvent} from "../typings/protocol-contract";
import {
  BootstrapRewardsWithdrawnEvent,
  FeesWithdrawnEvent, MaxDelegatorsStakingRewardsChangedEvent,
  StakingRewardAssignedEvent, StakingRewardsAddedToPoolEvent,
  StakingRewardsDistributedEvent
} from "../typings/rewards-contract";
import {BootstrapAddedToPoolEvent, BootstrapRewardsAssignedEvent} from "../typings/rewards-contract";
import {FeesAddedToBucketEvent, FeesAssignedEvent} from "../typings/rewards-contract";
import {
  ValidatorDataUpdatedEvent, ValidatorMetadataChangedEvent,
  ValidatorRegisteredEvent,
  ValidatorUnregisteredEvent
} from "../typings/validator-registration-contract";
import {
    DelegatedEvent,
    DelegatedStakeChangedEvent, DelegationImportFinalizedEvent, DelegationsImportedEvent
} from "../typings/delegations-contract";
import {
  CommitteeSnapshotEvent,
  MaxCommitteeSizeChangedEvent,
  MaxTimeBetweenRewardAssignmentsChangedEvent,
  ValidatorCommitteeChangeEvent,
  ValidatorStatusUpdatedEvent
} from "../typings/committee-contract";
import {ValidatorComplianceUpdateEvent} from "../typings/compliance-contract";
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

export function isBNArrayEqual(a1: Array<any>, a2: Array<any>): boolean {
  return (
    a1.length == a2.length &&
    a1.find((v, i) => !new BN(a1[i]).eq(new BN(a2[i]))) == null
  );
}

function comparePrimitive(a: any, b: any): boolean {
  if (BN.isBN(a) || BN.isBN(b)) {
    return new BN(a).eq(new BN(b));
  } else {
    if (
      (Array.isArray(a) && BN.isBN(a[0])) ||
      (Array.isArray(b) && BN.isBN(b[0]))
    ) {
      return isBNArrayEqual(a, b);
    }
    return _.isEqual(a, b);
  }
}

function objectMatches(obj, against): boolean {
    if (obj == null || against == null) return false;

    for (const k in against) {
      if (!comparePrimitive(obj[k], against[k])) {
        return false;
      }
    }
    return true;
}

function compare(event: any, against: any, transposeKey?: string): boolean {
  if (transposeKey != null) {
    const fields = Object.keys(against);
    event = transpose(event, transposeKey, fields);
    against = transpose(against, transposeKey);
    return  Object.keys(against).length == Object.keys(event).length &&
        Object.keys(against).find(key => !objectMatches(event[key], against[key])) == null;
  } else {
    return objectMatches(event, against);
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
      const logs = eventParser(this._obj, contractAddress).map(stripEvent);

      this.assert(
        logs.length != 0,
        "expected the event to exist",
        "expected no event to exist"
      );

      if (logs.length == 1) {
        const log = logs.pop();
        this.assert(
            compare(log, data, transposeKey),
            "expected #{this} to be #{exp} but got #{act}",
            "expected #{this} to not be #{act}",
            data, // expected
            log // actual
        );
      } else {
        for (const log of logs) {
          if (compare(log, data, transposeKey)) {
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
  "StandbysSnapshot": "addrs",
  "StakingRewardsAssigned": "assignees",
};

module.exports = function(chai) {
  for (const event of eventDefinitions) {
    chai.Assertion.overwriteMethod(event.name[0].toLowerCase() + event.name.substr(1) + 'Event',
        containEvent(
            (txResult, contractAddress?: string) => parseLogs(txResult, compiledContracts[event.contractName], event.signature, contractAddress),
            TransposeKeys[event.name]
        )
    );
  }
  chai.Assertion.overwriteMethod("haveCommittee", containEvent(function(o) {return [o];}));

  chai.Assertion.addChainableMethod("withinContract", function (this: any, contract: Contract) {
    chai.util.flag(this, "contractAddress", contract.address);
  })
};

declare global {
  export namespace Chai {
    export interface TypeComparison {
      delegatedEvent(data?: Partial<DelegatedEvent>): void;
      delegatedStakeChangedEvent(data?: Partial<DelegatedStakeChangedEvent>): void;
      committeeSnapshotEvent(data?: Partial<CommitteeSnapshotEvent>): void;
      validatorCommitteeChangeEvent(data?: Partial<ValidatorCommitteeChangeEvent>): void;
      validatorRegisteredEvent(data?: Partial<ValidatorRegisteredEvent>): void;
      validatorMetadataChangedEvent(data?: Partial<ValidatorMetadataChangedEvent>): void;
      validatorUnregisteredEvent(data?: Partial<ValidatorUnregisteredEvent>): void;
      validatorDataUpdatedEvent(data?: Partial<ValidatorDataUpdatedEvent>): void;
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
      validatorVotedUnreadyEvent(data?: Partial<ValidatorVotedUnreadyEvent>): void;
      validatorVotedOutEvent(data?: Partial<ValidatorVotedOutEvent>): void;
      validatorVotedInEvent(data?: Partial<ValidatorVotedInEvent>): void;
      voteOutCastedEvent(data?: Partial<VoteOutCastedEvent>): void;
      protocolVersionChangedEvent(data?: Partial<ProtocolVersionChangedEvent>): void;
      validatorComplianceUpdateEvent(data?: Partial<ValidatorComplianceUpdateEvent>)
      stakingRewardsAssignedEvent(data?: Partial<StakingRewardAssignedEvent>)
      stakingRewardsDistributedEvent(data?: Partial<StakingRewardsDistributedEvent>)
      feesAssignedEvent(data?: Partial<FeesAssignedEvent>)
      feesAddedToBucketEvent(data?: Partial<FeesAddedToBucketEvent>);
      bootstrapRewardsAssignedEvent(data?: Partial<BootstrapRewardsAssignedEvent>)
      bootstrapAddedToPoolEvent(data?: Partial<BootstrapAddedToPoolEvent>)
      voteUnreadyTimeoutSecondsChangedEvent(data?: Partial<VoteOutTimeoutSecondsChangedEvent>);
      maxDelegationRatioChangedEvent(data?: Partial<MaxDelegationRatioChangedEvent>);
      voteOutLockTimeoutSecondsChangedEvent(data?: Partial<VoteOutLockTimeoutSecondsChangedEvent>);
      voteOutPercentageThresholdChangedEvent(data?: Partial<VoteUnreadyPercentageThresholdChangedEvent>);
      voteUnreadyPercentageThresholdChangedEvent(data?: Partial<VoteOutPercentageThresholdChangedEvent>);
      lockedEvent(data?: Partial<LockedEvent>);
      unlockedEvent(data?: Partial<UnlockedEvent>);
      bootstrapRewardsAssignedEvent(data?: Partial<BootstrapRewardsAssignedEvent>);
      bootstrapAddedToPoolEvent(data?: Partial<BootstrapAddedToPoolEvent>);
      maxTimeBetweenRewardAssignmentsChangedEvent(data?: Partial<MaxTimeBetweenRewardAssignmentsChangedEvent>)
      maxCommitteeSizeChangedEvent(data?: Partial<MaxCommitteeSizeChangedEvent>);
      feesWithdrawnEvent(data?: Partial<FeesWithdrawnEvent>);
      bootstrapRewardsWithdrawnEvent(data?: Partial<BootstrapRewardsWithdrawnEvent>);
      stakingRewardsAddedToPoolEvent(data?: Partial<StakingRewardsAddedToPoolEvent>);
      validatorStatusUpdatedEvent(data?: Partial<ValidatorStatusUpdatedEvent>);
      contractRegistryAddressUpdatedEvent(data?: Partial<ContractRegistryAddressUpdatedEvent>)
      maxDelegatorsStakingRewardsChangedEvent(data?: Partial<MaxDelegatorsStakingRewardsChangedEvent>);
      fundsAddedToPoolEvent(data?: Partial<FundsAddedToPoolEvent>);
      clientSetEvent(data?: Partial<ClientSetEvent>);
      maxAnnualRateSetEvent(data?: Partial<MaxAnnualRateSetEvent>);
      emergencyWithdrawalEvent(data?: Partial<EmergencyWithdrawalEvent>);
      delegationImportFinalizedEvent(data?: Partial<DelegationImportFinalizedEvent>);
      delegationsImportedEvent(data?: Partial<DelegationsImportedEvent>);

      withinContract(contract: Contract): Assertion;
    }

    export interface Assertion {
      bignumber: Assertion;
      haveCommittee(data: CommitteeSnapshotEvent);
    }
  }
}
