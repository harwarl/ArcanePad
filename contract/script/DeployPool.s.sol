// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import "../src/IDOPool.sol";

contract DeployPool is Script {
    IDOPool public pool;

    function run() public returns (IDOPool) {
        vm.startBroadcast();
        pool = new IDOPool();
        vm.stopBroadcast();

        return pool;
    }
}
