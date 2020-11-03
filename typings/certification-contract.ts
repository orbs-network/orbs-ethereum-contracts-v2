import {TransactionConfig, TransactionReceipt} from "web3-core";
import {Contract} from "../eth";
import {ManagedContract} from "./base-contract";

export interface GuardianCertificationUpdateEvent {
  guardian: string,
  isCertified: boolean;
}

export interface CertificationContract extends ManagedContract {
  isGuardianCertified(guardian: string, params?: TransactionConfig): Promise<boolean>;
  setGuardianCertification(guardian: string, isCertified: boolean, params?: TransactionConfig): Promise<TransactionReceipt>;
  setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;

}
