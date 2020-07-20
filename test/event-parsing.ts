import Web3 from "web3";
import * as _ from "lodash";
import {SubscriptionChangedEvent, VcCreatedEvent} from "../typings/subscriptions-contract";
import {compiledContracts} from "../compiled-contracts";
import {
    FeesAddedToBucketEvent,
    FeesWithdrawnFromBucketEvent
} from "../typings/fees-wallet-contract";

const elections = compiledContracts["Elections"];
const committee = compiledContracts["Committee"];
const guardiansRegistration = compiledContracts["GuardiansRegistration"];
const certification = compiledContracts["Certification"];
const staking = compiledContracts["StakingContract"];
const subscriptions = compiledContracts["Subscriptions"];
const rewards = compiledContracts["Rewards"];
const protocol = compiledContracts["Protocol"];
const contractRegistry = compiledContracts["ContractRegistry"];
const delegations = compiledContracts["Delegations"];
const guardianWallet = compiledContracts["GuardiansWallet"];
const feesWallet = compiledContracts["FeesWallet"];

export function parseLogs(txResult, contract, eventSignature, contractAddress?: string) {
    const abi = new Web3().eth.abi;
    const inputs = contract.abi.find(e => e.name == eventSignature.split('(')[0]).inputs;
    const eventSignatureHash = abi.encodeEventSignature(eventSignature);
    return _.values(txResult.events)
        .reduce((x,y) => x.concat(y), [])
        .filter(e => contractAddress == null || contractAddress == e.address)
        .map(e => e.raw)
        .filter(e => e.topics[0] === eventSignatureHash)
        .map(e => abi.decodeLog(inputs, e.data, e.topics.slice(1) /*assume all events are non-anonymous*/));
}

export const committeeSnapshotEvents = (txResult, contractAddress?: string) => parseLogs(txResult, committee, "CommitteeSnapshot(address[],uint256[],bool[])", contractAddress);
export const guardianRegisteredEvents = (txResult, contractAddress?: string) => parseLogs(txResult, guardiansRegistration, "GuardianRegistered(address)", contractAddress);
export const guardianUnregisteredEvents = (txResult, contractAddress?: string) => parseLogs(txResult, guardiansRegistration, "GuardianUnregistered(address)", contractAddress);
export const guardianDataUpdatedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, guardiansRegistration, "GuardianDataUpdated(address,bytes4,address,string,string,string)", contractAddress);
export const guardianMetadataChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, guardiansRegistration, "GuardianMetadataChanged(address,string,string,string)", contractAddress);
export const stakedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, staking, "Staked(address,uint256,uint256)", contractAddress);
export const unstakedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, staking, "Unstaked(address,uint256,uint256)", contractAddress);
export const delegatedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, delegations, "Delegated(address,address)", contractAddress);
export const delegatedStakeChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, delegations, "DelegatedStakeChanged(address,uint256,uint256,address[],uint256[])", contractAddress);
export const subscriptionChangedEvents = (txResult, contractAddress?: string): SubscriptionChangedEvent[] => parseLogs(txResult, subscriptions, "SubscriptionChanged(uint256,uint256,uint256,string,string)", contractAddress);
export const paymentEvents = (txResult, contractAddress?: string) => parseLogs(txResult, subscriptions, "Payment(uint256,address,uint256,string,uint256)", contractAddress);
export const feesAddedToBucketEvents = (txResult, contractAddress?: string): FeesAddedToBucketEvent[] => parseLogs(txResult, feesWallet, "FeesAddedToBucket(uint256,uint256,uint256)", contractAddress);
export const feesWithdrawnFromBucketEvents = (txResult, contractAddress?: string): FeesWithdrawnFromBucketEvent[] => parseLogs(txResult, feesWallet, "FeesWithdrawnToBucket(uint256,uint256,uint256)", contractAddress);
export const stakingRewardsDistributedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, rewards, "StakingRewardsDistributed(address,uint256,uint256,uint256,uint256,address[],uint256[])", contractAddress);
export const vcConfigRecordChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, subscriptions, "VcConfigRecordChanged(uint256,string,string)", contractAddress);
export const vcOwnerChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, subscriptions, "VcOwnerChanged(uint256,address,address)", contractAddress);
export const vcCreatedEvents = (txResult, contractAddress?: string): VcCreatedEvent[] => parseLogs(txResult, subscriptions, "VcCreated(uint256,address)", contractAddress);
export const contractAddressUpdatedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, contractRegistry, "ContractAddressUpdated(string,address)", contractAddress);
export const protocolChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, protocol, "ProtocolVersionChanged(string,uint256,uint256,uint256)", contractAddress);
export const guardianCertificationUpdateEvents = (txResult, contractAddress?: string) => parseLogs(txResult, certification, "GuardianCertificationUpdate(address,bool)", contractAddress);
export const lockedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, protocol, "Locked()", contractAddress);
export const unlockedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, protocol, "Unlocked()", contractAddress);
export const readyToSyncTimeoutChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, committee, "ReadyToSyncTimeoutChanged(uint32,uint32)");
export const maxTimeBetweenRewardAssignmentsChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, committee, "MaxTimeBetweenRewardAssignmentsChanged(uint32,uint32)");
export const maxCommitteeSizeChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, committee, "MaxCommitteeSizeChanged(uint8,uint8)");
export const guardianStatusUpdatedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "GuardianStatusUpdated(address,bool,bool)");
export const maxDelegatorsStakingRewardsChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, rewards, "MaxDelegatorsStakingRewardsChanged(uint32)");
export const contractRegistryAddressUpdatedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "ContractRegistryAddressUpdated(address)");
export const guardianCommitteeChangeEvents = (txResult, contractAddress?: string) => parseLogs(txResult, committee, "GuardianCommitteeChange(address,uint256,bool,bool,bool)");
export const guardianVotedUnreadyEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "GuardianVotedUnready(address)");
export const guardianVotedOutEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "GuardianVotedOut(address)");
export const guardianVotedInEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "GuardianVotedIn(address)");
export const voteUnreadyCastedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "VoteUnreadyCasted(address,address)");
export const voteOutCastedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "VoteOutCasted(address,address[])");
export const readyForCommiteeEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "ReadyForCommitee(address)");
export const stakeChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "StakeChanged(address,uint256,uint256,uint256)");
export const voteOutTimeoutSecondsChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "VoteOutTimeoutSecondsChanged(uint32,uint32)");
export const minSelfStakePercentMilleChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "MinSelfStakePercentMilleChanged(uint32,uint32)");
export const banningLockTimeoutSecondsChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "BanningLockTimeoutSecondsChanged(uint32,uint32)");
export const voteOutPercentageThresholdChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "VoteOutPercentageThresholdChanged(uint8,uint8)");
export const banningPercentageThresholdChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "BanningPercentageThresholdChanged(uint8,uint8)");
export const rewardsAssignedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, guardianWallet, "RewardsAssigned(address[],uint256[],uint256[],uint256[])");

export const gasReportEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "GasReport(string,uint256)", contractAddress);
