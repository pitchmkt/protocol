// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PrizeConfig} from "../src/PrizeConfig.sol";

/// @title PrizeConfigTest
/// @notice Guards the arithmetic invariants the prize constants are required to satisfy.
/// @dev These are compile-time constants, so there is nothing to deploy in `setUp()`.
contract PrizeConfigTest is Test {
    /// @notice The five tier percentages plus the protocol fee must account for the whole pool.
    /// @dev Documented on {PrizeConfig-PROTOCOL_FEE_PCT} but previously unenforced: a change to
    ///      any single percentage would otherwise silently leave part of the pool unallocated
    ///      or over-allocate it.
    function test_tierPercentagesPlusFeeExhaustThePool() public pure {
        uint256 total = PrizeConfig.TIER6_PRIZE_PCT + PrizeConfig.TIER7_PRIZE_PCT + PrizeConfig.TIER8_PRIZE_PCT
            + PrizeConfig.TIER9_PRIZE_PCT + PrizeConfig.TIER10_PRIZE_PCT + PrizeConfig.PROTOCOL_FEE_PCT;

        assertEq(total, PrizeConfig.PCT_DENOMINATOR, "tier percentages plus fee must equal 100");
    }

    /// @notice The tier count must match the span of winning tiers the percentages describe.
    function test_tierCountMatchesWinningTierSpan() public pure {
        assertEq(PrizeConfig.TIER_COUNT, 5, "five tiers are defined");
        assertEq(
            PrizeConfig.MAX_WINNING_TIER - PrizeConfig.MIN_WINNING_TIER + 1,
            PrizeConfig.TIER_COUNT,
            "tier count must span MIN_WINNING_TIER..MAX_WINNING_TIER"
        );
    }

    /// @notice The lowest tier is deliberately funded above the middle tiers.
    /// @dev Tier 6 holds 3,360 of the 59,049 possible columns against tier 7's 960, so an equal
    ///      share would pay each tier-6 column less than the column cost. Encoded as a test so a
    ///      future "tidy the percentages into a descending ramp" change fails loudly.
    function test_lowestTierIsFundedAboveTheMiddleTiers() public pure {
        assertGt(PrizeConfig.TIER6_PRIZE_PCT, PrizeConfig.TIER7_PRIZE_PCT, "tier 6 outranks tier 7");
        assertGt(PrizeConfig.TIER6_PRIZE_PCT, PrizeConfig.TIER8_PRIZE_PCT, "tier 6 outranks tier 8");
        assertGt(PrizeConfig.TIER6_PRIZE_PCT, PrizeConfig.TIER9_PRIZE_PCT, "tier 6 outranks tier 9");
        assertGt(PrizeConfig.TIER10_PRIZE_PCT, PrizeConfig.TIER6_PRIZE_PCT, "the top tier still leads");
    }
}
