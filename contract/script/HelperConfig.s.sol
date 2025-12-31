// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import "../src/mocks/MockToken.sol";

abstract contract CodeConstants {
    uint256 public constant ETH_CHAIN_ID = 1;
    uint256 public constant BNB_CHAIN_ID = 56;
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant LOCAL_CHAIN_ID = 31337;
}
// ======================== Errors ========================

error HelperConfig__InvalidChainId();

contract FactoryHelperConfig is Script, CodeConstants {
    // ======================== Types ========================
    struct NetworkConfig {
        address feeCollector;
        uint256 platformBps;
        address account;
    }

    // ======================== State Variables ========================
    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainId => NetworkConfig) public networkConfigs;

    // ======================== Functions ========================
    // constructor() {
    //     networkConfigs[ETH_CHAIN_ID] = getMainnetConfig();
    //     networkConfigs[SEPOLIA_CHAIN_ID] = getMainnetConfig();
    //     networkConfigs[BNB_CHAIN_ID] = getMainnetConfig();
    // }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function setConfig(uint256 chainid, NetworkConfig memory networkConfig) public {
        networkConfigs[chainid] = networkConfig;
    }

    function getConfigByChainId(uint256 chainid) public returns (NetworkConfig memory) {
        // return config based on chainid
        if (chainid == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilConfig();
        }
        if (networkConfigs[chainid].feeCollector != address(0) || networkConfigs[chainid].platformBps != 0) {
            return networkConfigs[chainid];
        }
        revert HelperConfig__InvalidChainId();
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        if (localNetworkConfig.feeCollector != address(0)) {
            return localNetworkConfig;
        }

        localNetworkConfig = NetworkConfig({
            feeCollector: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8,
            platformBps: 1000,
            account: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
        });

        return localNetworkConfig;
    }
}

contract VestingHelperConfig is Script, CodeConstants {
    // ======================== Types ========================
    struct NetworkConfig {
        address token;
        address account;
    }

    // ======================== State Variables ========================
    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainid => NetworkConfig) public networkConfigs;

    // ======================== Functions ========================
    constructor() {
        networkConfigs[ETH_CHAIN_ID] = getOrCreateAnvilConfig();
        networkConfigs[SEPOLIA_CHAIN_ID] = getOrCreateAnvilConfig();
        networkConfigs[BNB_CHAIN_ID] = getOrCreateAnvilConfig();
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainid(block.chainid);
    }

    function getConfigByChainid(uint256 chainid) public returns (NetworkConfig memory) {
        if (chainid == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilConfig();
        }
        if (networkConfigs[chainid].token != address(0)) {
            return networkConfigs[chainid];
        }
        revert HelperConfig__InvalidChainId();
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        if (localNetworkConfig.token != address(0)) {
            return localNetworkConfig;
        }
        MockToken mockToken = new MockToken();
        localNetworkConfig =
            NetworkConfig({token: address(mockToken), account: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266});

        return localNetworkConfig;
    }
}
