import {Contract} from "../eth";
import {TransactionConfig, TransactionReceipt} from "web3-core";
import * as BN from "bn.js";
import {OwnedContract} from "./base-contract";

export interface StakeChangedEvent {
  addr: string,
  selfStake: string|BN,
  delegated_stake: string|BN,
  effective_stake: string|BN
}

export interface ElectionsContract extends OwnedContract {
  registerGuardian( ip: string, orbsAddrs: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  getTopology(): Promise<TransactionReceipt>;
  readyForCommittee(params?: TransactionConfig): Promise<TransactionReceipt>;
  readyToSync(params?: TransactionConfig): Promise<TransactionReceipt>;
  voteUnready(subjectAddr: string, expiration: number, params?: TransactionConfig): Promise<TransactionReceipt>;
  setGuardianOrbsAddress(orbsAddress: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  setGuardianIp(ip: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  voteOut(subjectAddr: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  getVoteOutVote(address: string): Promise<string>;
  getAccumulatedStakesForVoteOut(address: string): Promise<BN>;

  setVoteUnreadyTimeoutSeconds(voteOutTimeoutSeconds: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
  setMinSelfStakePercentMille(minSelfStakePercentMille: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
  setVoteOutPercentMilleThreshold(voteOutPercentMilleThreshold: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
  setVoteUnreadyPercentMilleThreshold(voteUnreadyPercentMilleThreshold: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;

  getSettings(params?: TransactionConfig): Promise<[
    number|BN /* minSelfStakePercentMille */,
    number|BN /* voteOutPercentMilleThreshold */,
    number|BN /* banningPercentMilleThreshold */
  ]>;

  getVoteUnreadyTimeoutSeconds(): Promise<number>;
  getMinSelfStakePercentMille(): Promise<number>;
  getVoteUnreadyPercentMilleThreshold(): Promise<number>;
  getVoteOutPercentMilleThreshold(): Promise<number>;

  getVoteOutStatus(subjectAddr: string): Promise<[
    number|BN /* votedStake */,
    number|BN /* totalDelegatedStake */
  ]>;

  getVoteUnreadyStatus(subjectAddr: string): Promise<{
    committee: string[],
    weights: string[],
    votes: boolean[],
    certification: boolean[],
    subjectInCommittee: boolean,
    subjectInCertifiedCommittee: boolean
  }>;

  getEffectiveStake(addr: string): Promise<number>;
}

export interface StakeChangeEvent {
  addr: string;
  selfStake: number | BN;
  delegated_stake: number | BN;
  effective_stake: number | BN;
}

export interface VoteUnreadyCastedEvent {
  voter: string;
  subject: string;
  expiration: number|BN;
}

export interface GuardianVotedUnreadyEvent {
  guardian: string;
}

export interface VoteOutCastedEvent {
  voter: string;
  subject: string;
}

export interface GuardianVotedOutEvent {
  guardian: string;
}

export interface  VoteOutTimeoutSecondsChangedEvent {
  newValue: string|BN,
  oldValue: string|BN,
}

export interface  MinSelfStakePercentMilleChangedEvent {
  newValue: string|BN,
  oldValue: string|BN,
}

export interface  VoteUnreadyPercentMilleThresholdChangedEvent {
  newValue: string|BN,
  oldValue: string|BN,
}

export interface VoteOutPercentMilleThresholdChangedEvent {
  newValue: string|BN,
  oldValue: string|BN,
}
