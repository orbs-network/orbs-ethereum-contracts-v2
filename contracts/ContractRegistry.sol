pragma solidity 0.5.16;
import "./spec_interfaces/IContractRegistry.sol";
import "./IContractRegistryListener.sol";
import "./WithClaimableMigrationOwnership.sol";
import "./WithClaimableFunctionalOwnership.sol";

contract ContractRegistry is IContractRegistry, WithClaimableMigrationOwnership, WithClaimableFunctionalOwnership {

	struct Contract {
		address addr;
		bool isManaged;
	}
	mapping (bytes32 => Contract) idToContract;
	bytes32[] contractIds;

	function setContracts(bytes32[] calldata ids, address[] calldata addrs, bool[] calldata isManaged) external onlyFunctionalOwner {
		require(ids.length == addrs.length, "ids, addrs array length mismatch");
		require(ids.length == isManaged.length, "ids, isManaged array length mismatch");
		for (uint i = 0; i < ids.length; i++) {
			bytes32 contractId = ids[i];
			address addr = addrs[i];
			bool isCurrentManaged = isManaged[i];
			if (addr != address(0)) {
				if (idToContract[contractId].addr == address(0)) {
					addName(contractId);
				}
			} else {
				isCurrentManaged = false;
				if (idToContract[contractId].addr != address(0)) {
					removeName(contractId);
				}
			}
			idToContract[contractId] = Contract({
				addr: addr,
				isManaged: isCurrentManaged
			});
			emit ContractAddressUpdated(contractId, addr, isCurrentManaged);
		}

		notifyOnContractsChange();
	}

	function notifyOnContractsChange() private {
		bytes32[] memory _contractIds = contractIds;
		Contract memory curContract;
		for (uint i = 0; i < _contractIds.length; i++) {
			curContract = idToContract[_contractIds[i]];
			if (curContract.isManaged) {
				IContractRegistryListener(curContract.addr).refreshContracts();
			}
		}
	}

	function addName(bytes32 contractId) private {
		uint n = contractIds.length;
		contractIds.length = n + 1;
		contractIds[n] = contractId;
	}

	function removeName(bytes32 contractId) private {
		uint n = contractIds.length;
		uint i;
		bool found;
		for (i = 0;
			i < n && contractId != contractIds[i];
			i++) {}

		if (!found) return;

		for (; i < n - 1; i++) {
			contractIds[i] = contractIds[i + 1];
		}
		contractIds.length = n - 1;
	}

	function getContracts(bytes32[] calldata ids) external view returns (address[] memory) {
		address[] memory addrs = new address[](ids.length);
		for (uint i = 0; i < ids.length; i++) {
			addrs[i] = idToContract[ids[i]].addr;
			require(addrs[i] != address(0), "the contract id is not registered");
		}
		return addrs;
	}
}
