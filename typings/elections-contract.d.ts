import {Contract} from "../eth";
import {TransactionConfig, TransactionReceipt} from "web3-core";
import * as BN from "bn.js";
import {OwnedContract} from "./base-contract";

export interface ElectionsContract extends OwnedContract {
  registerGuardian( ip: string, orbsAddrs: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  getTopology(): Promise<TransactionReceipt>;
  readyForCommittee(params?: TransactionConfig): Promise<TransactionReceipt>;
  readyToSync(params?: TransactionConfig): Promise<TransactionReceipt>;
  voteUnready(subjectAddr: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  setGuardianOrbsAddress(orbsAddress: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  setGuardianIp(ip: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  voteOut(subjectAddr: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  getVoteOutVote(address: string): Promise<string>;
  getAccumulatedStakesForVoteOut(address: string): Promise<BN>;

  setVoteUnreadyTimeoutSeconds(voteOutTimeoutSeconds: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
  setMinSelfStakePercentMille(minSelfStakePercentMille: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
  setVoteOutPercentageThreshold(voteOutPercentageThreshold: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
  setVoteUnreadyPercentageThreshold(voteUnreadyPercentageThreshold: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;

  getSettings(params?: TransactionConfig): Promise<[
    number|BN /* voteOutTimeoutSeconds */,
    number|BN /* minSelfStakePercentMille */,
    number|BN /* voteOutPercentageThreshold */,
    number|BN /* banningPercentageThreshold */
  ]>;

  getVoteUnreadyTimeoutSeconds(): Promise<number>;
  getMinSelfStakePercentMille(): Promise<number>;
  getVoteUnreadyPercentageThreshold(): Promise<number>;
  getVoteOutPercentageThreshold(): Promise<number>;
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

export interface  VoteUnreadyPercentageThresholdChangedEvent {
  newValue: string|BN,
  oldValue: string|BN,
}

export interface VoteOutPercentageThresholdChangedEvent {
  newValue: string|BN,
  oldValue: string|BN,
}
