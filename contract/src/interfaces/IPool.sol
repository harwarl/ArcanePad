/**
 * @title IDOPool
 * @notice Individual IDO pool contrcat for token sales
 */
interface IDOPool {
    // ========================================= STATE VARIABLES =========================================
    // address public factory;
    // address public creator;
    // address public token; // Token being sold
    // address public paymentToken; // USDT,, USDC
    // uint256 public tokenPrice;
    // uint256 public softCap;
    // uint256 public hardCap;
    // uint256 public minContribution;
    // uint256 public maxContribution;
    // uint256 public startTime;
    // uint256 public endTime;
    // uint256 public totalRaised;
    // uint256 public totalParticipants;
    // bool public finalized;
    // bool public whitelistEnabled;
    // bytes32 public whitelistMerkleRoot;

    // // Mappings
    // mapping(address => uint256) public contributions;
    // mapping(address => uint256) public tokenAllocations;
    // mapping(address => bool) public hasClaimedRefund;
    // mapping(uint8 => uint256) public tierAllocations; // tier => guaranteed Allocation Amount

    // ======================== ENUMS ========================
    enum PoolStatus {
        Upcoming,
        Active,
        Ended,
        Finalized,
        Failed,
        Cancelled
    }

    enum UserTier {
        None, // Not Staked
        Bronze, // Tier 1
        Silver, // Tier 2
        Gold, // Tier 3
        Diamond // Tier 4

    }

    // ======================== EVENTS ========================
    event Participated(address indexed user, uint256 amount, uint256 tokensAllocated, uint8 tier, uint256 timestamp);
    event TokensClaimed(address indexed user, uint256 amount, uint256 timestamp);
    event RefundClaimed(address indexed user, uint256 amount, uint256 timestamp);
    event PoolFinalized(uint256 totalRaised, uint256 totalParticipants, uint256 timestamp);
    event PoolCancelled(address admin, uint256 timestamp);
    event whitelistUpdated(bytes32 newMerkleRoot, uint256 timestamp);
    event EmergencyWithdraw(address token, uint256 amount, address to);

    // ======================== STRUCTS ========================
    struct PoolInfo {
        // address of the token to be bought
        address token;
        // address of the payment token
        address paymentToken;
        // Price in payment token
        uint256 tokenPrice;
        // Minimum raise target
        uint256 softCap;
        // Maximum raise target
        uint256 hardCap;
        // Min amount per wallet
        uint256 minContribution;
        // Max amount per wallet
        uint256 maxContribution;
        // sale start timestamp
        uint256 startTime;
        // sale end timestamp
        uint256 endTime;
        // total amount raised for the project
        uint256 totalRaised;
        // total wallets involved in sale
        uint256 totalParticipants;
        // true is project is completed, false if its not
        bool finalized;
        // true is project is cancelled, false if not
        bool cancelled;
        PoolStatus status;
    }

    struct UserInfo {
        // total payment token contributed
        uint256 contribution;
        // total allocation of token to user
        uint256 totalAllocation;
        //true is wallet has claimed the refund
        bool hasClaimedRefund;
        // true if wallet has claimed the token
        bool hasClaimedTokens;
        // user tier
        uint8 tier;
        // guaranteed allocation is tier is valid
        uint256 guaranteedAllocation;
    }

    // ======================== CORE FUNCTIONS ========================
    /**
     * @notice Participate in the IDO sale
     * @param amount Amount of the payment token to contribute
     * @param merkleProof Proof for whitelist verification (if enabled)
     */
    function participate(uint256 amount, bytes32[] calldata merkleProof) external;

    /**
     * @notice Participate with native token (ETH/MATIC)
     * @param merkleProof Proof for whitelise verification (if enabled)
     */
    function participateWithNative(bytes32[] calldata merkleProof) external payable;

    /**
     * @notice Claim allocated tokens after pool finalization
     */
    function claimTokens() external;

    /**
     * @notice Claim refund if pool failed or was cancelled
     */
    function claimRefund() external;

    /**
     * @notice Get Current pool status
     * @return Current status of the pool
     */
    function getPoolStatus() external view returns (PoolStatus);

    /**
     * @notice Get complete pool information
     * @return Pool configuration and state
     */
    function getPoolInfo() external view returns (PoolInfo memory);

