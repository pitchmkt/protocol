// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {MarketConfig} from "./MarketConfig.sol";

/// @title DisputeConfig
/// @author PitchMkt
/// @notice Compile-time constants that define PitchMkt's dispute window rules.
///         All members are `internal` — they are inlined by the compiler and add no
///         deployment or runtime cost. No separate contract is deployed for this library.
/// @dev Kept apart from {MarketConfig} because {Disputes} is its only consumer, and {Matchweek}
///      has no business importing dispute parameters. The one thing the two share is the
///      stablecoin's unit, which lives in {MarketConfig}.
library DisputeConfig {
    /// @notice Length of the window, starting at result publication, during which a matchweek's
    ///         results can be disputed.
    uint40 internal constant DISPUTE_WINDOW = 48 hours;

    /// @notice Fixed stablecoin bond required to open a dispute: 50 USDC.
    /// @dev Placeholder MVP value — tune before mainnet launch. Priced in
    ///      {MarketConfig.STABLECOIN_UNIT} so the amount stays 50 tokens whatever the stablecoin's
    ///      decimals are, instead of restating them here.
    uint256 internal constant DISPUTE_BOND = 50 * MarketConfig.STABLECOIN_UNIT;
}
