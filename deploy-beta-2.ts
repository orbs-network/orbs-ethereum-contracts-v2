import {DEPLOYMENT_SUBSET_MAIN,ZERO_ADDR} from "./test/driver";
import {Web3Driver} from "./eth";
import {bn} from "./test/helpers";
import Web3 from "web3";


export const options = {
    // Committee
    maxCommitteeSize: 22,
    maxTimeBetweenRewardAssignments: 2*24*60*60,

    // Elections
    minSelfStakePercentMille : 8000,
    voteUnreadyThresholdPercentMille : 70 * 1000,
    voteOutThresholdPercentMille : 70 * 1000,

    // Rewards
    generalCommitteeAnnualBootstrap: bn(12).mul(bn(10).pow(bn(18))),
    certifiedCommitteeAnnualBootstrap: bn(6).mul(bn(10).pow(bn(18))),
    stakingRewardsAnnualRateInPercentMille: 12000,
    stakingRewardsAnnualCap: bn(12000).mul(bn(10).pow(bn(18))),
    defaultDelegatorsStakingRewardsPercentMille: 66667,
    maxDelegatorsStakingRewardsPercentMille: 66667,

    // Protocol wallets
    stakingRewardsWalletRate: bn(12000 * 1.1).mul(bn(10).pow(bn(18))), // staking rewards for entire committee + 10%
    bootstrapRewardsWalletRate: bn((12 + 6) * 22).mul(bn(10).pow(bn(18))).mul(bn(11)).div(bn(10)), // bootstrap rewards for both certified and general, for entire committee + 10%

    // Subscription plan
    subscriptionTier: "beta1",
    subscriptionRate: bn(100).mul(bn(10).pow(bn(18))),

    genesisRefTimeDelay: bn(3*60*60),

    orbsTokenAddress: "0xff56Cc6b1E6dEd347aA0B7676C85AB0B3D08B0FA",
    bootstrapTokenAddress: "0x6b175474e89094c44da98b954eedeac495271d0f",
    stakingContractAddress: "0x01D59Af68E2dcb44e04C50e05F62E7043F2656C3",

    previousGuardianRegistrationContractAddr: "0xd095e7310616376BDeD74Afc7e0400E6d0894E6F",

    existingContractsToLock: [
        "0xdA393f62303Ce1396D6F425cd7e85b60DaC8233e", // elections
        "0x3b2C72d0D5FC8A7346091f449487CD0A7F0954d6", // subscriptions
        "0xF6Cc041e1bb8C1431D419Bb88424324Af5Dd7866", // protocol
        "0x47c4AE9ceFb30AFBA85da9c2Fcd3125480770D9b", // certification
        "0xd095e7310616376BDeD74Afc7e0400E6d0894E6F", // registration
        "0xBFB2bAC25daAabf79e5c94A8036b28c553ee75F5", // committee
        "0x16De66Ca1135a997f17679c0CdF09d49223F5B20", // rewards
        "0xBb5B5E9333e155cad6fe299B18dED3F4107EF294", // delegations
    ],

    minimumInitialVcPayment: 0,
};

