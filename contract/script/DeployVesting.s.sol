// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import "./HelperConfig.s.sol";
import "../src/vesting/Vesting.sol";

contract DeployVesting is Script {
    Vesting public vesting;

    function run() public returns (Vesting, VestingHelperConfig) {
        VestingHelperConfig helperConfig = new VestingHelperConfig();
        VestingHelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        vm.startBroadcast(config.account);
        vesting = new Vesting(config.token);
        vm.stopBroadcast();
        return (vesting, helperConfig);
    }
}
