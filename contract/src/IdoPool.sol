// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./interfaces/IPool.sol";
import "./library/DataTypes.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract IDOPool is IPool, Pausable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // ======================== STATE VARIABLES ========================
    // IDO Factory Address
    address public factory;

    // Current Pool status
    PoolStatus public status;

    // Current Pool Initialized state
    bool private _initialized;

    // Pool information struct
    DataTypes.PoolInfo public poolInfo;

    // Vesting information
    DataTypes.VestingConfig public vestingConfig;

    // WhiteList Root
    bytes32 public whitelistRoot;

    // whiteList enabled
    bool public whitelistEnabled;

    address public creator;
    address public stakingTiersContract;
    address public feeCollector;
    uint256 private platformFeeBps;
    address[] public participants;

    mapping(address => uint256) public contributions;
    mapping(address => uint256) public tokenAllocations;
    mapping(address => bool) public hasClaimedRefund;
    mapping(uint8 => uint256) public tierAllocations;

    // constructor
    constructor() {
        factory = _msgSender();
    }

    /**
     * @notice Initialize the pool with configuration
     * @dev Can only be called once, by factory
     * @param _poolConfig Pool configuration struct
     * @param _vestingConfig Vesting configuration struct
     * @param _whitelistRoot Merkle root for whitelist
     * @param _creator Pool creator address
     * @param _stakingTiers Staking tiers contract address
     * @param _feeCollector Fee collector address
     * @param _platformFeeBps Platform fee in basis points
     */
    function initialize(
        DataTypes.PoolConfig calldata _poolConfig,
        DataTypes.VestingConfig calldata _vestingConfig,
        bytes32 _whitelistRoot,
        bool _whitelistEnabled,
        address _creator,
        address _stakingTiers,
        address _feeCollector,
        uint256 _platformFeeBps
    ) external {
        require(factory == _msgSender(), "IDOPool: only factory can initialize");
        require(!_initialized, "IDOPool: Pool Already Initialized");

        // Split into internal functions to reduce stack depth
        _initializePoolConfig(_poolConfig);
        _initializeAddresses(_creator, _stakingTiers, _feeCollector, _platformFeeBps);
        _initializeVesting(_vestingConfig, _whitelistRoot);

        _initialized = true;
        whitelistEnabled = _whitelistEnabled;

        emit PoolInitialized(_creator, _poolConfig.tokenAddress, _poolConfig.paymentToken);
    }

    /**
     * @notice Participate in the IDO sale
     * @param amount Amount of the payment token to contribute
     * @param merkleProof Proof for whitelist verification (if enabled)
     */
    function participate(uint256 amount, bytes32[] calldata merkleProof) external nonReentrant whenNotPaused {
        _canParticipate(amount, merkleProof);

        // Calculate token allocation
        uint256 tokensToAllocate = _calculateTokenAllocation(amount);
        require(tokensToAllocate > 0, "IDOPool: Invalid Token Allocation");

        // Track new Participant
        if (contributions[_msgSender()] == 0) {
            participants.push(_msgSender());
            poolInfo.totalParticipants++;
        }

        // Update State
        contributions[_msgSender()] += amount;
        tokenAllocations[_msgSender()] += tokensToAllocate;
        poolInfo.totalRaised += amount;

        // Transfer Payment
        IERC20(poolInfo.paymentToken).safeTransferFrom(_msgSender(), address(this), amount);

        emit Participated(_msgSender(), amount, tokensToAllocate, block.timestamp);
    }

    /**
     * @notice Participate with native token (ETH/MATIC)
     * @param merkleProof Proof for whitelise verification (if enabled)
     */
    function participateWithNative(bytes32[] calldata merkleProof) external payable nonReentrant whenNotPaused {
        // Validate Native Token is Accepted
        require(poolInfo.paymentToken == address(0), "IDOPool: Native token not accepted");
        uint256 amount = msg.value;

        _canParticipate(amount, merkleProof);

        // Calculate token allocation
        uint256 tokensToAllocate = _calculateTokenAllocation(amount);
        require(tokensToAllocate > 0, "IDOPool: Invalid Token Allocation");

        // Track new Participant
        if (contributions[_msgSender()] == 0) {
            participants.push(_msgSender());
            poolInfo.totalParticipants++;
        }

        // Update State
        contributions[_msgSender()] += amount;
        tokenAllocations[_msgSender()] += tokensToAllocate;
        poolInfo.totalRaised += amount;

        emit Participated(_msgSender(), amount, tokensToAllocate, block.timestamp);
    }

    /**
     * @notice Claim allocated tokens after pool finalization
     */
    function claimTokens() external {}

    /**
     * @notice Claim refund if pool failed or was cancelled
     */
    function claimRefund() external {}

    /**
     * @notice Get Current pool status
     * @return Current status of the pool
     */
    function getPoolStatus() external view returns (PoolStatus) {
        return status;
    }

    /**
     * @notice Get complete pool information
     * @return Pool configuration and state
     */
    function getPoolInfo() external view returns (DataTypes.PoolInfo memory) {
        return poolInfo;
    }

    /**
     * @notice Get the user's participation information
     * @param user Address of the user
     * @return User's contribution and allocation details
     */
    function getUserInfo(address user) external view returns (DataTypes.UserInfo memory) {
        return DataTypes.UserInfo({
            contribution: contributions[user],
            totalAllocation: tokenAllocations[user],
            hasClaimedRefund: hasClaimedRefund[user],
            hasClaimedTokens: false,
            guaranteedAllocation: 200
        });
    }

    /**
     * @notice Calculate the token user would receive for an amount
     * @param paymentTokenAmmount Amount of payment token
     * @return Amount of tokens to be allocated
     */
    function calculateTokenAllocation(uint256 paymentTokenAmmount) external view returns (uint256) {
        _calculateTokenAllocation(paymentTokenAmmount);
    }

    /**
     * @notice Get user's tier from staking contract
     * @param user Address of the user
     * @return Tier Level (0-5)
     */
    function getUserTier(address user) external view returns (uint8) {
        return 2;
    }

    /**
     * @notice Check if user is whitelisted
     * @param user address to check
     * @param merkleProof Merkle Proof for verification
     */
    function isWhitelisted(address user, bytes32[] calldata merkleProof) external view returns (bool) {
        _verifyWhitelist(user, merkleProof);
    }

    /**
     * @notice Get Guaranteed allocation for a tier
     * @param tier Tier Level
     * @return Allocation amount in payment token
     */
    function getTierAllocation(uint8 tier) external view returns (uint256) {}

    /**
     * @notice Get remaining allocation available
     * @return Available amount that can still be raised
     */
    function getRemainingAllocation() external view returns (uint256) {}

    /**
     * @notice Gets the list of all participants
     * @return Array of participant addresses
     */
    function getAllParticipants() external view returns (address[] memory) {
        return participants;
    }

    /**
     * @notice Get progress percentahe (raised/hardcap)
     * @return Progress in Basis Point (10000 = 100%)
     */
    function getProgress() external view returns (uint256) {}

    /**
     * @notice check if soft cap was reached
     * @return True if soft cap met
     */
    function isSoftCapReached() external view returns (bool) {
        return poolInfo.totalRaised >= poolInfo.softCap;
    }

    /**
     * @notice check if hard cap was reached
     * @return True if hard cap met
     */
    function isHardCapReached() external view returns (bool) {
        return poolInfo.totalRaised == poolInfo.hardCap;
    }

    /**
     * @notice Get Time remaining until end
     * @return Seconds remaining (0 if ended)
     */
    function getTimeRemaining() external view returns (uint256) {
        return poolInfo.endTime - poolInfo.startTime;
    }

    // ======================== ADMIN FUNCTIONS ========================
    /**
     * @notice Finalize the pool after end time
     * @dev can only be called after end time if soft cap reached
     */
    function finalize() external {}

    /**
     * @notice Cancel the pool (emerygency only)
     * @dev can only be called by the factory or creator
     */
    function cancel() external {}

    /**
     * @notice Update whitelist merkle root
     * @param newMerkleRoot New Merkle roor for whitelist
     */
    function updateWhitelist(bytes32 newMerkleRoot) external {
        whitelistRoot = newMerkleRoot;
    }

    /**
     * @notice Set tier allocation
     * @param tiers Array of tier levels
     * @param allocations Array of allocation amounts
     */
    function setTierAllocations(uint8[] calldata tiers, uint256[] calldata allocations) external {}

    /**
     * @notice Withdraw raised funds (after finalization)
     * @param to Address to send funds
     */
    function withdrawRaisedFunds(address to) external {}

    /**
     * @notice Emergency withdraw tokens (only unsold tokens)
     * @param token Token address to withdraw
     * @param to Address to send to
     */
    function emergencyWithdrawTokens(address token, address to) external {}

    /**
     * @notice Pause the pool
     */
    function pause() external {
        super._pause();
    }

    /**
     * @notice Unpause the pool
     */
    function unpause() external {
        super._unpause();
    }

    // ======================== INTERNAL FUNCTIONS ========================
    /**
     * @notice Verify Merkle proof for whitelist
     * @param user Address to verify
     * @param merkleProof  Proof Array
     * @return True if proof is valid
     */
    function _verifyWhitelist(address user, bytes32[] calldata merkleProof) internal view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(user));
        return MerkleProof.verify(merkleProof, whitelistRoot, leaf);
    }

    /**
     * @notice Calculate tokens to allocate
     * @param paymentAmount Purchase Token amount
     * @return Amount of token allocated
     */
    function _calculateTokenAllocation(uint256 paymentAmount) internal returns (uint256) {
        // get Token decimals
        uint256 paymentDecimals = IERC20Metadata(poolInfo.paymentToken).decimals();
        uint256 tokenDecimals = IERC20Metadata(poolInfo.token).decimals();

        // Formula tokens = (paymentAmount * 10^tokenDecimals) / tokenPrice
        uint256 tokensAllocated;

        if (tokenDecimals >= paymentDecimals) {
            // Scale up
            tokensAllocated = (paymentAmount * 10 ** (tokenDecimals - paymentDecimals) * 1e18) / poolInfo.tokenPrice;
        } else {
            // Scale down
            tokensAllocated = (paymentAmount * 1e18) / (poolInfo.tokenPrice * 10 ** (paymentDecimals - tokenDecimals));
        }

        return tokensAllocated;
    }

    /**
     * @notice Calculate platform fee
     * @param amount Amount to calculate fee on
     * @return fee amount
     */
    function _calculatePlatformFee(uint256 amount) internal view returns (uint256) {}

    /**
     * @notice transfer tokens with fee deduction
     * @param to Recipeint Address
     * @param amount Amount to transfer
     */
    function _transferWithFee(address to, uint256 amount) internal {}

    /**
     * @dev Internal function to set pool configuration
     */
    function _initializePoolConfig(DataTypes.PoolConfig calldata config) private {
        DataTypes.PoolInfo memory _poolInfo = DataTypes.PoolInfo({
            token: config.tokenAddress,
            paymentToken: config.paymentToken,
            tokenPrice: config.tokenPrice,
            softCap: config.softCap,
            hardCap: config.hardCap,
            minContribution: config.minContribution,
            maxContribution: config.maxContribution,
            startTime: config.startTime,
            endTime: config.endTime,
            totalRaised: 0,
            totalParticipants: 0,
            finalized: false,
            cancelled: false
        });

        poolInfo = _poolInfo;
    }

    /**
     * @dev Internal function to set addresses
     */
    function _initializeAddresses(
        address _creator,
        address _stakingTiers,
        address _feeCollector,
        uint256 _platformFeeBps
    ) private {
        creator = _creator;
        stakingTiersContract = _stakingTiers;
        feeCollector = _feeCollector;
        platformFeeBps = _platformFeeBps;
    }

    /**
     * @dev Internal function to set vesting config
     */
    function _initializeVesting(DataTypes.VestingConfig calldata config, bytes32 _whitelistRoot) private {
        vestingConfig = config;
        whitelistRoot = _whitelistRoot;
    }

    /**
     * @notice validate pool and amount
     * @param amount payment token amount
     * @param merkleProof merkle Proof
     */
    function _canParticipate(uint256 amount, bytes32[] calldata merkleProof) private {
        // timestamp checks
        require(block.timestamp >= poolInfo.startTime, "IDOPool: Sales not started");
        require(block.timestamp < poolInfo.endTime, "IDOPool: Sales ended");

        // pool state checks
        require(_initialized, "IDOPool: Initialized");
        require(!poolInfo.cancelled, "IDOPool: Cancelled");
        require(!poolInfo.finalized, "IDOPool: Finalized");
        require(poolInfo.totalRaised < poolInfo.hardCap, "IDOPool: HardCap Reached");

        // White list checks
        if (whitelistEnabled) {
            require(_verifyWhitelist(_msgSender(), merkleProof), "IDOPool: Not whitelisted");
        }

        // contribution checks
        require(amount > 0, "IDOPool: Amount must be greater than 0");
        require(amount >= poolInfo.minContribution, "IDOPool: Below minimum contribution");
        uint256 userTotalContribution = contributions[_msgSender()].add(amount);
        require(userTotalContribution <= poolInfo.maxContribution, "IDOPool: Exceeds maximum contributions per wallet");

        // Hard cap checks
        uint256 newTotalRaised = amount.add(poolInfo.totalRaised);
        require(newTotalRaised <= poolInfo.hardCap, "IDOPool: Contribution exceeds hardcap");
    }
}
