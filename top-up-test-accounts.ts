import {defaultWeb3Provider} from "./eth";
import {bn} from "./test/helpers";

async function main() {
    const web3 = defaultWeb3Provider();
    const accounts = await web3.eth.getAccounts();
    accounts.slice(1,10).forEach(a => console.log(a));
    await Promise.all(accounts.slice(1, 20).map(to => web3.eth.sendTransaction({to, from: accounts[0], value: web3.utils.toWei("0.2", "ether")})))
}

async function collect() {
    const web3 = defaultWeb3Provider();
    const accounts = await web3.eth.getAccounts();
    for (let from of accounts.slice(1, 20)) {
        const amount = bn(await web3.eth.getBalance(from)).sub(bn(web3.utils.toWei("0.1", "ether")));
        console.log(`Transfer amount of ${from} is ${amount} wei`);
        if (amount.gt(bn(0))) {
            await web3.eth.sendTransaction({to: accounts[0], from, value: amount});
        }

    }
}

main().catch(e => console.error(e));
// collect().catch(e => console.error(e));
