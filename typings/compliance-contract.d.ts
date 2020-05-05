import {TransactionConfig, TransactionReceipt} from "web3-core";
import {Contract} from "../eth";

export type ComplianceType = "Compliance" | "General";

export interface ValidatorComplianceUpdateEvent {
  validator: string,
  complianceType: ComplianceType;
}

export interface ComplianceContract extends Contract {
  getValidatorCompliance(validator: string, params?: TransactionConfig): Promise<ComplianceType>;
  setValidatorCompliance(validator: string, complianceType: ComplianceType, params?: TransactionConfig): Promise<TransactionReceipt>;
  setContractRegistry(contractRegistry: string, params?: TransactionConfig): Promise<TransactionReceipt>;

}
