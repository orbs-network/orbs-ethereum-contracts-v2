import {Contract} from "../eth";
import {TransactionConfig, TransactionReceipt} from "web3-core";
import * as BN from "bn.js";

export interface ElectionsContract extends Contract {
  registerValidator( ip: string, orbsAddrs: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  getTopology(): Promise<TransactionReceipt>;
  notifyReadyForCommittee(params?: TransactionConfig): Promise<TransactionReceipt>;
  notifyReadyToSync(params?: TransactionConfig): Promise<TransactionReceipt>;
  voteOut(address: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  setValidatorOrbsAddress(orbsAddress: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  setValidatorIp(ip: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  setBanningVotes(address: string[], params?: TransactionConfig): Promise<TransactionReceipt>;
  refreshBanningVote(voter: string, against: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  getBanningVotes(address: string): Promise<string[]>;
  getAccumulatedStakesForBanning(address: string): Promise<BN>;
  getTotalGovernanceStake(): Promise<BN>;
}

export interface TopologyChangedEvent {
  orbsAddrs: string[];
  ips: string[];
}

export interface ValidatorRegisteredEvent_deprecated {
  addr: string;
  ip: string;
}

export interface StakeChangeEvent {
  addr: string;
  ownStake: number | BN;
  uncappedStake: number | BN;
  governanceStake: number | BN;
  committeeStake: number | BN;
}

export interface VoteOutEvent {
  voter: string;
  against: string;
}

export interface VotedOutOfCommitteeEvent {
  addr: string;
}

export interface BanningVoteEvent {
  voter: string;
  against: string[];
}

export interface BannedEvent {
  validator: string;
}

export interface UnbannedEvent {
  validator: string;
}
