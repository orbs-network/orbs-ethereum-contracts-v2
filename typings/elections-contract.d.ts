import {Contract} from "../eth";
import {TransactionConfig, TransactionReceipt} from "web3-core";
import * as BN from "bn.js";
import {OwnedContract} from "./base-contract";

export interface ElectionsContract extends OwnedContract {
  registerValidator( ip: string, orbsAddrs: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  getTopology(): Promise<TransactionReceipt>;
  readyForCommittee(params?: TransactionConfig): Promise<TransactionReceipt>;
  readyToSync(params?: TransactionConfig): Promise<TransactionReceipt>;
  voteUnready(subjectAddr: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  setValidatorOrbsAddress(orbsAddress: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  setValidatorIp(ip: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  voteOut(address: string[], params?: TransactionConfig): Promise<TransactionReceipt>;
  getVoteOutVotes(address: string): Promise<string[]>;
  getAccumulatedStakesForBanning(address: string): Promise<BN>;

  setVoteUnreadyTimeoutSeconds(voteOutTimeoutSeconds: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
  setMaxDelegationRatio(maxDelegationRatio: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
  setVoteOutLockTimeoutSeconds(voteOutLockTimeoutSeconds: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
  setVoteOutPercentageThreshold(voteOutPercentageThreshold: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;
  setVoteUnreadyPercentageThreshold(voteUnreadyPercentageThreshold: number|BN, params?: TransactionConfig): Promise<TransactionReceipt>;

  getSettings(params?: TransactionConfig): Promise<[
    number|BN /* voteOutTimeoutSeconds */,
    number|BN /* maxDelegationRatio */,
    number|BN /* banningLockTimeoutSeconds */,
    number|BN /* voteOutPercentageThreshold */,
    number|BN /* banningPercentageThreshold */
  ]>;

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

export interface ValidatorVotedUnreadyEvent {
  validator: string;
}

export interface VoteOutCastedEvent {
  voter: string;
  subjects: string[];
}

export interface ValidatorVotedOutEvent {
  validator: string;
}

export interface ValidatorVotedInEvent {
  validator: string;
}

export interface  VoteOutTimeoutSecondsChangedEvent {
  newValue: string|BN,
  oldValue: string|BN,
}

export interface  MaxDelegationRatioChangedEvent {
  newValue: string|BN,
  oldValue: string|BN,
}

export interface  VoteOutLockTimeoutSecondsChangedEvent {
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
