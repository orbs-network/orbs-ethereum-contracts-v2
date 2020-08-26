pragma solidity 0.5.16;

interface ILockable {

    event Locked();
    event Unlocked();

    function lock() external /* onlyLockOwner */;
    function unlock() external /* onlyLockOwner */;
    function isLocked() view external returns (bool);

}
