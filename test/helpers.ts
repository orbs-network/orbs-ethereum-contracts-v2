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

export async function txTimestamp(web3: Web3Driver, r: TransactionReceipt): Promise<number> { // TODO move
    return (await web3.eth.getBlock(r.blockNumber)).timestamp as number;
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

export interface StandbysSnapshot {
    addrs: string[];
    weights: (number | BN)[];
    compliance: boolean[];
}
export async function expectCommitteeStandbysToBe(d: Driver, standbys: Partial<StandbysSnapshot>) {
    const normalize = (standbys: Partial<StandbysSnapshot>) => standbys.weights == null ? standbys : {...standbys, weights: standbys.weights.map(w => new BN(w).toString())};
    const [addrs, weights, compliance] = await d.committee.getStandbys();

    if (standbys.addrs == null) {
        throw new Error("addrs field missing from standbys object")
    }
    const expectedStandbys = transpose(normalize(standbys), "addrs", Object.keys(standbys));
    const actualStandbys = transpose(normalize({addrs, weights, compliance}), "addrs", Object.keys(standbys));

    chai.expect(expectedStandbys).to.deep.equal(actualStandbys);
}
