// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "../library/DataTypes.sol";

/**
 * @title IDOPool
 * @notice Individual IDO pool contrcat for token sales
 */
interface IPool {
    // ======================== ENUMS ========================
    enum PoolStatus {
        Init,
        Active,
        Ended,
        Finalized,
        Failed,
        Cancelled
    }

    // ======================== EVENTS ========================
    event PoolInitialized(address indexed creator, address indexed tokenAddress, address indexed paymentToken);
    event Participated(address indexed user, uint256 amount, uint256 tokensAllocated, uint256 timestamp);
    event TokensClaimed(address indexed user, uint256 amount, uint256 timestamp);
    event RefundClaimed(address indexed user, uint256 amount, uint256 timestamp);
    event PoolFinalized(uint256 totalRaised, uint256 totalParticipants, uint256 timestamp);
    event PoolCancelled(address admin, uint256 timestamp);
    event whitelistUpdated(bytes32 newMerkleRoot, uint256 timestamp);
    event EmergencyWithdraw(address token, uint256 amount, address to, uint256 timestamp);
    event TierAllocationsSet(uint8 tier, uint256 amount, uint256 timestamp);
    event VestingScheduleCreated(address indexed user, uint256 amount, uint256 cliff, uint256 duration, uint256 start);

    // ======================== CORE FUNCTIONS ========================
    /**
     * @notice Initialize the pool with configuration
     * @dev Can only be called once, by factory
     * @param _poolConfig Pool configuration struct
     * @param _vestingConfig Vesting configuration struct
     * @param _whitelistRoot Merkle root for whitelist
     * @param _whitelistEnabled tag to check whitelist
     * @param _creator Pool creator address
     * @param _feeCollector Fee collector address
     * @param _vestingContract Vesting contract
     * @param _platformFeeBps Platform fee in basis points
     */
    function initialize(
        DataTypes.PoolConfig calldata _poolConfig,
        DataTypes.VestingConfig calldata _vestingConfig,
        bytes32 _whitelistRoot,
        bool _whitelistEnabled,
        address _creator,
        address _feeCollector,
        address _vestingContract,
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
     *
     * @param user address of the user to check
     * @return bool true if the user can and false if he can't
     * @return reason
     */
    function canClaimTokens(address user) external view returns (bool, string memory);

    /**
     *
     * @param user address of the user to check
     * @return bool true if the user can and false if he can't
     * @return reason
     */
    function canClaimRefund(address user) external view returns (bool, string memory);

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
     * @notice Check if user is whitelisted
     * @param user address to check
     * @param merkleProof Merkle Proof for verification
     */
    function isWhitelisted(address user, bytes32[] calldata merkleProof) external view returns (bool);

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
    function updateWhitelist(bytes32 newMerkleRoot) external;

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
}
