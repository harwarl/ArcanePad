/**
 * @title IDOFactory
 * @notice Factory contract for creating and managing IDOPools
 */
interface IDOFactory {
    // ========================================= STATE VARIABLES =========================================
    // address public feeCollector
    // uint256 public platformFeePercent // in BPS
    // address public stakingTierContract
    // address[] public allPools;
    // mapping(address => bool) public isPool;
    // mapping(address => address[]) public poolsByCreator

    event PoolCreated(
        address indexed pool, address indexed creator, address indexed token, uint256 poolId, uint256 timestamp
    );

    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeCollectorUpdated(address oldCollector, address newCollector);
    event PoolPaused(address indexed pool, address admin);
    event PoolUnpaused(address indexed pool, address admin);

    // ========================================= STRUCT =========================================
    struct PoolConfig {
        address tokenAddress;       // Token being sold
        uint256 tokenPrice;         // Price in payment token
        uint256 softCap;            // Minimum raise target
        uint256 hardCap;            // Maximum raise target
        uint256 minContribution;    // Min amount per wallet
        uint256 maxContribution;    // Max amount per wallet
        uint256 startTime;          // Sale start timestamp
        uint256 endTime;            // Sale end Timestamp
        address paymentToken;       // Token Used for payment
        bool whitelistEnabled;      // Whether whitelist is required
        uint8 vestingType;          // 0-immediate, 1-linear, 2=cliff+linear, 3=milestone
    }

    struct VestingConfig {
        uint256 tgePercent;         // Percent unlocked at tge
        uint256 cliff;              // Cliff period in seconds
        uint256 vestingDuration;    // Total Vesting duration after cliff
        uint256 vestingInterval;    // Interval for linear unlock (3.g 30 days)
    }

    // ========================================= CORE FUNCTIONS =========================================
    /**
     * @notice Create a new pool
     * @param poolConfig configuration for the pool
     * @param vestingConfig vessting schedule configuration
     * @param whitelistRoot Merkele root for whitelist (if enabled)
     * @return pool Address of the created pool
     */
    function createPool(
        PoolConfig calldata poolConfig,
        VestingConfig calldata vestingConfig,
        bytes32 whitelistRoot
    ) external returns (address pool);

    /**
     * @notice Get all pools created by the factory
     * @return Array of pool addresses
     */
    function getAllPools() external returns (address[] memory);

    /**
     * @notice Get all pools created by the factory for a particular address
     * @param creator Address of the pool creator
     * @return Array of pool addresses
     */
    function getPoolsByCreator(address creator) external returns (address[] memory);

    /**
     * @notice Get total number of pools
     * @return Total count of pools
     */
    function getPoolCount() external view returns (uint256);

    /**
     * @notice Checks if a pool is valid
     * @param pool Address to check
     * @return True if address is a pool created by factory
     */
    function isValidPool(address pool) external view returns (bool);

    // ========================================= Admin Functions =========================================
    /**
     * @notice Updates the platform fee percentage
     * @param newFeePercent New Fee in Basis Points (max 1000 = 10%)
     */
    function updatePlatformFee(uint256 newFeePercent) external;

    /**
     * @notice Updates the platform fee collector address
     * @param newCollector New Address to receive fees
     */
    function updateFeeCollector(address newCollector) external;

    /**
     * @notice Emergency pause a specific pool
     * @param pool Address of pool to pause
     */
    function EmergencyPausePool(address pool) external;

    /**
     * @notice Unpause a specific pool
     * @param pool Address of pool to unpause
     */
    function unpause(address pool) external;
}
