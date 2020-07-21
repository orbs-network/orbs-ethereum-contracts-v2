import {betaDriverOptions, Driver} from "./test/driver";
import {Contracts} from "./typings/contracts";

async function main() {
    const d = await Driver.new(betaDriverOptions);
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
}

main()
.then(() => process.exit(), (e) => console.error(e));
