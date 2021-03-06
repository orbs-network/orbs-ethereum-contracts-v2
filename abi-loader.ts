import {ContractRegistryKey} from "./test/driver";
import {ContractName} from "./typings/contracts";
import {AbiItem} from "web3-utils";
import {deployedContracts} from "./deployed-contracts";
import Web3 from "web3";

export {ContractRegistryKey, ContractName}

export function getAbiByContractRegistryKey(key: ContractRegistryKey): AbiItem[] {
    switch (key) {
        case 'protocol':
            return require('./abi/Protocol.abi.json');
        case 'committee':
            return require('./abi/Committee.abi.json');
        case 'elections':
            return require('./abi/Elections.abi.json');
        case 'delegations':
            return require('./abi/Delegations.abi.json');
        case 'guardiansRegistration':
            return require('./abi/GuardiansRegistration.abi.json');
        case 'certification':
            return require('./abi/Certification.abi.json');
        case 'staking':
            return require('./abi/StakingContract.abi.json');
        case 'subscriptions':
            return require('./abi/Subscriptions.abi.json');
        case 'stakingRewards':
            return require('./abi/StakingRewards.abi.json');
        case 'feesAndBootstrapRewards':
            return require('./abi/FeesAndBootstrapRewards.abi.json');
        case 'bootstrapRewardsWallet':
            return require('./abi/ProtocolWallet.abi.json');
        case 'stakingRewardsWallet':
            return require('./abi/ProtocolWallet.abi.json');
        case 'generalFeesWallet':
            return require('./abi/FeesWallet.abi.json');
        case 'certifiedFeesWallet':
            return require('./abi/FeesWallet.abi.json');
        case 'stakingContractHandler':
            return require('./abi/StakingContractHandler.abi.json');
        default:
            assertUnreachable(key, `No such contract registry key: ${key}`);
    }
}

export function getAbiByContractName(key: ContractName): AbiItem[] {
    return require(`./abi/${key.replace(/[\/\\\.]/g, '')}.abi.json`);
}

export function getAbiByContractAddress(address: string): (AbiItem[]|undefined) {
    if (!address.startsWith("0x")) {
        address = "0x" + address;
    }
    address = Web3.utils.toChecksumAddress(address.toLowerCase());
    return deployedContracts[address];
}

function assertUnreachable(x: never, msg: string): never {
    throw new Error(msg);
}
