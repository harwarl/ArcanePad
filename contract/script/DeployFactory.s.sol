// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import "../src/IDOFactory.sol";

contract DeployFactory is Script {
    IDOFactory public factory;

    function run() public returns (IDOFactory) {
        vm.startBroadcast();
        
        vm.stopBroadcast();
    }
}
