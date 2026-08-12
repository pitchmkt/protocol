// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/// @title MarketConfig
/// @author PitchMkt
/// @notice Compile-time constants that define PitchMkt's market parameters: the size of a
///         matchweek, the price of a column, and the prize distribution rules.
///         All members are `internal` — they are inlined by the compiler and add no
///         deployment or runtime cost. No separate contract is deployed for this library.
/// @dev Solidity rejects a library-qualified constant as a fixed-array length, so {Matchweek}
///      spells its array lengths as the literals 10 and 5 rather than {MATCH_COUNT} and
///      {TIER_COUNT}. `MarketConfig.t.sol` asserts those literals against these constants, so a
///      change here that the array types do not follow fails the test suite.
library MarketConfig {
    /// @notice One whole unit of the stablecoin predictions are paid in: 1 USDC (6 decimals).
    /// @dev Every stablecoin amount the protocol hardcodes is denominated against this, here and
    ///      in {DisputeConfig}. A token with different decimals means changing this constant
    ///      alone, not hunting down each amount.
    uint256 internal constant STABLECOIN_UNIT = 1e6;

    /// @notice Number of matches per matchweek.
    /// @dev The source of truth for the size of a matchweek: {MAX_WINNING_TIER} derives from it.
    uint256 internal constant MATCH_COUNT = 10;

    /// @notice Price of a single column: 2 USDC.
    /// @dev A prediction pays this price per column it covers, so its cost scales with how many
    ///      outcome combinations it plays. Each winner's prize share is proportional to what its
    ///      winning columns cost (see {Matchweek.claimPrize}), not split evenly by winner count.
    uint256 internal constant UNIT_PRICE = 2 * STABLECOIN_UNIT;

    /// @notice Lowest number of correct predictions that earns a prize.
    uint8 internal constant MIN_WINNING_TIER = 6;

    /// @notice Highest number of correct predictions (a perfect score).
    /// @dev A perfect score is every match correct, so this is {MATCH_COUNT} by definition rather
    ///      than an independent knob. Widening a matchweek moves the top tier with it.
    ///      Narrowed to `uint8` because tier numbers are carried as `uint8` throughout, notably by
    ///      {Matchweek.claimPrize}'s loop and the {Matchweek.EmptyTierPool} error.
    // casting to 'uint8' is safe because a matchweek of more than 255 matches is not a thing this
    // protocol can price: 3**256 columns would overflow the cost arithmetic long before the cast.
    // forge-lint: disable-next-line(unsafe-typecast)
    uint8 internal constant MAX_WINNING_TIER = uint8(MATCH_COUNT);

    /// @notice Number of prize tiers ({MIN_WINNING_TIER} through {MAX_WINNING_TIER} inclusive).
    uint256 internal constant TIER_COUNT = MAX_WINNING_TIER - MIN_WINNING_TIER + 1;

    /// @notice Index of the perfect-score tier in the per-tier arrays (tier 10 → index 4).
    /// @dev The tier that releases the carry pool when it has winners.
    uint256 internal constant PERFECT_TIER_INDEX = TIER_COUNT - 1;

    /// @notice Prize percentage of the pool allocated to tier 6 (6/10 correct).
    /// @dev Deliberately larger than the middle tiers. Tier 6 holds by far the most winning
    ///      columns, so a flat share would leave each one below the price of the column that
    ///      won it. La Quiniela allocates its lowest category more than its middle ones for
    ///      the same reason.
    uint256 internal constant TIER6_PRIZE_PCT = 19;

    /// @notice Prize percentage of the pool allocated to tier 7 (7/10 correct).
    uint256 internal constant TIER7_PRIZE_PCT = 15;

    /// @notice Prize percentage of the pool allocated to tier 8 (8/10 correct).
    uint256 internal constant TIER8_PRIZE_PCT = 15;

    /// @notice Prize percentage of the pool allocated to tier 9 (9/10 correct).
    uint256 internal constant TIER9_PRIZE_PCT = 15;

    /// @notice Prize percentage of the pool allocated to tier 10 (10/10 correct).
    uint256 internal constant TIER10_PRIZE_PCT = 33;

    /// @notice Percentage of the pool retained by the protocol as a fee.
    /// @dev The tier percentages and this fee are exhaustive:
    ///      `TIER6 + TIER7 + TIER8 + TIER9 + TIER10 + PROTOCOL_FEE_PCT == PCT_DENOMINATOR`.
    ///      Any change to one constant must preserve that invariant.
    uint256 internal constant PROTOCOL_FEE_PCT = 3;

    /// @notice Denominator used when computing prize shares from percentages.
    uint256 internal constant PCT_DENOMINATOR = 100;

    /// @notice The prize percentage of every tier, ordered from {MIN_WINNING_TIER} upwards.
    /// @dev Solidity has no constant arrays, so the per-tier percentages are declared one by one
    ///      above and assembled here. Keeping the assembly next to the declarations means a tier
    ///      added or reweighted is caught in this file instead of drifting from a copy in
    ///      {Matchweek.commitDistribution}.
    /// @return The five tier percentages, indices 0–4 mapping to tiers 6–10.
    function tierPrizePcts() internal pure returns (uint256[5] memory) {
        return [TIER6_PRIZE_PCT, TIER7_PRIZE_PCT, TIER8_PRIZE_PCT, TIER9_PRIZE_PCT, TIER10_PRIZE_PCT];
    }
}
