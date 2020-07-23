import {betaDriverOptions, Driver} from "./test/driver";
import {Contracts} from "./typings/contracts";

async function printGetters(contractName, contract) {
    for (let k of Object.keys(contract)) {
        if (k.startsWith("get") && typeof contract[k] === "function") {
            try {
                const res = await contract[k]();
                console.log(contractName, k, "=>>", JSON.stringify(res));
            } catch (e) {
            }
        }
    }
}

async function main() {
    // const d = await Driver.new(betaDriverOptions);
    const d = await Driver.new({
        ...betaDriverOptions,

        // PreDeployedContracts
        contractRegistryAddress: "0x10bFdCc77E998Eb849a18c79b880F8b9BE06Ad83",
        delegationsAddress: "0xBb5B5E9333e155cad6fe299B18dED3F4107EF294",
        rewardsAddress: "0x16De66Ca1135a997f17679c0CdF09d49223F5B20",
        electionsAddress: "0xdA393f62303Ce1396D6F425cd7e85b60DaC8233e",
        subscriptionsAddress: "0x3b2C72d0D5FC8A7346091f449487CD0A7F0954d6",
        protocolAddress: "0xF6Cc041e1bb8C1431D419Bb88424324Af5Dd7866",
        certificationAddress: "0x47c4AE9ceFb30AFBA85da9c2Fcd3125480770D9b",
        committeeAddress: "0xBFB2bAC25daAabf79e5c94A8036b28c553ee75F5",
        stakingRewardsWalletAddress: "0x7381179C5FdF9d509a9749e684fa58604E670F11",
        bootstrapRewardsWalletAddress: "0xE4893F34d3F1cB45bfF426624A2dC938D132cd7b",
        guardiansRegistrationAddress: "0xd095e7310616376BDeD74Afc7e0400E6d0894E6F",
    });
    // const d = await Driver.new();
    // const accounts = [d.accounts[0], d.accounts[1], d.accounts[2]];
    // for (const acc of accounts) {
    //     console.log(await d.web3.eth.getBalance(acc))
    // }

    // d.logGasUsageSummary("deployment");

    console.log("elections", d.elections.address);
    console.log("erc20", d.erc20.address);
    console.log("externalToken", d.externalToken.address);
    console.log("staking", d.staking.address);
    console.log("delegations", d.delegations.address);
    console.log("subscriptions", d.subscriptions.address);
    console.log("rewards", d.rewards.address);
    console.log("protocol", d.protocol.address);
    console.log("certification", d.certification.address);
    console.log("guardiansRegistration", d.guardiansRegistration.address);
    console.log("committee", d.committee.address);
    console.log("stakingRewardsWallet", d.stakingRewardsWallet.address);
    console.log("bootstrapRewardsWallet", d.bootstrapRewardsWallet.address);
    console.log("contractRegistry", d.contractRegistry.address);
    console.log("monthlySubscriptionPlan", d.subscribers[0].address);

    console.log("\n\n**************************** contract getters: ****************************\n\n");
    await printGetters("elections", d.elections);
    await printGetters("erc20", d.erc20);
    await printGetters("externalToken", d.externalToken);
    await printGetters("staking", d.staking);
    await printGetters("delegations", d.delegations);
    await printGetters("subscriptions", d.subscriptions);
    await printGetters("rewards", d.rewards);
    await printGetters("protocol", d.protocol);
    await printGetters("certification", d.certification);
    await printGetters("guardiansRegistration", d.guardiansRegistration);
    await printGetters("committee", d.committee);
    await printGetters("stakingRewardsWallet", d.stakingRewardsWallet);
    await printGetters("bootstrapRewardsWallet", d.bootstrapRewardsWallet);
    await printGetters("contractRegistry", d.contractRegistry);
    await printGetters("monthlySubscriptionPlan", d.subscribers[0]);
}

main()
.then(() => process.exit(), (e) => console.error(e));
