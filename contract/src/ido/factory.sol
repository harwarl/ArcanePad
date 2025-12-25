// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

contract Factory {
    function createPool() external returns (bool) {}
    function getAllPools() external returns (address[] memory) {}
    function getPoolsByCreator(address creator) external returns (address[] memory) {}

    function getPoolCount() external view returns (uint256) {}
    function isValidPool() external view returns (bool) {}

    function updatePlatformFee(uint256 newFeePercent) external {}
    function updateFeeCollector(address newCollector) external {}

    function emergencyPausePool() external {}
    function unpause() external {}
}
