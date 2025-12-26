// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "../library/DataTypes.sol";

/**
 * @title IDOPool
 * @notice Individual IDO pool contrcat for token sales
 */
interface IPool {
    // ========================================= STATE VARIABLES =========================================
    // IDO Factory Address
    // address public factory;
    // IDO creator Address
    // address public creator
    // WhitelistMerkleRoot
    // bytes32 public whitelistMerkleRoot;
    // // Current Pool status
    // PoolStatus public status;

    // // Mappings
    // mapping(address => uint256) public contributions;
    // mapping(address => uint256) public tokenAllocations;
    // mapping(address => bool) public hasClaimedRefund;
    // mapping(uint8 => uint256) public tierAllocations; // tier => guaranteed Allocation Amount

    // ======================== ENUMS ========================
    enum PoolStatus {
        Init,
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
    event PoolInitialized(address indexed creator, address indexed tokenAddress, address indexed paymentToken);
    event Participated(address indexed user, uint256 amount, uint256 tokensAllocated, uint256 timestamp);
    event TokensClaimed(address indexed user, uint256 amount, uint256 timestamp);
    event RefundClaimed(address indexed user, uint256 amount, uint256 timestamp);
    event PoolFinalized(uint256 totalRaised, uint256 totalParticipants, uint256 timestamp);
    event PoolCancelled(address admin, uint256 timestamp);
    event whitelistUpdated(bytes32 newMerkleRoot, uint256 timestamp);
    event EmergencyWithdraw(address token, uint256 amount, address to);

    // ======================== CORE FUNCTIONS ========================
    /**
     * @notice Initialize the pool with configuration
     * @dev Can only be called once, by factory
     * @param poolConfig Pool configuration struct
     * @param vestingConfig Vesting configuration struct
     * @param _whitelistRoot Merkle root for whitelist
     * @param _creator Pool creator address
     * @param _stakingTiers Staking tiers contract address
     * @param _feeCollector Fee collector address
     * @param _platformFeeBps Platform fee in basis points
     */
    function initialize(
        DataTypes.PoolConfig calldata poolConfig,
        DataTypes.VestingConfig calldata vestingConfig,
        bytes32 _whitelistRoot,
        address _creator,
        address _stakingTiers,
        address _feeCollector,
        uint256 _platformFeeBps
    ) external;

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
    function getPoolInfo() external view returns (DataTypes.PoolInfo memory);

    /**
     * @notice Get the user's participation information
     * @param user Address of the user
     * @return User's contribution and allocation details
     */
    function getUserInfo(address user) external view returns (DataTypes.UserInfo memory);

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
