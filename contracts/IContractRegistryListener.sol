pragma solidity 0.5.16;

interface IContractRegistryListener {

    function refreshContracts() external;

    function refreshManagers(string calldata role, address newManager) external;

}
