import Web3 from "web3";
import BN from "bn.js";
import * as _ from "lodash";
import { Web3Driver } from "../eth";
import {Driver} from "./driver";
import {TransactionReceipt} from "web3-core";
import chai from "chai";

export const retry = (n: number, f: () => Promise<void>) => async  () => {
    for (let i = 0; i < n; i++) {
        await f();
    }
};

export const evmIncreaseTimeForQueries = async (web3: Web3Driver, seconds: number) => {
    await evmIncreaseTime(web3, seconds);
    evmMine(web3, 1); // "bake" the new clock in by closing 1 block
};

export const evmIncreaseTime = async (web3: Web3Driver, seconds: number) => new Promise(
    (resolve, reject) =>
        (web3.currentProvider as any).send(
            {method: "evm_increaseTime", params: [seconds]},
            (err, res) => err ? reject(err) : resolve(res)
        )
);

export const evmMine = async (web3: Web3Driver, blocks: number) => Promise.all(_.range(blocks).map(() => new Promise(
    (resolve, reject) =>
        (web3.currentProvider as any).send(
            {method: "evm_mine", params: []},
            (err, res) => err ? reject(err) : resolve(res)
        )
)));

export function bn(x: string|BN|number|Array<string|BN|number>) {
    if (Array.isArray(x)) {
        return x.map(n => bn(n))
    }
    return new BN(x);
}


export function minAddress(addrs: string[]): string {
    const toBn = addr => new BN(addr.slice(2), 16);
    const minBn = addrs
        .map(toBn)
        .reduce((m, x) => BN.min(m, x), toBn(addrs[0]));
    return addrs.find(addr => toBn(addr).eq(minBn)) as string
}

export async function getTopBlockTimestamp(d: Driver) : Promise<number> {
    return new Promise(
        (resolve, reject) =>
            d.web3.eth.getBlock(
                "latest",
                (err, block: any) =>
                    err ? reject(err): resolve(block.timestamp)
            )
    );
}

export function fromTokenUnits(n: (number|BN)): BN {
    return bn(n).mul(bn("1000000000000000"));
}

export function toTokenUnits(n: (number|BN)): BN {
    return bn(n).div(bn("1000000000000000"));
}

export function bnSum(ns: BN[]): BN {
    return ns.reduce((x, y) => x.add(y), bn(0));
}

export function transpose(obj, key, fields?) {
    if (Object.keys(obj || {}).length == 0) {
        return {}
    }
    const transposed: {[key: string]: any} = {};
    const n = _.values(obj)[0].length;
    fields = fields || Object.keys(obj);
    for (let i = 0; i < n; i++) {
        const item = {};
        for (let k of fields) {
            item[k] = obj[k][i];
        }
        transposed[item[key]] = item;
    }
    return transposed;
}

const expect = chai.expect;

export async function expectRejected(promise: Promise<any>, expectedErrorMsg: RegExp) {
    try {
        await promise;
    } catch (err) {
        expect(err.toString()).to.match(expectedErrorMsg);
        return
    }
    throw new Error("expected promise to reject")
}

