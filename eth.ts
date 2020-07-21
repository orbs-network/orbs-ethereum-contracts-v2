import Web3 from "web3";
import {compiledContracts} from "./compiled-contracts";
import { Contract as Web3Contract } from "web3-eth-contract";
import BN from "bn.js";
import { Contracts } from "./typings/contracts";
import {TransactionReceipt} from "web3-core";
import {GasRecorder} from "./gas-recorder";
const HDWalletProvider = require("truffle-hdwallet-provider");

export const ETHEREUM_URL = process.env.ETHEREUM_URL || "http://localhost:7545";

const ETHEREUM_MNEMONIC = process.env.ETHEREUM_MNEMONIC || "vanish junk genuine web seminar cook absurd royal ability series taste method identify elevator liquid";

const GAS_PRICE = parseInt(process.env.GAS_PRICE  || '1000000000'); // 1 Gwei
const GAS_PRICE_DEPLOY = parseInt(process.env.GAS_PRICE_DEPLOY  || `${GAS_PRICE}`); // 1 Gwei

export class Web3Session {
     gasRecorder: GasRecorder = new GasRecorder();
}

export const defaultWeb3Provider = () => new Web3(new HDWalletProvider(
    ETHEREUM_MNEMONIC,
    ETHEREUM_URL,
    0,
    400,
    false
));

type ContractEntry = {
    web3Contract : Web3Contract | null;
    name: string
}
export class Web3Driver{
    private web3 : Web3;
    public contracts = new Map<string, ContractEntry>();
    private defaultSession = new Web3Session();

    constructor(private web3Provider : () => Web3 = defaultWeb3Provider){
        this.web3 = this.web3Provider();
    }

    get eth(){
        return this.web3.eth;
    }
    get currentProvider(){
        return this.web3.currentProvider;
    }

    async deploy<N extends keyof Contracts>(contractName: N, args: any[], options?: any, session?: Web3Session) {
        session = session || this.defaultSession;

        const abi = compiledContracts[contractName].abi;
        const accounts = await this.web3.eth.getAccounts();
        let web3Contract;
        let txHash;
        for (let attempt = 0; attempt < 5; attempt++) {
            try {
                web3Contract = await new this.web3.eth.Contract(abi).deploy({
                    data: compiledContracts[contractName].bytecode,
                    arguments: args || []
                }).send({
                    from: accounts[0],
                    gasPrice: GAS_PRICE_DEPLOY,
                    ...(options || {})
                }, (err, _txHash) => {
                    if (!err) {
                        txHash = _txHash;
                    }
                });
            } catch (e) {
                if (/Invalid JSON RPC response/.exec(e.toString())) {
                    this.log(`Failed deploying "${contractName}", retrying`);
                    await new Promise(resolve => setTimeout(resolve, 1000));
                    continue;
                }

                console.log("Failed deploying " + contractName + ": " + e.toString());
                this.refresh();
                throw e;
            }

            this.contracts.set(web3Contract.options.address, {web3Contract, name:contractName})
            this.log("Deployed " + contractName + " at " + web3Contract.options.address);

            const tx = await this.web3.eth.getTransactionReceipt(txHash);
            session.gasRecorder.record(tx);

            return new Contract(this, session, abi, web3Contract.options.address) as Contracts[N];
        }

        throw new Error(`Failed deploying contract ${contractName} after 5 attempts`);
    }

    getExisting<N extends keyof Contracts>(contractName: N, contractAddress: string, session?: Web3Session) {
        session = session || this.defaultSession;
        const abi = compiledContracts[contractName].abi;
        const web3Contract = new this.web3.eth.Contract(abi, contractAddress);
        this.contracts.set(web3Contract.options.address, {web3Contract, name:contractName});
        return new Contract(this, session, abi, web3Contract.options.address) as Contracts[N];
    }

    async txTimestamp(r: TransactionReceipt): Promise<number> {
        for (let attempt = 0; attempt < 5; attempt++) {
            const block = await this.eth.getBlock(r.blockNumber);
            if (block != null ) {
                return block.timestamp as number;
            }
            console.log(`web3.eth.getBlock returned null for block ${r.blockNumber}, retrying..`);
        }

        throw new Error("web3.eth.getBlock failed after 5 attempts");
    }

    getContract(address: string){
        const entry = this.contracts.get(address);
        if (!entry){
            throw new Error(`did not find contract entry for contract ${address}`);
        }
        const contract = entry.web3Contract || new this.web3.eth.Contract(compiledContracts[entry.name].abi, address);
        entry.web3Contract = contract;
        return contract;
    }

    refresh(){
        this.web3 = this.web3Provider();
        for (const entry of this.contracts.values()){
            entry.web3Contract = null;
        }
    }

    log(s: string) {
        if (process.env.WEB3_DRIVER_VERBOSE) {
            console.log(s);
        }
    }

}

export class Contract {

    constructor(public web3: Web3Driver, private session: Web3Session, abi: any, public address: string) {
        Object.keys(this.web3Contract.methods)
            .filter(x => x[0] != '0')
            .forEach(m => {
                this[m] = function () {
                    return this.callContractMethod(m, abi.find(x => x.name == m), Array.from(arguments));
                };
                this[m].bind(this);
            })
    }

    get web3Contract(): Web3Contract {
        return this.web3.getContract(this.address);
    }

    private async callContractMethod(method: string, methodAbi, args: any[]) {
        this.web3.log(`calling method: ${method}`);

        const accounts = await this.web3.eth.getAccounts();
        let opts = {};
        if (args.length > 0 && JSON.stringify(args[args.length - 1])[0] == '{') {
            opts = args.pop();
        }
        args = args.map(x => BN.isBN(x) ? x.toString() : Array.isArray(x) ? x.map(_x => BN.isBN(_x) ? _x.toString() : _x) : x);
        const action = methodAbi.stateMutability == "view" ? "call" : "send";
        for (let attempt = 0; attempt < 5; attempt++) {
            let ret;
            try {
                ret = await this.web3Contract.methods[method](...args)[action]({
                    from: accounts[0],
                    gasPrice: GAS_PRICE,
                    gas: 10000000,
                    ...opts
                });
            } catch(e) {
                this.web3.log(`error calling ${method}: ${e.toString()}`);
                if (/Invalid JSON RPC response/.exec(e.toString())) {
                    this.web3.log(`Calling contract method "${method}" failed, retrying`);
                    await new Promise(resolve => setTimeout(resolve, 1000));
                    continue;
                }
                this.web3.refresh();
                throw e;
            }
            if (action == "send") {
                this.session.gasRecorder.record(ret);
            }
            return ret;
        }

        throw new Error(`Calling contract method "${method}" failed after 5 attempts`);
    }
}
