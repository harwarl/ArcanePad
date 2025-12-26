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
        _validatePoolConfig(poolConfig);

        // ValidateVestingConfig
        _validateVestingConfig(vestingConfig);

        // Validate Whilelist Root
        _validateWhiteListRoot(poolConfig, whitelistRoot);

        // Create a new Pool
        IDOPool pool = new IDOPool();

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

    /**
     * @notice Validate pool configuration parameters
     * @param poolConfig The pool configuration to validate
     */
    function _validatePoolConfig(PoolConfig calldata poolConfig) internal view {
        require(poolConfig.tokenAddress != address(0), "IDOFactory: Token address cannot be zero");
        require(_isContract(poolConfig.tokenAddress), "IDOFactory: Token address must be a contract");
        require(poolConfig.paymentToken != address(0), "IDOFactory: Payment token address cannot be zero");
        require(_isContract(poolConfig.paymentToken), "IDOFactory: Payment token must be a contract");
        require(
            poolConfig.tokenAddress != poolConfig.paymentToken, "IDOFactory: Token and payment token must be different"
        );
        require(poolConfig.tokenPrice > 0, "IDOFactory: Token price must be greater than 0");
        require(poolConfig.softCap > 0, "IDOFactory: Soft cap must be greater than 0");
        require(poolConfig.hardCap > poolConfig.softCap, "IDOFactory: Hard cap must be greater than soft cap");
        require(poolConfig.hardCap >= poolConfig.softCap * 2, "IDOFactory: Hard cap should be at least 2x soft cap");
        require(poolConfig.minContribution > 0, "IDOFactory: Min contribution must be greater than 0");
        require(
            poolConfig.maxContribution > poolConfig.minContribution,
            "IDOFactory: Max contribution must be greater than min contribution"
        );
        require(
            poolConfig.maxContribution >= poolConfig.minContribution * 2,
            "IDOFactory: Max contribution should be at least 2x min contribution"
        );
        require(
            poolConfig.softCap >= poolConfig.minContribution * 10,
            "IDOFactory: Soft cap too low for min contribution (min 10 potential participants)"
        );
        require(
            poolConfig.maxContribution <= poolConfig.hardCap / 2,
            "IDOFactory: Max contribution too high (max 50% of hard cap per wallet)"
        );
        require(poolConfig.startTime > block.timestamp, "IDOFactory: Start time must be in the future");
        require(
            poolConfig.startTime <= block.timestamp + 365 days, "IDOFactory: Start time too far in future (max 1 year)"
        );
        require(poolConfig.endTime > poolConfig.startTime, "IDOFactory: End time must be after start time");
        uint256 saleDuration = poolConfig.endTime - poolConfig.startTime;
        require(saleDuration >= 1 hours, "IDOFactory: Sale duration too short (minimum 1 hour)");
        require(saleDuration <= 30 days, "IDOFactory: Sale duration too long (maximum 30 days)");
        require(poolConfig.vestingType <= 3, "IDOFactory: Invalid vesting type (must be 0-3)");
        require(
            poolConfig.startTime >= block.timestamp + 1 hours,
            "IDOFactory: Start time too soon (minimum 1 hour from now)"
        );
    }

    /**
     * @notice Validate vesting configuration parameters
     * @param vestingConfig The vesting configuration to validate
     */
    function _validateVestingConfig(VestingConfig calldata vestingConfig) internal pure {
        require(vestingConfig.tgePercent <= 10000, "IDOFactory: TGE percent cannot exceed 100% (10000 basis points)");
        if (vestingConfig.tgePercent == 10000) {
            require(
                vestingConfig.cliff == 0 && vestingConfig.vestingDuration == 0 && vestingConfig.vestingInterval == 0,
                "IDOFactory: No vesting parameters needed when TGE is 100%"
            );
            return;
        }
        require(
            vestingConfig.vestingDuration > 0, "IDOFactory: Vesting duration must be greater than 0 when TGE < 100%"
        );
        require(vestingConfig.vestingInterval > 0, "IDOFactory: Vesting interval must be greater than 0");
        require(
            vestingConfig.vestingInterval <= vestingConfig.vestingDuration,
            "IDOFactory: Vesting interval cannot exceed vesting duration"
        );
        require(
            vestingConfig.vestingDuration % vestingConfig.vestingInterval == 0,
            "IDOFactory: Vesting duration must be divisible by vesting interval"
        );
        require(
            vestingConfig.cliff < vestingConfig.vestingDuration,
            "IDOFactory: Cliff cannot be longer than vesting duration"
        );
        require(vestingConfig.vestingInterval >= 1 days, "IDOFactory: Vesting interval too short (minimum 1 day)");
        require(vestingConfig.vestingInterval <= 365 days, "IDOFactory: Vesting interval too long (maximum 365 days)");
        require(vestingConfig.vestingDuration >= 7 days, "IDOFactory: Vesting duration too short (minimum 7 days)");
        require(
            vestingConfig.vestingDuration <= 1460 days, // 4 years
            "IDOFactory: Vesting duration too long (maximum 4 years)"
        );
        require(vestingConfig.cliff <= 365 days, "IDOFactory: Cliff period too long (maximum 1 year)");
    }

    /**
     * @notice Validate whitelist root parameter
     * @param poolConfig The pool configuration
     * @param whitelistRoot The merkle root for whitelist
     */
    function _validateWhiteListRoot(PoolConfig calldata poolConfig, bytes32 whitelistRoot) internal pure {
        if (poolConfig.whitelistEnabled) {
            //  If whitelist is enabled, root cannot be empty
            require(whitelistRoot != bytes32(0), "IDOFactory: Whitelist enabled but root is empty");

            // Root should not be a known invalid value
            // Merkle root of empty tree is typically a specific hash
            require(whitelistRoot != keccak256(""), "IDOFactory: Invalid whitelist root (empty hash)");
        } else {
            // If whitelist is disabled, root should be empty (optional but recommended)
            // This is a soft check - you might allow a root even if whitelist is disabled
            // for potential future enabling
            // Require empty root (strict)
            require(whitelistRoot == bytes32(0), "IDOFactory: Whitelist disabled but root provided");
        }
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
