import Web3 from "web3";
import * as _ from "lodash";
import {SubscriptionChangedEvent, VcCreatedEvent} from "../typings/subscriptions-contract";
import {compiledContracts} from "../compiled-contracts";
import {
    BootstrapRewardsWithdrawnEvent,
    FeesAddedToBucketEvent,
    FeesWithdrawnEvent,
    FeesWithdrawnFromBucketEvent, StakingRewardsAddedToPoolEvent
} from "../typings/rewards-contract";

const elections = compiledContracts["Elections"];
const committee = compiledContracts["Committee"];
const validatorsRegistration = compiledContracts["ValidatorsRegistration"];
const compliance = compiledContracts["Compliance"];
const staking = compiledContracts["StakingContract"];
const subscriptions = compiledContracts["Subscriptions"];
const rewards = compiledContracts["Rewards"];
const protocol = compiledContracts["Protocol"];
const contractRegistry = compiledContracts["ContractRegistry"];
const delegations = compiledContracts["Delegations"];

function parseLogs(txResult, contract, eventSignature, contractAddress?: string) {
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

export const committeeChangedEvents = (txResult, contractAddress: string) => parseLogs(txResult, committee, "CommitteeChanged(address[],uint256[],bool[])", contractAddress);
export const standbysChangedEvents = (txResult, contractAddress: string) => parseLogs(txResult, committee, "StandbysChanged(address[],uint256[],bool[])", contractAddress);
export const validatorRegisteredEvents = (txResult, contractAddress?: string) => parseLogs(txResult, validatorsRegistration, "ValidatorRegistered(address)", contractAddress);
export const validatorUnregisteredEvents = (txResult, contractAddress?: string) => parseLogs(txResult, validatorsRegistration, "ValidatorUnregistered(address)", contractAddress);
export const validatorDataUpdatedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, validatorsRegistration, "ValidatorDataUpdated(address,bytes4,address,string,string,string)", contractAddress);
export const validatorMetadataChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, validatorsRegistration, "ValidatorMetadataChanged(address,string,string,string)", contractAddress);
export const stakedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, staking, "Staked(address,uint256,uint256)", contractAddress);
export const unstakedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, staking, "Unstaked(address,uint256,uint256)", contractAddress);
export const delegatedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, delegations, "Delegated(address,address)", contractAddress);
export const delegatedStakeChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, delegations, "DelegatedStakeChanged(address,uint256,uint256,address[],uint256[])", contractAddress);
export const stakeChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "StakeChanged(address,uint256,uint256,uint256,uint256,uint256)", contractAddress);
export const subscriptionChangedEvents = (txResult, contractAddress?: string): SubscriptionChangedEvent[] => parseLogs(txResult, subscriptions, "SubscriptionChanged(uint256,uint256,uint256,string,string)", contractAddress);
export const paymentEvents = (txResult, contractAddress?: string) => parseLogs(txResult, subscriptions, "Payment(uint256,address,uint256,string,uint256)", contractAddress);
export const feesAddedToBucketEvents = (txResult, contractAddress?: string): FeesAddedToBucketEvent[] => parseLogs(txResult, rewards, "FeesAddedToBucket(uint256,uint256,uint256,bool)", contractAddress);
export const feesWithdrawnFromBucketEvents = (txResult, contractAddress?: string): FeesWithdrawnFromBucketEvent[] => parseLogs(txResult, rewards, "FeesWithdrawnToBucket(uint256,uint256,uint256,bool)", contractAddress);
export const feesWithdrawnEvents = (txResult, contractAddress?: string): FeesWithdrawnEvent[] => parseLogs(txResult, rewards, "FeesWithdrawn(address,uint256)", contractAddress);
export const bootstrapRewardsWithdrawnEvents = (txResult, contractAddress?: string): BootstrapRewardsWithdrawnEvent[] => parseLogs(txResult, rewards, "BootstrapRewardsWithdrawn(address,uint256)", contractAddress);
export const stakingRewardsAddedToPoolEvents = (txResult, contractAddress?: string): StakingRewardsAddedToPoolEvent[] => parseLogs(txResult, rewards, "StakingRewardsAddedToPool(uint256,uint256)", contractAddress);
export const stakingRewardsAssignedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, rewards, "StakingRewardsAssigned(address[],uint256[])", contractAddress);
export const stakingRewardsDistributedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, rewards, "StakingRewardsDistributed(address,uint256,uint256,uint256,uint256,address[],uint256[])", contractAddress);
export const feesAssignedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, rewards, "FeesAssigned(uint256,uint256)", contractAddress);
export const bootstrapRewardsAssignedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, rewards, "BootstrapRewardsAssigned(uint256,uint256)", contractAddress);
export const bootstrapAddedToPoolEvents = (txResult, contractAddress?: string) => parseLogs(txResult, rewards, "BootstrapAddedToPool(uint256,uint256)", contractAddress);
export const voteOutEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "VoteOut(address,address)", contractAddress);
export const votedOutOfCommitteeEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "VotedOutOfCommittee(address)", contractAddress);
export const vcConfigRecordChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, subscriptions, "VcConfigRecordChanged(uint256,string,string)", contractAddress);
export const vcOwnerChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, subscriptions, "VcOwnerChanged(uint256,address,address)", contractAddress);
export const vcCreatedEvents = (txResult, contractAddress?: string): VcCreatedEvent[] => parseLogs(txResult, subscriptions, "VcCreated(uint256,address)", contractAddress);
export const contractAddressUpdatedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, contractRegistry, "ContractAddressUpdated(string,address)", contractAddress);
export const protocolChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, protocol, "ProtocolVersionChanged(string,uint256,uint256,uint256)", contractAddress);
export const banningVoteEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "BanningVote(address,address[])", contractAddress);
export const electionsBanned = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "Banned(address)", contractAddress);
export const electionsUnbanned = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "Unbanned(address)", contractAddress);
export const validatorComplianceUpdateEvents = (txResult, contractAddress?: string) => parseLogs(txResult, compliance, "ValidatorComplianceUpdate(address,bool)", contractAddress);
export const voteOutTimeoutSecondsChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "VoteOutTimeoutSecondsChanged(uint32,uint32)");
export const maxDelegationRatioChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "MaxDelegationRatioChanged(uint32,uint32)");
export const banningLockTimeoutSecondsChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "BanningLockTimeoutSecondsChanged(uint32,uint32)");
export const voteOutPercentageThresholdChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "VoteOutPercentageThresholdChanged(uint8,uint8)");
export const banningPercentageThresholdChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "BanningPercentageThresholdChanged(uint8,uint8)");
export const lockedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, protocol, "Locked()", contractAddress);
export const unlockedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, protocol, "Unlocked()", contractAddress);
export const readyToSyncTimeoutChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, committee, "ReadyToSyncTimeoutChanged(uint48,uint48)");
export const maxCommitteeSizeChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, committee, "MaxCommitteeSizeChanged(uint8,uint8)");
export const maxStandbysChangedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, committee, "MaxStandbysChanged(uint8,uint8)");
export const validatorStatusUpdatedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "ValidatorStatusUpdated(address,bool,bool)");
export const contractRegistryAddressUpdatedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "ContractRegistryAddressUpdated(address)");

export const gasReportEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "GasReport(string,uint256)", contractAddress);
