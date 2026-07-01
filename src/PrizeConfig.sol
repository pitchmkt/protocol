// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/// @title PrizeConfig
/// @notice Compile-time constants that define PitchMkt prize distribution rules.
///         All members are `internal` — they are inlined by the compiler and add no
///         deployment or runtime cost. No separate contract is deployed for this library.
library PrizeConfig {
    /// @notice Lowest number of correct predictions that earns a prize.
    uint8 internal constant MIN_WINNING_TIER = 6;

    /// @notice Highest number of correct predictions (perfect score).
    uint8 internal constant MAX_WINNING_TIER = 10;

    /// @notice Number of prize tiers ({MIN_WINNING_TIER} through {MAX_WINNING_TIER} inclusive).
    uint256 internal constant TIER_COUNT = MAX_WINNING_TIER - MIN_WINNING_TIER + 1;

    /// @notice Prize percentage of the pool allocated to tier 6 (6/10 correct).
    uint256 internal constant TIER6_PRIZE_PCT = 7;

    /// @notice Prize percentage of the pool allocated to tier 7 (7/10 correct).
    uint256 internal constant TIER7_PRIZE_PCT = 10;

    /// @notice Prize percentage of the pool allocated to tier 8 (8/10 correct).
    uint256 internal constant TIER8_PRIZE_PCT = 15;

    /// @notice Prize percentage of the pool allocated to tier 9 (9/10 correct).
    uint256 internal constant TIER9_PRIZE_PCT = 25;

    /// @notice Prize percentage of the pool allocated to tier 10 (10/10 correct).
    uint256 internal constant TIER10_PRIZE_PCT = 40;

    /// @notice Denominator used when computing prize shares from percentages.
    uint256 internal constant PCT_DENOMINATOR = 100;
}
