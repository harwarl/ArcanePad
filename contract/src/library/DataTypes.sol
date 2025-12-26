// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

/**
 * @title DataTypes
 * @notice Shared data structures for IDO system
 */

library DataTypes {
    struct PoolConfig {
        address tokenAddress; // Token being sold
        uint256 tokenPrice; // Price in payment token
        uint256 softCap; // Minimum raise target
        uint256 hardCap; // Maximum raise target
        uint256 minContribution; // Min amount per wallet
        uint256 maxContribution; // Max amount per wallet
        uint256 startTime; // Sale start timestamp
        uint256 endTime; // Sale end Timestamp
        address paymentToken; // Token Used for payment
        bool whitelistEnabled; // Whether whitelist is required
        uint8 vestingType; // 0-immediate, 1-linear, 2=cliff+linear, 3=milestone
    }

    struct VestingConfig {
        uint256 tgePercent; // Percent unlocked at tge
        uint256 cliff; // Cliff period in seconds
        uint256 vestingDuration; // Total Vesting duration after cliff
        uint256 vestingInterval; // Interval for linear unlock (3.g 30 days)
    }

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
}