import {TransactionReceipt} from "web3-core";

export class GasRecorder {

    private gasByAccount: {[account: string]: number} = {};

    record(txReceipt: TransactionReceipt) {
        const addr = txReceipt.from.toLowerCase();
        this.gasByAccount[addr] = (this.gasByAccount[addr] || 0) + txReceipt.gasUsed;
    }

    gasUsedBy(account: string): number {
        return this.gasByAccount[account.toLowerCase()] || 0;
    }

}
