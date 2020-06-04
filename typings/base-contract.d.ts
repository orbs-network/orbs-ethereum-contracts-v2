import {Contract} from "../eth";
import {TransactionConfig, TransactionReceipt} from "web3-core";

export interface OwnedContract extends Contract {
    transferFunctionalOwnership(newOwner: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    claimFunctionalOwnership(params?: TransactionConfig): Promise<TransactionReceipt>;
    transferMigrationOwnership(newOwner: string, params?: TransactionConfig): Promise<TransactionReceipt>;
    claimMigrationOwnership(params?: TransactionConfig): Promise<TransactionReceipt>;

    setContractRegistry(address: string, params?: TransactionConfig): Promise<TransactionReceipt>;
}
