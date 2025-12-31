// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IFactory.sol";
import "./vesting/Vesting.sol";
import "./IDOPool.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

error IDOFactory__ZeroFeeCollector();
error IDOFactory__ZeroStakingTier();
error IDOFactory__PlatformFeeTooHigh();
error IDOFactory__ZeroCreator();
error IDOFactory__ZeroPool();
error IDOFactory__ZeroToken();
error IDOFactory__TokenNotContract();
error IDOFactory__ZeroPaymentToken();
error IDOFactory__PaymentTokenNotContract();
error IDOFactory__TokenEqualsPayment();
error IDOFactory__ZeroTokenPrice();
error IDOFactory__ZeroSoftCap();
error IDOFactory__HardCapTooLow();
error IDOFactory__HardCapTooSmall();
error IDOFactory__ZeroMinContribution();
error IDOFactory__MaxContributionTooLow();
error IDOFactory__MaxContributionTooSmall();
error IDOFactory__SoftCapTooLow();
error IDOFactory__MaxContributionTooHigh();
error IDOFactory__StartTimePast();
error IDOFactory__StartTimeTooFar();
error IDOFactory__EndTimeBeforeStart();
error IDOFactory__SaleDurationTooShort();
error IDOFactory__SaleDurationTooLong();
error IDOFactory__InvalidVestingType();
error IDOFactory__StartTimeTooSoon();
error IDOFactory__TGETooHigh();
error IDOFactory__NoVestingNeeded();
error IDOFactory__VestingDurationZero();
error IDOFactory__VestingIntervalZero();
error IDOFactory__IntervalExceedsDuration();
error IDOFactory__DurationNotDivisibleByInterval();
error IDOFactory__CliffExceedsDuration();
error IDOFactory__IntervalTooShort();
error IDOFactory__IntervalTooLong();
error IDOFactory__DurationTooShort();
error IDOFactory__DurationTooLong();
error IDOFactory__CliffTooLong();

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
        uint256 _platformFeeBps // This can be zero but no more than 10
    ) {
        if (_feeCollector == address(0)) {
            revert IDOFactory__ZeroFeeCollector();
        }

        if (_platformFeeBps > 1000) {
            revert IDOFactory__PlatformFeeTooHigh();
        }

        feeCollector = _feeCollector;
        platformFeeBps = _platformFeeBps;
    }

    function createPool(DataTypes.PoolConfig calldata poolConfig, DataTypes.VestingConfig calldata vestingConfig)
        external
        returns (address)
    {
        // Validate the PoolConfig Parameters
        _validatePoolConfig(poolConfig);

        // ValidateVestingConfig
        _validateVestingConfig(vestingConfig);

        // Create a new Pool
        IDOPool pool = new IDOPool();

        // Create a vesting contract
        Vesting vesting = new Vesting(poolConfig.tokenAddress);

        // Initialize pool
        pool.initialize(poolConfig, vestingConfig, false, msg.sender, feeCollector, address(vesting), platformFeeBps);

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
        if (creator == address(0)) {
            revert IDOFactory__ZeroCreator();
        }

        return poolsByCreator[creator];
    }

    function getPoolCount() external view returns (uint256) {
        return allPools.length;
    }

    function isValidPool(address pool) external view returns (bool) {
        if (pool == address(0)) {
            revert IDOFactory__ZeroPool();
        }
        return isPool[pool];
    }

    function updatePlatformFee(uint256 newFeePercentBps) external {
        if (newFeePercentBps > 1000) {
            revert IDOFactory__PlatformFeeTooHigh();
        }
        platformFeeBps = newFeePercentBps;
    }

    function updateFeeCollector(address newCollector) external {
        if (newCollector == address(0)) {
            revert IDOFactory__ZeroFeeCollector();
        }
        feeCollector = newCollector;
    }

    function EmergencyPausePool(address pool) external {
        if (pool == address(0)) {
            revert IDOFactory__ZeroPool();
        }
        IDOPool(pool).pause();
    }

    function unpause(address pool) external {
        if (pool == address(0)) {
            revert IDOFactory__ZeroPool();
        }
        IDOPool(pool).unpause();
    }

    /**
     * @notice Validate pool configuration parameters
     * @param poolConfig The pool configuration to validate
     */
    function _validatePoolConfig(DataTypes.PoolConfig calldata poolConfig) internal view {
        if (poolConfig.tokenAddress == address(0)) revert IDOFactory__ZeroToken();
        if (!_isContract(poolConfig.tokenAddress)) revert IDOFactory__TokenNotContract();
        if (poolConfig.paymentToken == address(0)) revert IDOFactory__ZeroPaymentToken();
        if (!_isContract(poolConfig.paymentToken)) revert IDOFactory__PaymentTokenNotContract();
        if (poolConfig.tokenAddress == poolConfig.paymentToken) revert IDOFactory__TokenEqualsPayment();
        if (poolConfig.tokenPrice == 0) revert IDOFactory__ZeroTokenPrice();
        if (poolConfig.softCap == 0) revert IDOFactory__ZeroSoftCap();
        if (poolConfig.hardCap <= poolConfig.softCap) revert IDOFactory__HardCapTooLow();
        if (poolConfig.hardCap < poolConfig.softCap * 2) revert IDOFactory__HardCapTooSmall();
        if (poolConfig.minContribution == 0) revert IDOFactory__ZeroMinContribution();
        if (poolConfig.maxContribution <= poolConfig.minContribution) revert IDOFactory__MaxContributionTooLow();
        if (poolConfig.maxContribution < poolConfig.minContribution * 2) revert IDOFactory__MaxContributionTooSmall();
        if (poolConfig.softCap < poolConfig.minContribution * 10) revert IDOFactory__SoftCapTooLow();
        if (poolConfig.maxContribution > poolConfig.hardCap / 2) revert IDOFactory__MaxContributionTooHigh();
        if (poolConfig.startTime <= block.timestamp) revert IDOFactory__StartTimePast();
        if (poolConfig.startTime > block.timestamp + 365 days) revert IDOFactory__StartTimeTooFar();
        if (poolConfig.endTime <= poolConfig.startTime) revert IDOFactory__EndTimeBeforeStart();

        uint256 saleDuration = poolConfig.endTime - poolConfig.startTime;
        if (saleDuration < 1 hours) revert IDOFactory__SaleDurationTooShort();
        if (saleDuration > 30 days) revert IDOFactory__SaleDurationTooLong();

        if (poolConfig.vestingType > 3) revert IDOFactory__InvalidVestingType();
        if (poolConfig.startTime < block.timestamp + 1 hours) revert IDOFactory__StartTimeTooSoon();
    }

    /**
     * @notice Validate vesting configuration parameters
     * @param v The vesting configuration to validate
     */
    function _validateVestingConfig(DataTypes.VestingConfig calldata v) internal pure {
        if (v.tgePercent > 10000) revert IDOFactory__TGETooHigh();

        if (v.tgePercent == 10000) {
            if (v.cliff != 0 || v.vestingDuration != 0 || v.vestingInterval != 0) {
                revert IDOFactory__NoVestingNeeded();
            }
            return;
        }

        if (v.vestingDuration == 0) revert IDOFactory__VestingDurationZero();
        if (v.vestingInterval == 0) revert IDOFactory__VestingIntervalZero();
        if (v.vestingInterval > v.vestingDuration) revert IDOFactory__IntervalExceedsDuration();
        if (v.vestingDuration % v.vestingInterval != 0) revert IDOFactory__DurationNotDivisibleByInterval();
        if (v.cliff >= v.vestingDuration) revert IDOFactory__CliffExceedsDuration();
        if (v.vestingInterval < 1 days) revert IDOFactory__IntervalTooShort();
        if (v.vestingInterval > 30 days) revert IDOFactory__IntervalTooLong();
        if (v.vestingDuration < 7 days) revert IDOFactory__DurationTooShort();
        if (v.vestingDuration > 1460 days) revert IDOFactory__DurationTooLong();
        if (v.cliff > 365 days) revert IDOFactory__CliffTooLong();
    }

    /**
     * @notice Check if an address is a contract
     * @param account Address to check
     * @return True if address is a contract
     */
    function _isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
}
