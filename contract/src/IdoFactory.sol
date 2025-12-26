// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IFactory.sol";
import "./IDOPool.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract IDOFactory is IFactory, Ownable {
    // ========================================= STATE VARIABLES =========================================
    // Address to collect fees
    address public feeCollector;
    // Platform fee in basis points
    uint256 public platformFeeBps;
    // Staking Contract to get tiers
    address public stakingTierContract;
    // Array of all the pools created via this factory
    address[] private allPools;
    // Mapping to validate pools
    mapping(address => bool) private isPool;
    // Mapping to get pools by creators
    mapping(address => address[]) private poolsByCreator;

    constructor(
        address _feeCollector,
        uint256 _platformFeeBps, // This can be zero but no more than 10
        address _stakingTierContract
    ) {
        require(_feeCollector != address(0), "IDOFactory: FeeCollector address cannot be zero");
        require(_stakingTierContract != address(0), "IDOFactory: StakingTierContract address cannot be zero");
        require(_platformFeeBps <= 1000, "IDOFactory: Platform Fee Bps cannot exceed 10%");

        feeCollector = _feeCollector;
        platformFeeBps = _platformFeeBps;
        stakingTierContract = _stakingTierContract;
    }

    function createPool(PoolConfig calldata poolConfig, VestingConfig calldata vestingConfig, bytes32 whitelistRoot)
        external
        returns (address)
    {
        // Validate the PoolConfig Parameters
        require(
            poolConfig.startTime < poolConfig.endTime && poolConfig.startTime > block.timestamp,
            "IDOFactory: Invalid Time stamps"
        );
        require(poolConfig.softCap < poolConfig.hardCap, "IDOFactory: SoftCap must be less than HardCap");
        require(
            poolConfig.minContribution < poolConfig.maxContribution,
            "IDOFactory: Min contributions must be less than Max"
        );
        require(poolConfig.tokenAddress != address(0), "IDOFactory: Token address cannot be zero");
        require(poolConfig.paymentToken != address(0), "IDOFactory: Purchase token address cannot be zero");
        require(poolConfig.tokenPrice > 0, "IDOFactory: Invalid token price");

        // Create a new Pool
        IDOPool pool = new IDOPool(); // TODO: add parameters in here

        // Add the pool to the array of pools
        allPools.push(address(pool));
        isPool[address(pool)] = true;
        poolsByCreator[_msgSender()].push(address(pool));

        emit PoolCreated(address(pool), _msgSender(), poolConfig.tokenAddress, allPools.length - 1, block.timestamp);
        return address(pool);
    }

    function getAllPools() external view returns (address[] memory) {
        return allPools;
    }

    function getPoolsByCreator(address creator) external view returns (address[] memory) {
        require(creator != address(0), "IDOFactory: Creator address cannot be zero");
        return poolsByCreator[creator];
    }

    function getPoolCount() external view returns (uint256) {
        return allPools.length;
    }

    function isValidPool(address pool) external view returns (bool) {
        require(pool != address(0), "IDOFactory: Pool address cannot be zero");
        return isPool[pool];
    }

    function updatePlatformFee(uint256 newFeePercentBps) external {
        require(newFeePercentBps <= 1000, "IDOFactory: Platform Fee Bps cannot exceed 10%");
        platformFeeBps = newFeePercentBps;
    }

    function updateFeeCollector(address newCollector) external {
        require(newCollector != address(0), "IDOFactory: FeeCollector address cannot be zero");
        feeCollector = newCollector;
    }

    function EmergencyPausePool(address pool) external {
        require(pool != address(0), "IDOFactory: Pool address cannot be zero");
        IDOPool(pool).pause();
    }

    function unpause(address pool) external {
        require(pool != address(0), "IDOFactory: Pool address cannot be zero");
        IDOPool(pool).unpause();
    }
}
