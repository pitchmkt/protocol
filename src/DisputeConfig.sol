// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/// @title DisputeConfig
/// @author PitchMkt
/// @notice Compile-time constants that define PitchMkt's dispute window rules.
///         All members are `internal` — they are inlined by the compiler and add no
///         deployment or runtime cost. No separate contract is deployed for this library.
/// @dev Kept apart from {MarketConfig} because {Disputes} is its only consumer, and {Matchweek}
///      has no business importing dispute parameters. Neither library imports the other: each
///      declares its own {STABLECOIN_DECIMALS}.
library DisputeConfig {
    /// @notice Decimals of the stablecoin disputes are bonded in.
    /// @dev Declared here rather than imported, so this library stands alone. The protocol runs on
    ///      a single stablecoin — the deploy script resolves one address and hands it to both
    ///      {Disputes} and {Matchweek} — so this must always equal
    ///      {MarketConfig.STABLECOIN_DECIMALS}. `MarketConfig.t.sol` asserts the two agree, since
    ///      changing one alone would silently misprice {DISPUTE_BOND} by orders of magnitude.
    uint256 internal constant STABLECOIN_DECIMALS = 6;

    /// @notice Length of the window, starting at result publication, during which a matchweek's
    ///         results can be disputed.
    uint40 internal constant DISPUTE_WINDOW = 48 hours;

    /// @notice Fixed stablecoin bond required to open a dispute: 50 USDC.
    /// @dev Placeholder MVP value — tune before mainnet launch. Written as a multiple of one whole
    ///      token so the figure reads as 50 tokens rather than as a raw amount.
    uint256 internal constant DISPUTE_BOND = 50 * 10 ** STABLECOIN_DECIMALS;
}