    /**
     * @notice Get the user's participation information
     * @param user Address of the user
     * @return User's contribution and allocation details
     */
    function getUserInfo(address user) external view returns (UserInfo memory);

    /**
     * @notice Calculate the token user would receive for an amount
     * @param paymentTokenAmmount Amount of payment token
     * @return Amount of tokens to be allocated
     */
    function calculateTokenAllocation(uint256 paymentTokenAmmount) external view returns (uint256);

    /**
     * @notice Get user's tier from staking contract
     * @param user Address of the user
     * @return Tier Level (0-5)
     */
    function getUserTier(address user) external view returns (uint8);

    /**
     * @notice Check if user is whitelisted
     * @param user address to check
     * @param merkleProof Merkle Proof for verification
     */
    function isWhitelisted(address user, bytes32[] calldata merkleProof) external view returns (bool);

    /**
     * @notice Get Guaranteed allocation for a tier
     * @param tier Tier Level
     * @return Allocation amount in payment token
     */
    function getTierAllocation(uint8 tier) external view returns (uint256);

    /**
     * @notice Get remaining allocation available
     * @return Available amount that can still be raised
     */
    function getRemainingAllocation() external view returns (uint256);

    /**
     * @notice Gets the list of all participants
     * @return Array of participant addresses
     */
    function getAllParticipants() external view returns (address[] memory);

    /**
     * @notice Get progress percentahe (raised/hardcap)
     * @return Progress in Basis Point (10000 = 100%)
     */
    function getProgress() external view returns (uint256);

    /**
     * @notice check if soft cap was reached
     * @return True if soft cap met
     */
    function isSoftCapReached() external view returns (bool);

    /**
     * @notice check if hard cap was reached
     * @return True if hard cap met
     */
    function isHardCapReached() external view returns (bool);

    /**
     * @notice Get Time remaining until end
     * @return Seconds remaining (0 if ended)
     */
    function getTimeRemaining() external view returns (uint256);

    // ======================== ADMIN FUNCTIONS ========================
    /**
     * @notice Finalize the pool after end time
     * @dev can only be called after end time if soft cap reached
     */
    function finalize() external;

    /**
     * @notice Cancel the pool (emerygency only)
     * @dev can only be called by the factory or creator
     */
    function cancel() external;

    /**
     * @notice Update whitelist merkle root
     * @param newMerkleRoot New Merkle roor for whitelist
     */
    function updateWhiteliste(bytes32 newMerkleRoot) external;

    /**
     * @notice Set tier allocation
     * @param tiers Array of tier levels
     * @param allocations Array of allocation amounts
     */
    function setTierAllocations(uint8[] calldata tiers, uint256[] calldata allocations) external;

    /**
     * @notice Withdraw raised funds (after finalization)
     * @param to Address to send funds
     */
    function withdrawRaisedFunds(address to) external;

    /**
     * @notice Emergency withdraw tokens (only unsold tokens)
     * @param token Token address to withdraw
     * @param to Address to send to
     */
    function emergencyWithdrawTokens(address token, address to) external;

    /**
     * @notice Pause the pool
     */
    function pause() external;

    /**
     * @notice Unpause the pool
     */
    function unpause() external;

    // ======================== INTERNAL FUNCTIONS ========================
    // /**
    //  * @notice Verify Merkle proof for whitelist
    //  * @param user Address to verify
    //  * @param merkleProof  Proof Array
    //  * @return True if proof is valid
    //  */
    // function _verifyWhitelist(address user, bytes32[] calldata merkleProof) internal view returns(bool);

    // /**
    //  * @notice Calculate platform fee
    //  * @param amount Amount to calculate fee on
    //  * @return fee amount
    //  */
    // function _calculatePlatformFee(uint256 amount) internal view returns (uint256);

    // /**
    //  * @notice transfer tokens with fee deduction
    //  * @param to Recipeint Address
    //  * @param amount Amount to transfer
    //  */
    // function _transferWithFee(address to, uint256 amount) internal;

    // /**
    //  * @notice Check if user can participate
    //  * @param user user Address
    //  * @param amount contribution amount
    //  * @param merkleProof whitelist proof
    //  */
    // function _canParticipate(address user, uint256 amount, bytes32[] calldata merkleProof) internal views returns (bool);
}
