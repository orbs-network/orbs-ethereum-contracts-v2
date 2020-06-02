import {TransactionConfig, TransactionReceipt} from "web3-core";
import {Contract} from "../eth";
import {OwnedContract} from "./base-contract";

export interface ValidatorComplianceUpdateEvent {
  validator: string,
  isCompliant: boolean;
}

export interface ComplianceContract extends OwnedContract {
  isValidatorCompliant(validator: string, params?: TransactionConfig): Promise<boolean>;
  setValidatorCompliance(validator: string, isCompliant: boolean, params?: TransactionConfig): Promise<TransactionReceipt>;
  setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;

}
