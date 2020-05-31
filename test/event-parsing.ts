import Web3 from "web3";
import * as _ from "lodash";
import {SubscriptionChangedEvent, VcCreatedEvent} from "../typings/subscriptions-contract";
import {compiledContracts} from "../compiled-contracts";
import {FeesAddedToBucketEvent} from "../typings/rewards-contract";

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

export const committeeChangedEvents = (txResult, contractAddress: string) => parseLogs(txResult, committee, "CommitteeChanged(address[],address[],uint256[],bool[])", contractAddress);
export const standbysChangedEvents = (txResult, contractAddress: string) => parseLogs(txResult, committee, "StandbysChanged(address[],address[],uint256[],bool[])", contractAddress);
export const validatorRegisteredEvents = (txResult, contractAddress?: string) => parseLogs(txResult, validatorsRegistration, "ValidatorRegistered(address,bytes4,address,string,string,string)", contractAddress);
export const validatorUnregisteredEvents = (txResult, contractAddress?: string) => parseLogs(txResult, validatorsRegistration, "ValidatorUnregistered(addr)", contractAddress);
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
export const stakingRewardsAssignedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, rewards, "StakingRewardsAssigned(address[],uint48[])", contractAddress);
export const stakingRewardsDistributed = (txResult, contractAddress?: string) => parseLogs(txResult, rewards, "StakingRewardsDistributed(address,uint256,uint256,uint256,uint256,address[],uint256[])", contractAddress);
export const feesAssignedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, rewards, "FeesAssigned(address[],uint48[])", contractAddress);
export const bootstrapRewardsAssignedEvents = (txResult, contractAddress?: string) => parseLogs(txResult, rewards, "BootstrapRewardsAssigned(address[],uint48[])", contractAddress);
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

export const gasReportEvents = (txResult, contractAddress?: string) => parseLogs(txResult, elections, "GasReport(string,uint256)", contractAddress);