const oldGuardianRegistrationABI = [{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"addr","type":"address"}],"name":"ContractRegistryAddressUpdated","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"previousFunctionalOwner","type":"address"},{"indexed":true,"internalType":"address","name":"newFunctionalOwner","type":"address"}],"name":"FunctionalOwnershipTransferred","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"addr","type":"address"},{"indexed":false,"internalType":"bytes4","name":"ip","type":"bytes4"},{"indexed":false,"internalType":"address","name":"orbsAddr","type":"address"},{"indexed":false,"internalType":"string","name":"name","type":"string"},{"indexed":false,"internalType":"string","name":"website","type":"string"},{"indexed":false,"internalType":"string","name":"contact","type":"string"}],"name":"GuardianDataUpdated","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"addr","type":"address"},{"indexed":false,"internalType":"string","name":"key","type":"string"},{"indexed":false,"internalType":"string","name":"newValue","type":"string"},{"indexed":false,"internalType":"string","name":"oldValue","type":"string"}],"name":"GuardianMetadataChanged","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"addr","type":"address"}],"name":"GuardianRegistered","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"addr","type":"address"}],"name":"GuardianUnregistered","type":"event"},{"anonymous":false,"inputs":[],"name":"Locked","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"previousMigrationOwner","type":"address"},{"indexed":true,"internalType":"address","name":"newMigrationOwner","type":"address"}],"name":"MigrationOwnershipTransferred","type":"event"},{"anonymous":false,"inputs":[],"name":"Unlocked","type":"event"},{"constant":false,"inputs":[],"name":"claimFunctionalOwnership","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":false,"inputs":[],"name":"claimMigrationOwnership","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[],"name":"functionalOwner","outputs":[{"internalType":"address","name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"getBootstrapRewardsWallet","outputs":[{"internalType":"contract IProtocolWallet","name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"getCertificationContract","outputs":[{"internalType":"contract ICertification","name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"getCommitteeContract","outputs":[{"internalType":"contract ICommittee","name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"getDelegationsContract","outputs":[{"internalType":"contract IDelegations","name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"getElectionsContract","outputs":[{"internalType":"contract IElections","name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[{"internalType":"address[]","name":"orbsAddrs","type":"address[]"}],"name":"getEthereumAddresses","outputs":[{"internalType":"address[]","name":"ethereumAddrs","type":"address[]"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[{"internalType":"address","name":"addr","type":"address"}],"name":"getGuardianData","outputs":[{"internalType":"bytes4","name":"ip","type":"bytes4"},{"internalType":"address","name":"orbsAddr","type":"address"},{"internalType":"string","name":"name","type":"string"},{"internalType":"string","name":"website","type":"string"},{"internalType":"string","name":"contact","type":"string"},{"internalType":"uint256","name":"registration_time","type":"uint256"},{"internalType":"uint256","name":"last_update_time","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[{"internalType":"address","name":"addr","type":"address"}],"name":"getGuardianIp","outputs":[{"internalType":"bytes4","name":"ip","type":"bytes4"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[{"internalType":"address[]","name":"addrs","type":"address[]"}],"name":"getGuardianIps","outputs":[{"internalType":"bytes4[]","name":"ips","type":"bytes4[]"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[{"internalType":"address[]","name":"addrs","type":"address[]"}],"name":"getGuardiansOrbsAddress","outputs":[{"internalType":"address[]","name":"orbsAddrs","type":"address[]"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"getGuardiansRegistrationContract","outputs":[{"internalType":"contract IGuardiansRegistration","name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[{"internalType":"address","name":"addr","type":"address"},{"internalType":"string","name":"key","type":"string"}],"name":"getMetadata","outputs":[{"internalType":"string","name":"","type":"string"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[{"internalType":"address[]","name":"ethereumAddrs","type":"address[]"}],"name":"getOrbsAddresses","outputs":[{"internalType":"address[]","name":"orbsAddrs","type":"address[]"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"getProtocolContract","outputs":[{"internalType":"contract IProtocol","name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"getRewardsContract","outputs":[{"internalType":"contract IRewards","name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"getStakingContract","outputs":[{"internalType":"contract IStakingContract","name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"getStakingRewardsWallet","outputs":[{"internalType":"contract IProtocolWallet","name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"getSubscriptionsContract","outputs":[{"internalType":"contract ISubscriptions","name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[{"internalType":"address","name":"","type":"address"},{"internalType":"string","name":"","type":"string"}],"name":"guardianMetadata","outputs":[{"internalType":"string","name":"","type":"string"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"guardians","outputs":[{"internalType":"address","name":"orbsAddr","type":"address"},{"internalType":"bytes4","name":"ip","type":"bytes4"},{"internalType":"string","name":"name","type":"string"},{"internalType":"string","name":"website","type":"string"},{"internalType":"string","name":"contact","type":"string"},{"internalType":"uint256","name":"registrationTime","type":"uint256"},{"internalType":"uint256","name":"lastUpdateTime","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[{"internalType":"bytes4","name":"","type":"bytes4"}],"name":"ipToGuardian","outputs":[{"internalType":"address","name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"isFunctionalOwner","outputs":[{"internalType":"bool","name":"","type":"bool"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"isMigrationOwner","outputs":[{"internalType":"bool","name":"","type":"bool"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[{"internalType":"address","name":"addr","type":"address"}],"name":"isRegistered","outputs":[{"internalType":"bool","name":"","type":"bool"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[],"name":"lock","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[],"name":"locked","outputs":[{"internalType":"bool","name":"","type":"bool"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[],"name":"migrationOwner","outputs":[{"internalType":"address","name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"orbsAddressToEthereumAddress","outputs":[{"internalType":"address","name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[{"internalType":"bytes4","name":"ip","type":"bytes4"},{"internalType":"address","name":"orbsAddr","type":"address"},{"internalType":"string","name":"name","type":"string"},{"internalType":"string","name":"website","type":"string"},{"internalType":"string","name":"contact","type":"string"}],"name":"registerGuardian","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":false,"inputs":[],"name":"renounceFunctionalOwnership","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":false,"inputs":[],"name":"renounceMigrationOwnership","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[{"internalType":"address","name":"ethereumOrOrbsAddress","type":"address"}],"name":"resolveGuardianAddress","outputs":[{"internalType":"address","name":"ethereumAddress","type":"address"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[{"internalType":"contract IContractRegistry","name":"_contractRegistry","type":"address"}],"name":"setContractRegistry","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":false,"inputs":[{"internalType":"string","name":"key","type":"string"},{"internalType":"string","name":"value","type":"string"}],"name":"setMetadata","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":false,"inputs":[{"internalType":"address","name":"newFunctionalOwner","type":"address"}],"name":"transferFunctionalOwnership","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":false,"inputs":[{"internalType":"address","name":"newMigrationOwner","type":"address"}],"name":"transferMigrationOwnership","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":false,"inputs":[],"name":"unlock","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":false,"inputs":[],"name":"unregisterGuardian","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":false,"inputs":[{"internalType":"bytes4","name":"ip","type":"bytes4"},{"internalType":"address","name":"orbsAddr","type":"address"},{"internalType":"string","name":"name","type":"string"},{"internalType":"string","name":"website","type":"string"},{"internalType":"string","name":"contact","type":"string"}],"name":"updateGuardian","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":false,"inputs":[{"internalType":"bytes4","name":"ip","type":"bytes4"}],"name":"updateGuardianIp","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"}]

async function listGuardians(guardianRegistrationContractAddr: string): Promise<string[]> {
    const web3 = new Web3(new Web3.providers.HttpProvider("https://mainnet.infura.io/v3/62f4815d28674debbe4703c5eb9d413c"))
    const contract = new web3.eth.Contract(oldGuardianRegistrationABI as any, guardianRegistrationContractAddr);
    const events = await contract.getPastEvents("allEvents", {
        fromBlock: "earliest",
        toBlock: "latest",
    });
    let guardians: string[] = [];
    for (const e of events) {
        if (e.event == "GuardianRegistered") {
            guardians.push(e.returnValues.addr as string)
        }
        if (e.event == "GuardianUnregistered") {
            guardians = guardians.filter(addr => addr != e.returnValues.addr)
        }
    }

    console.log("Following guardians will be migrated:", guardians);
    return guardians;
}

async function lockExistingContracts(web3: Web3Driver, contractsToLock: string[], migrationManager: string) {
    for (const addr of contractsToLock) {
        console.log('Locking contract:', addr);
        const contract = web3.getExisting("Lockable" as any, addr);
        await contract.lock({from: migrationManager});
    }
}

async function deploy() {
    const web3 = new Web3Driver();

    console.log("listing guardians...");
    const guardiansToMigrate = await listGuardians(options.previousGuardianRegistrationContractAddr);

    const accounts = await web3.eth.getAccounts();

    const initManager = accounts[0];
    const registryAdmin = accounts[1];
    const migrationManager = accounts[2];
    const functionalManager = accounts[3];

    await lockExistingContracts(web3, options.existingContractsToLock, accounts[0])

    console.log("Done locking contracts");

    const contractRegistry = await web3.deploy('ContractRegistry', [ZERO_ADDR, registryAdmin]);
    const delegations = await web3.deploy("Delegations", [contractRegistry.address, registryAdmin]);
    const externalToken = await web3.deploy('TestingERC20', []);
    const erc20 = await web3.deploy('TestingERC20', []);
    const stakingContractHandler = await web3.deploy('StakingContractHandler', [contractRegistry.address, registryAdmin]);
    const rewards = await web3.deploy('Rewards', [contractRegistry.address, registryAdmin, erc20.address, externalToken.address,
            options.generalCommitteeAnnualBootstrap,
            options.certifiedCommitteeAnnualBootstrap,
            options.stakingRewardsAnnualRateInPercentMille,
            options.stakingRewardsAnnualCap,
            options.defaultDelegatorsStakingRewardsPercentMille,
            options.maxDelegatorsStakingRewardsPercentMille,
            ZERO_ADDR,
            []
        ]);
    const elections = await web3.deploy("Elections", [contractRegistry.address, registryAdmin, options.minSelfStakePercentMille, options.voteUnreadyThresholdPercentMille, options.voteOutThresholdPercentMille]);
    const subscriptions = await web3.deploy('Subscriptions', [contractRegistry.address, registryAdmin, erc20.address, options.genesisRefTimeDelay || 3*60*60, options.minimumInitialVcPayment, [], ZERO_ADDR]);
    const protocol = await web3.deploy('Protocol', [contractRegistry.address, registryAdmin]);
    const certification = await web3.deploy('Certification', [contractRegistry.address, registryAdmin]);
    const committee = await web3.deploy('Committee', [contractRegistry.address, registryAdmin, options.maxCommitteeSize, options.maxTimeBetweenRewardAssignments]);
    const stakingRewardsWallet = await web3.deploy('ProtocolWallet', [erc20.address, rewards.address, options.stakingRewardsWalletRate]);
    const bootstrapRewardsWallet = await web3.deploy('ProtocolWallet', [externalToken.address, rewards.address, options.bootstrapRewardsWalletRate]);
    const guardiansRegistration = await web3.deploy('GuardiansRegistration', [contractRegistry.address, registryAdmin, options.previousGuardianRegistrationContractAddr, guardiansToMigrate]);
    const generalFeesWallet = await web3.deploy('FeesWallet', [contractRegistry.address, registryAdmin, erc20.address]);
    const certifiedFeesWallet = await web3.deploy('FeesWallet', [contractRegistry.address, registryAdmin, erc20.address]);
    await Promise.all([
        contractRegistry.setContract("staking", options.stakingContractAddress, false, {from: registryAdmin}),
        contractRegistry.setContract("rewards", rewards.address, true, {from: registryAdmin}),
        contractRegistry.setContract("delegations", delegations.address, true, {from: registryAdmin}),
        contractRegistry.setContract("elections", elections.address, true, {from: registryAdmin}),
        contractRegistry.setContract("subscriptions", subscriptions.address, true, {from: registryAdmin}),
        contractRegistry.setContract("protocol", protocol.address, true, {from: registryAdmin}),
        contractRegistry.setContract("certification", certification.address, true, {from: registryAdmin}),
        contractRegistry.setContract("guardiansRegistration", guardiansRegistration.address, true, {from: registryAdmin}),
        contractRegistry.setContract("committee", committee.address, true, {from: registryAdmin}),
        contractRegistry.setContract("stakingRewardsWallet", stakingRewardsWallet.address, false, {from: registryAdmin}),
        contractRegistry.setContract("bootstrapRewardsWallet", bootstrapRewardsWallet.address, false, {from: registryAdmin}),
        contractRegistry.setContract("generalFeesWallet", generalFeesWallet.address, true, {from: registryAdmin}),
        contractRegistry.setContract("certifiedFeesWallet", certifiedFeesWallet.address, true, {from: registryAdmin}),
        contractRegistry.setContract("stakingContractHandler", stakingContractHandler.address, true, {from: registryAdmin}),

        contractRegistry.setContract("_bootstrapToken", externalToken.address, false, {from: registryAdmin}),
        contractRegistry.setContract("_erc20", erc20.address, false, {from: registryAdmin}),
    ]);

    await contractRegistry.setManager("migrationManager", migrationManager, {from: registryAdmin});
    await contractRegistry.setManager("functionalManager", functionalManager, {from: registryAdmin});

    for (const wallet of [stakingRewardsWallet, bootstrapRewardsWallet]) {
        await wallet.transferMigrationOwnership(migrationManager);
        await wallet.claimMigrationOwnership({from: migrationManager});
        await wallet.transferFunctionalOwnership(functionalManager);
        await wallet.claimFunctionalOwnership({from: functionalManager});
    }

    await protocol.createDeploymentSubset(DEPLOYMENT_SUBSET_MAIN, 1, {from: functionalManager});

    await rewards.activate(await web3.now());

    const managedContracts = [
        contractRegistry,
        rewards,
        delegations,
        elections,
        subscriptions,
        protocol,
        certification,
        guardiansRegistration,
        committee,
        generalFeesWallet,
        certifiedFeesWallet,
        stakingContractHandler
    ]
    for (const contract of managedContracts) {
        if (!(await contract.isInitializationComplete())) {
            await contract.initializationComplete();
        }
    }

    const subscriber = await web3.deploy('MonthlySubscriptionPlan', [contractRegistry.address, registryAdmin, erc20.address, options.subscriptionTier, options.subscriptionRate]);
    await subscriptions.addSubscriber(subscriber.address, {from: functionalManager});

    for (const guardian of guardiansToMigrate) {
        await delegations.refreshStake(guardian);
    }

    console.log(`contractRegistry: ${contractRegistry.address}`);
    console.log(`delegations: ${delegations.address}`);
    console.log(`externalToken: ${externalToken.address}`);
    console.log(`erc20: ${erc20.address}`);
    console.log(`stakingContractHandler: ${stakingContractHandler.address}`);
    console.log(`rewards: ${rewards.address}`);
    console.log(`elections: ${elections.address}`);
    console.log(`subscriptions: ${subscriptions.address}`);
    console.log(`protocol: ${protocol.address}`);
    console.log(`certification: ${certification.address}`);
    console.log(`committee: ${committee.address}`);
    console.log(`stakingRewardsWallet: ${stakingRewardsWallet.address}`);
    console.log(`bootstrapRewardsWallet: ${bootstrapRewardsWallet.address}`);
    console.log(`guardiansRegistration: ${guardiansRegistration.address}`);
    console.log(`generalFeesWallet: ${generalFeesWallet.address}`);
    console.log(`certifiedFeesWallet: ${certifiedFeesWallet.address}`);
    console.log(`subscriber: ${subscriber.address}`);
}

deploy().then(
    () => console.log('Done')
).catch(
    (e) => console.error(e)
);