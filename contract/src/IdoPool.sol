// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./interfaces/IPool.sol";
import "./library/DataTypes.sol";
import "./vesting/Vesting.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract IDOPool is IPool, Pausable, ReentrancyGuard, AccessControl, Ownable2Step {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // ======================== STATE VARIABLES ========================

    // OPERATOR_ROLE
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // IDO Factory Address
    address public factory;

    // // Current Pool status
    // PoolStatus public status;

    // Current Pool Initialized state
    bool private _initialized;

    // Pool information struct
    DataTypes.PoolInfo public poolInfo;

    // Vesting information
    DataTypes.VestingConfig public vestingConfig;

    // whiteList enabled
    bool public whitelistEnabled;

    // Creator Address
    address public creator;

    address public stakingTiersContract;
    // Address to collect platform fee
    address public feeCollector;
    // Address of the vesting contract
    Vesting public vesting;
    // Platform fee Basis point
    uint256 private platformFeeBps;
    // participants of the sale
    address[] public participants;
    // Total token allocation
    uint256 private totalAllocations;

    mapping(address => uint256) public contributions;
    mapping(address => uint256) public tokenAllocations;
    mapping(address => bool) public hasClaimedRefund;
    mapping(address => bool) public hasClaimedTokens;
    mapping(uint8 => uint256) public tierAllocations;
    mapping(address => bytes32) private userVestingScheduleId;

    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), "IDOPool: Not Operator");
        _;
    }

    modifier onlyFactory() {
        require(_msgSender() == factory, "IDOPool: Only Factory");
        _;
    }

    // constructor set the factory address
    constructor() {
        factory = _msgSender();
    }

    /**
     * @dev Add an account to the operator role.
     * @param account address
     */
    function addOperator(address account) public onlyOwner {
        require(!hasRole(OPERATOR_ROLE, account), "IDOPool: Is Operator");
        grantRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Remove an account from the operator role.
     * @param account address
     */
    function removeOperator(address account) public onlyOwner {
        require(hasRole(OPERATOR_ROLE, account), "IDOPool: Not an Operator");
        revokeRole(OPERATOR_ROLE, account);
    }

    /**
     * @dev Check if an account is operator.
     * @param account address
     */
    function checkOperator(address account) public view returns (bool) {
        return hasRole(OPERATOR_ROLE, account);
    }

    /**
     * @notice Initialize the pool with configuration
     * @dev Can only be called once, by factory
     * @param _poolConfig Pool configuration struct
     * @param _vestingConfig Vesting configuration struct
     * @param _creator Pool creator address
     * @param _feeCollector Fee collector address
     * @param _vesting The vesting contract address
     * @param _platformFeeBps Platform fee in basis points
     */
    function initialize(
        DataTypes.PoolConfig calldata _poolConfig,
        DataTypes.VestingConfig calldata _vestingConfig,
        bool _whitelistEnabled,
        address _creator,
        address _feeCollector,
        address _vesting,
        uint256 _platformFeeBps
    ) external onlyFactory {
        require(!_initialized, "IDOPool: Pool Already Initialized");

        // Split into internal functions to reduce stack depth
        _initializePoolConfig(_poolConfig);
        _initializeAddresses(_creator, _feeCollector, _platformFeeBps);
        _initializeVesting(_vestingConfig);

        vesting = Vesting(payable(_vesting));

        _initialized = true;
        whitelistEnabled = _whitelistEnabled;

        emit PoolInitialized(_creator, _poolConfig.tokenAddress, _poolConfig.paymentToken);
    }

    /**
     * @notice Participate in the IDO sale
     * @param amount Amount of the payment token to contribute
     */
    function participate(uint256 amount) external nonReentrant whenNotPaused {
        _canParticipate(amount);

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
        totalAllocations = totalAllocations.add(amount);
        poolInfo.totalRaised += amount;

        // Transfer Payment
        IERC20(poolInfo.paymentToken).safeTransferFrom(_msgSender(), address(this), amount);

        emit Participated(_msgSender(), amount, tokensToAllocate, block.timestamp);
    }

    /**
     * @notice Participate with native token (ETH/MATIC)
     */
    function participateWithNative() external payable nonReentrant whenNotPaused {
        // Validate Native Token is Accepted
        require(poolInfo.paymentToken == address(0), "IDOPool: Native token not accepted");
        uint256 amount = msg.value;

        _canParticipate(amount);

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
        totalAllocations += amount;
        poolInfo.totalRaised += amount;

        emit Participated(_msgSender(), amount, tokensToAllocate, block.timestamp);
    }

    /**
     * @notice Claim allocated tokens after pool finalization
     */
    function claimTokens() external nonReentrant {
        // validation checks
        require(poolInfo.finalized, "IDOPool: Pool not finalized");
        require(poolInfo.totalRaised >= poolInfo.softCap, "IDOPool: Soft cap not reached");
        require(!poolInfo.cancelled, "IDOPool: Pool was cancelled");
        require(tokenAllocations[_msgSender()] > 0, "IDOPool: No Tokens allocated");
        require(!hasClaimedTokens[_msgSender()], "IDOPool: Tokens already claimed");

        uint256 totalAllocation = tokenAllocations[_msgSender()];
        uint256 vestingTgePercent = vestingConfig.tgePercent;

        if (vestingTgePercent == 10000) {
            IERC20(poolInfo.token).safeTransfer(_msgSender(), totalAllocation);
            emit TokensClaimed(_msgSender(), totalAllocation, block.timestamp);
        } else {
            // Handle Vesting with the vesting contract
            uint256 tgeAmount = (vestingTgePercent * totalAllocation) / 10000;
            uint256 vestingAmount = totalAllocation - tgeAmount;

            // Tranfer TGE Amount immediately
            if (tgeAmount > 0) {
                IERC20(poolInfo.token).safeTransfer(_msgSender(), tgeAmount);
                emit TokensClaimed(_msgSender(), totalAllocation, block.timestamp);
            }

            // Create a vesting scehdule for remaining tokens
            if (vestingAmount > 0) {
                // Apporve vesting contract to spend tokens
                IERC20(poolInfo.token).safeApprove(address(vesting), vestingAmount);

                // Tranfer tokens to vesting contract
                IERC20(poolInfo.token).safeTransfer(address(vesting), vestingAmount);

                // Create vesting schedule

                vesting.createVestingSchedule(
                    _msgSender(),
                    vestingConfig.cliff,
                    block.timestamp,
                    vestingConfig.vestingDuration,
                    vestingConfig.vestingInterval,
                    false,
                    vestingAmount
                );

                // Store schedule ID
                bytes32 scheduleId = vesting.computeVestingScheduleIdForAddressAndIndex(
                    _msgSender(), vesting.getVestingScheduleCountByBeneficiary(_msgSender())
                );

                userVestingScheduleId[_msgSender()] = scheduleId;

                emit VestingScheduleCreated(
                    _msgSender(), vestingAmount, vestingConfig.cliff, vestingConfig.vestingDuration, block.timestamp
                );
            }
        }
    }

    /**
     * @notice Claim refund if pool failed or was cancelled
     */
    function claimRefund() external nonReentrant {
        bool isFailed = (block.timestamp > poolInfo.endTime && poolInfo.totalRaised < poolInfo.softCap);
        bool isCancelled = poolInfo.cancelled;

        require(isFailed || isCancelled, "IDOPool: Pool not failed or cancelled");

        // Check users contribution
        uint256 userContribution = contributions[_msgSender()];
        require(userContribution > 0, "IDOPool: No contribution to refund");

        // Check if user has already claimed refund
        require(!hasClaimedRefund[_msgSender()], "IDOPool: Refund already claimed");

        // Process Refund
        // Update the state
        hasClaimedRefund[_msgSender()] = true;

        // Transfer refund based on the payment token
        if (poolInfo.token == address(0)) {
            (bool success,) = _msgSender().call{value: userContribution}("");
            require(success, "IDOPool: Native toke transfer failed");
        } else {
            // ERC20 token refund
            IERC20(poolInfo.paymentToken).safeTransfer(_msgSender(), userContribution);
        }

        emit RefundClaimed(_msgSender(), userContribution, block.timestamp);
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
            guaranteedAllocation: 230 // TODO: add function to get the guaranteed Allocation
        });
    }

    /**
     * @notice Calculate the token user would receive for an amount
     * @param paymentTokenAmount Amount of payment token
     * @return Amount of tokens to be allocated
     */
    function calculateTokenAllocation(uint256 paymentTokenAmount) external view returns (uint256) {
        return _calculateTokenAllocation(paymentTokenAmount);
    }

    /**
     * @notice Check if user is whitelisted
     * @param user address to check
     */
    function isWhitelisted(address user) external view returns (bool) {
        return _verifyWhitelist(user);
    }

    /**
     * @notice Get remaining allocation available
     * @return Available amount that can still be raised
     */
    function getRemainingAllocation() external view returns (uint256) {
        return poolInfo.hardCap - poolInfo.totalRaised;
    }

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
    function getProgress() external view returns (uint256) {
        if (poolInfo.hardCap == 0) {
            return 0;
        }
        return (poolInfo.totalRaised * 10000) / poolInfo.hardCap;
    }

    // ======================== ADMIN FUNCTIONS ========================
    /**
     * @notice Finalize the pool after end time
     * @dev can only be called after end time if soft cap reached
     */
    function finalize() external onlyOperator {
        require(block.timestamp >= poolInfo.endTime, "IDOPool: Sales still ongoing");
        require(!poolInfo.cancelled, "IDOPool: Pool Cancelled");
        require(!poolInfo.finalized, "IDOPool: Pool Finalized");
        require(poolInfo.totalRaised >= poolInfo.softCap, "IDOPool: Soft cap not met");

        // Mark as finalized first
        poolInfo.finalized = true;

        _transferWithFee();

        // Verify Token Balance
        uint256 totalTokensNeeded = _getTotalTokenAllocations();
        uint256 contractTokenBalance = IERC20(poolInfo.token).balanceOf(address(this));

        require(contractTokenBalance >= totalTokensNeeded, "IDOPool: Insufficient IDO Tokens");

        emit PoolFinalized(poolInfo.totalRaised, poolInfo.totalParticipants, block.timestamp);
    }

    /**
     * @notice Cancel the pool (emerygency only)
     * @dev can only be called by the factory or creator
     */
    function cancel() external onlyOperator {
        require(!poolInfo.cancelled, "IDOPool: Pool Cancelled");
        require(!poolInfo.finalized, "IDOPool: Pool Finalized");

        // mark as cancelled
        poolInfo.cancelled = true;

        // return unsold tokens to the creator
        uint256 contractTokenBalance = IERC20(poolInfo.token).balanceOf(address(this));

        if (contractTokenBalance > 0) {
            IERC20(poolInfo.token).safeTransfer(creator, contractTokenBalance);
        }

        // Emit Event
        emit PoolCancelled(_msgSender(), block.timestamp);
    }

    /**
     * @notice Emergency withdraw tokens (only unsold tokens)
     * @param token Token address to withdraw
     * @param to Address to send to
     */
    function emergencyWithdrawTokens(address token, address to) external nonReentrant onlyOperator {
        require(token != address(0), "IDOPool: Invalid token");
        require(to != address(0), "IDOPool: Invalid recipient");

        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        require(tokenBalance > 0, "IDOPool: No tokens to withdraw");

        if (token == poolInfo.paymentToken) {
            // can only withdraw if:
            // - Pool is cancelled OR Pool Ended + 30 days passed
            bool canWithdraw = poolInfo.cancelled || (block.timestamp > poolInfo.endTime + 30 days);

            require(canWithdraw, "IDOPool: Payment token locked");
            require(tokenBalance > poolInfo.totalRaised, "IDOPool: No excess payment tokens");

            uint256 withdrawAmount = tokenBalance - poolInfo.totalRaised;
            IERC20(token).safeTransfer(to, withdrawAmount);

            emit EmergencyWithdraw(token, withdrawAmount, to, block.timestamp);
        }

        if (token == poolInfo.token) {
            // Can only withdraw if pool is cancelled or finalized
            if (poolInfo.cancelled) {
                IERC20(token).safeTransfer(to, tokenBalance);
                emit EmergencyWithdraw(token, tokenBalance, to, block.timestamp);
            }

            if (poolInfo.finalized) {
                // Only withdraw unsold tokens
                // Get total allocations
                uint256 allocated = _getTotalTokenAllocations();
                require(tokenBalance > allocated, "IDOPool: No excess tokens");

                uint256 withdrawAmount = tokenBalance - allocated;
                IERC20(token).safeTransfer(to, withdrawAmount);
                emit EmergencyWithdraw(token, withdrawAmount, to, block.timestamp);
                return;
            }
            revert("IDOPool: IDO token is locked");
        }

        // Transfer other tokens out
        IERC20(token).safeTransfer(to, tokenBalance);
        emit EmergencyWithdraw(token, tokenBalance, to, block.timestamp);
    }

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
     * @return True if proof is valid
     */
    function _verifyWhitelist(address user) internal view returns (bool) {
        // CHeck is user is in whitelist array
    }

    /**
     * @notice Calculate tokens to allocate
     * @param paymentAmount Purchase Token amount
     * @return Amount of token allocated
     */
    function _calculateTokenAllocation(uint256 paymentAmount) internal view returns (uint256) {
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
    function _calculatePlatformFee(uint256 amount) internal view returns (uint256) {
        return (amount * platformFeeBps) / 10000;
    }

    /**
     * @notice transfer tokens with fee deduction
     */
    function _transferWithFee() internal {
        // Calculate amount and remove platform fees
        uint256 totalRaised = poolInfo.totalRaised;
        uint256 platformFee = _calculatePlatformFee(totalRaised);
        uint256 creatorAmount = totalRaised - platformFee;

        // Verify amounts
        require(platformFee + creatorAmount == totalRaised, "IDOPool: Amount mismatch");
        // Tranfer raised funds
        _transferRaisedFunds(platformFee, creatorAmount);
    }

    /**
     * @notice Transfer raised funds to fee collector and creator
     * @param platformFee Fee amount for platform
     * @param creatorAmount Amount for pool creator
     */
    function _transferRaisedFunds(uint256 platformFee, uint256 creatorAmount) internal {
        // if paymentToken is native
        if (poolInfo.paymentToken == address(0)) {
            if (platformFee > 0) {
                // Transfer Fee to the feeCollector
                (bool feeSuccess,) = feeCollector.call{value: platformFee}("");
                require(feeSuccess, "IDOPool: Fee Transfer failed");
            }

            if (creatorAmount > 0) {
                (bool creatorSuccess,) = creator.call{value: creatorAmount}("");
                require(creatorSuccess, "IDOPool: Creator transfer failed");
            }
        } else {
            // ERC20 transfer
            if (platformFee > 0) {
                IERC20(poolInfo.paymentToken).safeTransfer(feeCollector, platformFee);
            }
            if (creatorAmount > 0) IERC20(poolInfo.token).safeTransfer(creator, creatorAmount);
        }
    }

    /**
     * @notice get total token allocations for all participants
     * @return Total tokens allocated
     */
    function _getTotalTokenAllocations() internal view returns (uint256) {
        uint256 total = 0;
        uint256 participantCount = participants.length;

        for (uint256 i = 0; i < participantCount; i++) {
            total += tokenAllocations[participants[i]];
        }

        return total;
    }

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
    function _initializeAddresses(address _creator, address _feeCollector, uint256 _platformFeeBps) private {
        creator = _creator;
        feeCollector = _feeCollector;
        platformFeeBps = _platformFeeBps;
    }

    /**
     * @dev Internal function to set vesting config
     */
    function _initializeVesting(DataTypes.VestingConfig calldata config) private {
        vestingConfig = config;
    }

    /**
     * @notice validate pool and amount
     * @param amount payment token amount
     */
    function _canParticipate(uint256 amount) private view {
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
            require(_verifyWhitelist(_msgSender()), "IDOPool: Not whitelisted");
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
