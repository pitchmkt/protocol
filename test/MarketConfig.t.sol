// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DisputeConfig} from "../src/DisputeConfig.sol";
import {MarketConfig} from "../src/MarketConfig.sol";

/// @title MarketConfigTest
/// @notice Guards the arithmetic invariants the market constants are required to satisfy.
/// @dev These are compile-time constants, so there is nothing to deploy in `setUp()`.
contract MarketConfigTest is Test {
    /// @notice The five tier percentages plus the protocol fee must account for the whole pool.
    /// @dev Documented on {MarketConfig-PROTOCOL_FEE_PCT} but previously unenforced: a change to
    ///      any single percentage would otherwise silently leave part of the pool unallocated
    ///      or over-allocate it.
    function test_tierPercentagesPlusFeeExhaustThePool() public pure {
        uint256 total = MarketConfig.TIER6_PRIZE_PCT + MarketConfig.TIER7_PRIZE_PCT + MarketConfig.TIER8_PRIZE_PCT
            + MarketConfig.TIER9_PRIZE_PCT + MarketConfig.TIER10_PRIZE_PCT + MarketConfig.PROTOCOL_FEE_PCT;

        assertEq(total, MarketConfig.PCT_DENOMINATOR, "tier percentages plus fee must equal 100");
    }

    /// @notice The tier count must match the span of winning tiers the percentages describe.
    function test_tierCountMatchesWinningTierSpan() public pure {
        assertEq(MarketConfig.TIER_COUNT, 5, "five tiers are defined");
        assertEq(
            MarketConfig.MAX_WINNING_TIER - MarketConfig.MIN_WINNING_TIER + 1,
            MarketConfig.TIER_COUNT,
            "tier count must span MIN_WINNING_TIER..MAX_WINNING_TIER"
        );
    }

    /// @notice A perfect score is every match correct, so the top tier is the matchweek's size.
    /// @dev {MarketConfig-MAX_WINNING_TIER} is declared as `uint8(MATCH_COUNT)`, so this cannot
    ///      drift today. The assertion stands guard against someone re-hardcoding either one.
    function test_topTierEqualsMatchCount() public pure {
        assertEq(
            uint256(MarketConfig.MAX_WINNING_TIER), MarketConfig.MATCH_COUNT, "a perfect score is every match correct"
        );
    }

    /// @notice The prize band has to be non-empty and fit inside a matchweek.
    /// @dev Guards against a MIN_WINNING_TIER raised above the number of matches played, which
    ///      would make every tier unreachable while every percentage still looked sane.
    function test_winningTierBandFitsInsideAMatchweek() public pure {
        assertLe(MarketConfig.MIN_WINNING_TIER, MarketConfig.MAX_WINNING_TIER, "the prize band must be non-empty");
        assertGt(MarketConfig.MIN_WINNING_TIER, 0, "zero correct predictions cannot win");
    }

    /// @notice {MarketConfig-tierPrizePcts} must report exactly the per-tier constants, in order.
    /// @dev The helper's return type is a `uint256[5]` literal — Solidity rejects a
    ///      library-qualified constant as an array length — so its width is pinned here against
    ///      {MarketConfig-TIER_COUNT}. Adding a tier without widening the helper fails this test
    ///      instead of silently leaving the new tier unfunded in {Matchweek.commitDistribution}.
    function test_tierPrizePctsMirrorsTheIndividualConstants() public pure {
        uint256[5] memory pcts = MarketConfig.tierPrizePcts();

        assertEq(pcts.length, MarketConfig.TIER_COUNT, "one percentage per tier");
        assertEq(pcts[0], MarketConfig.TIER6_PRIZE_PCT, "index 0 is tier 6");
        assertEq(pcts[1], MarketConfig.TIER7_PRIZE_PCT, "index 1 is tier 7");
        assertEq(pcts[2], MarketConfig.TIER8_PRIZE_PCT, "index 2 is tier 8");
        assertEq(pcts[3], MarketConfig.TIER9_PRIZE_PCT, "index 3 is tier 9");
        assertEq(pcts[4], MarketConfig.TIER10_PRIZE_PCT, "index 4 is tier 10");
    }

    /// @notice The perfect-score tier sits at the last index of the per-tier arrays.
    /// @dev {Matchweek.commitDistribution} reads this index to decide whether to release the
    ///      carry pool, so an off-by-one here would pay the carry pool to the wrong tier.
    function test_perfectTierIndexIsTheLastTier() public pure {
        assertEq(MarketConfig.PERFECT_TIER_INDEX, MarketConfig.TIER_COUNT - 1, "the perfect tier is the highest index");
        assertEq(
            MarketConfig.MIN_WINNING_TIER + MarketConfig.PERFECT_TIER_INDEX,
            MarketConfig.MAX_WINNING_TIER,
            "index and tier number must agree"
        );
    }

    /// @notice The lowest tier is deliberately funded above the middle tiers.
    /// @dev Tier 6 holds 3,360 of the 59,049 possible columns against tier 7's 960, so an equal
    ///      share would pay each tier-6 column less than the column cost. Encoded as a test so a
    ///      future "tidy the percentages into a descending ramp" change fails loudly.
    function test_lowestTierIsFundedAboveTheMiddleTiers() public pure {
        assertGt(MarketConfig.TIER6_PRIZE_PCT, MarketConfig.TIER7_PRIZE_PCT, "tier 6 outranks tier 7");
        assertGt(MarketConfig.TIER6_PRIZE_PCT, MarketConfig.TIER8_PRIZE_PCT, "tier 6 outranks tier 8");
        assertGt(MarketConfig.TIER6_PRIZE_PCT, MarketConfig.TIER9_PRIZE_PCT, "tier 6 outranks tier 9");
        assertGt(MarketConfig.TIER10_PRIZE_PCT, MarketConfig.TIER6_PRIZE_PCT, "the top tier still leads");
    }

    /// @notice The hardcoded stablecoin amounts must stay the token figures their NatSpec claims.
    /// @dev Both are written as multiples of {MarketConfig-STABLECOIN_UNIT}. This pins the token
    ///      figures so a change to the unit — deploying against an 18-decimal stablecoin, say —
    ///      is visibly a change to the unit alone and not to the prices themselves.
    function test_stablecoinAmountsArePricedInWholeUnits() public pure {
        assertEq(MarketConfig.UNIT_PRICE, 2 * MarketConfig.STABLECOIN_UNIT, "a column costs 2 tokens");
        assertEq(DisputeConfig.DISPUTE_BOND, 50 * MarketConfig.STABLECOIN_UNIT, "a dispute bond is 50 tokens");
    }
}
