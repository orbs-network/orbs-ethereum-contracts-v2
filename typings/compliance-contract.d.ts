import {TransactionConfig, TransactionReceipt} from "web3-core";
import {Contract} from "../eth";

export interface ValidatorConformanceUpdateEvent {
  validator: string,
  conformanceType: string
}

export interface ComplianceContract extends Contract {
  getValidatorCompliance(validator: string, params?: TransactionConfig): Promise<string>;
  setValidatorCompliance(validator: string, complianceType: string, params?: TransactionConfig): Promise<TransactionReceipt>;
  setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;

}
