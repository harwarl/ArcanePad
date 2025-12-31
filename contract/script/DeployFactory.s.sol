// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import "../src/IDOFactory.sol";
import "./HelperConfig.s.sol";

contract DeployFactory is Script {
    IDOFactory public factory;

    function run() public returns (IDOFactory, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        vm.startBroadcast(config.account);
        factory = new IDOFactory(
            config.feeCollector,
            config.platformBps
        );
        vm.stopBroadcast();

        return (factory, helperConfig);
    }
}
