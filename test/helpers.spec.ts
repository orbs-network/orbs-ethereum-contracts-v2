import chai from "chai";
const expect = chai.expect;

import {getAbiByContractRegistryKey} from "../abi-loader";
import {compiledContracts} from "../compiled-contracts";

describe("helpers tests", async () => {

    it("should return the ABI by the registry key name", async () => {
        expect(getAbiByContractRegistryKey('protocol')).to.deep.eq(compiledContracts.Protocol.abi);
        expect(getAbiByContractRegistryKey('committee')).to.deep.eq(compiledContracts.Committee.abi);
        expect(getAbiByContractRegistryKey('elections')).to.deep.eq(compiledContracts.Elections.abi);
        expect(getAbiByContractRegistryKey('delegations')).to.deep.eq(compiledContracts.Delegations.abi);
        expect(getAbiByContractRegistryKey('guardiansRegistration')).to.deep.eq(compiledContracts.GuardiansRegistration.abi);
        expect(getAbiByContractRegistryKey('certification')).to.deep.eq(compiledContracts.Certification.abi);
        expect(getAbiByContractRegistryKey('staking')).to.deep.eq(compiledContracts.StakingContract.abi);
        expect(getAbiByContractRegistryKey('subscriptions')).to.deep.eq(compiledContracts.Subscriptions.abi);
        expect(getAbiByContractRegistryKey('stakingRewards')).to.deep.eq(compiledContracts.StakingRewards.abi);
        expect(getAbiByContractRegistryKey('feesAndBootstrapRewards')).to.deep.eq(compiledContracts.FeesAndBootstrapRewards.abi);
        expect(getAbiByContractRegistryKey('stakingRewardsWallet')).to.deep.eq(compiledContracts.ProtocolWallet.abi);
        expect(getAbiByContractRegistryKey('generalFeesWallet')).to.deep.eq(compiledContracts.FeesWallet.abi);
        expect(getAbiByContractRegistryKey('certifiedFeesWallet')).to.deep.eq(compiledContracts.FeesWallet.abi);
        expect(getAbiByContractRegistryKey('stakingContractHandler')).to.deep.eq(compiledContracts.StakingContractHandler.abi);
    });

});