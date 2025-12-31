// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "forge-std/Script.sol";

abstract contract CodeConstants {
    uint256 public constant ETH_CHAIN_ID = 1;
    uint256 public constant BNB_CHAIN_ID = 56;
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant LOCAL_CHAIN_ID = 31337;
}

contract HelperConfig is Script, CodeConstants {
    // ======================== Errors ========================
    error HelperConfig__InvalidChainId();

    // ======================== Types ========================
    struct NetworkConfig {
        address feeCollector;
        uint256 platformBps;
    }

    // ======================== State Variables ========================
    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainId => NetworkConfig) public networkConfigs;

    // ======================== Functions ========================
    constructor(){
        networkConfigs[ETH_CHAIN_ID] = getMainnetConfig();
        networkConfigs[SEPOLIA_CHAIN_ID] = getMainnetConfig();
        networkConfigs[BNB_CHAIN_ID] = getMainnetConfig();
    }

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

    function getMainnetConfig() public returns (NetworkConfig memory mainnetConfig) {
        mainnetConfig = NetworkConfig({
            feeCollector: address(0),
            platformBps: 1000
        });
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory anvilConfig) {
        anvilConfig = NetworkConfig({
            feeCollector: address(0),
            platformBps: 1000
        });
    }
}