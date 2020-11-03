import {Driver, ZERO_ADDR} from "./driver";
import {ManagedContract} from "../typings/base-contract";
import {expectRejected} from "./helpers";
import chai from "chai";
import BN from "bn.js";
import {chaiEventMatchersPlugin} from "./matchers";
chai.use(require('chai-bn')(BN));
chai.use(chaiEventMatchersPlugin);

const expect = chai.expect;

describe("managed-contract", async () => {
    it("registry accessor: gets contract registry, sets registryAdmin only by init admin", async () => {
        const d = await Driver.new();
        const managed: ManagedContract = await d.web3.deploy('ManagedContractTest' as any, [d.contractRegistry.address, d.registryAdmin.address]);
        expect(await managed.getContractRegistry()).to.eq(d.contractRegistry.address);

        const newAdmin = d.newParticipant();

        await expectRejected(managed.setRegistryAdmin(newAdmin.address, {from: d.migrationManager.address}), /sender is not the initialization admin/);

        await managed.setRegistryAdmin(newAdmin.address, {from: d.initializationAdmin.address});
        expect(await managed.registryAdmin()).to.eq(newAdmin.address);

        await managed.initializationComplete({from: d.initializationAdmin.address});
        await expectRejected(managed.setRegistryAdmin(newAdmin.address, {from: d.initializationAdmin.address}), /sender is not the initialization admin/);
    });

    it('is able to transfer, renounce registryManagement ownership', async () => {
        const d = await Driver.new();
        const managed: ManagedContract = await d.web3.deploy('ManagedContractTest' as any, [d.contractRegistry.address, d.registryAdmin.address]);
        const newManager = d.newParticipant()
        await expectRejected(managed.transferRegistryManagement(newManager.address, {from: d.migrationManager.address}), /WithClaimableRegistryManagement: caller is not the registryAdmin/)
        await managed.transferRegistryManagement(newManager.address, {from: d.registryAdmin.address});
        await expectRejected(managed.claimRegistryManagement({from: d.registryAdmin.address}), /Caller is not the pending registryAdmin/);
        await managed.claimRegistryManagement({from: newManager.address});
        expect(await managed.registryAdmin()).to.eq(newManager.address);

        await expectRejected(managed.renounceRegistryManagement({from: d.registryAdmin.address}), /WithClaimableRegistryManagement: caller is not the registryAdmin/);
        await managed.renounceRegistryManagement({from: newManager.address});
        expect(await managed.registryAdmin()).to.eq(ZERO_ADDR);
    });
});

