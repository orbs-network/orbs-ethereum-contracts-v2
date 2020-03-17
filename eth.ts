import Web3 from "web3";
import {compiledContracts} from "./compiled-contracts";
import { Contract as Web3Contract } from "web3-eth-contract";
import BN from "bn.js";
import { Contracts } from "./typings/contracts";
const HDWalletProvider = require("truffle-hdwallet-provider");

export const ETHEREUM_URL = process.env.ETHEREUM_URL || "http://localhost:7545";
const ETHEREUM_MNEMONIC = process.env.ETHEREUM_MNEMONIC || "vanish junk genuine web seminar cook absurd royal ability series taste method identify elevator liquid";

export const defaultWeb3Provider = () => new Web3(new HDWalletProvider(
    ETHEREUM_MNEMONIC,
    ETHEREUM_URL,
    0,
    100,
    false
    ));

export class Web3Driver{
    private web3 : Web3;
    private refreshCount = 0;
    constructor(private web3Provider : () => Web3 = defaultWeb3Provider){
        this.web3 = this.web3Provider();
    }

    get eth(){
        return this.web3.eth;
    }
    get currentProvider(){
        return this.web3.currentProvider;
    }

    async deploy<N extends keyof Contracts>(contractName: N, args: any[], options?: any) {
        try {
            const abi = compiledContracts[contractName].abi;
            const accounts = await this.web3.eth.getAccounts();
            let web3Contract = await new this.web3.eth.Contract(abi).deploy({
                data: compiledContracts[contractName].bytecode,
                arguments: args || []
            }).send({
                from: accounts[0],
                ...(options || {})
            });
            let lastNonce = this.refreshCount;
            const web3ContractProvider = () => {
                if (this.refreshCount != lastNonce){
                    web3Contract = new this.web3.eth.Contract(abi, web3Contract.options.address);
                    lastNonce = this.refreshCount;
                }
                return web3Contract;
            }
            return new Contract(this, abi, web3ContractProvider) as Contracts[N];
        } catch (e) {
            this.refresh();
            throw e;
        }
    }
    
    refresh(){
        this.web3 = this.web3Provider();
        this.refreshCount++;
    }
}

export class Contract {

    constructor(public web3: Web3Driver, abi: any, public web3ContractProvider: ()=>Web3Contract) {
        Object.keys(web3ContractProvider().methods)
            .filter(x => x[0] != '0')
            .forEach(m => {
                this[m] = function () {
                    return this.callContractMethod(m, abi.find(x => x.name == m), Array.from(arguments));
                };
                this[m].bind(this);
            })
    }

    get address(): string {
        return this.web3Contract.options.address;
    }

    get web3Contract(): Web3Contract {
        return this.web3ContractProvider();
    }

    private async callContractMethod(method: string, methodAbi, args: any[]) {
        const accounts = await this.web3.eth.getAccounts();
        let opts = {};
        if (args.length > 0 && JSON.stringify(args[args.length - 1])[0] == '{') {
            opts = args.pop();
        }
        args = args.map(x => BN.isBN(x) ? x.toString() : Array.isArray(x) ? x.map(_x => BN.isBN(_x) ? _x.toString() : _x) : x);
        const action = methodAbi.stateMutability == "view" ? "call" : "send";
        try {
            const ret = await this.web3Contract.methods[method](...args)[action]({
                from: accounts[0],
                gas: 6700000,
                ...opts
            }); // if we return directly, it will not throw the exceptions but return a rejected promise
            return ret;
        } catch(e) {
            this.web3.refresh();
            throw e;
        }
    }
}