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
        delegationAddress: "0xBb5B5E9333e155cad6fe299B18dED3F4107EF294",
        rewardsAddress: "0x16De66Ca1135a997f17679c0CdF09d49223F5B20",
    });
    // const d = await Driver.new();
    // const accounts = [d.accounts[0], d.accounts[1], d.accounts[2]];
    // for (const acc of accounts) {
    //     console.log(await d.web3.eth.getBalance(acc))
    // }

    // d.logGasUsageSummary("deployment");

    console.log("elections", d.elections.address);
    console.log("erc20", d.erc20.address);
    console.log("externalToken", d.bootstrapToken.address);
    console.log("staking", d.staking.address);
    console.log("delegations", d.delegation.address);
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
    await printGetters("externalToken", d.bootstrapToken);
    await printGetters("staking", d.staking);
    await printGetters("delegations", d.delegation);
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
