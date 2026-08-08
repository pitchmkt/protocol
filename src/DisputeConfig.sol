// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/// @title DisputeConfig
/// @notice Compile-time constants that define PitchMkt's dispute window rules.
///         All members are `internal` — they are inlined by the compiler and add no
///         deployment or runtime cost. No separate contract is deployed for this library.
library DisputeConfig {
    /// @notice Length of the window, starting at result publication, during which a matchweek's
    ///         results can be disputed.
    uint40 internal constant DISPUTE_WINDOW = 48 hours;

    /// @notice Fixed stablecoin bond required to open a dispute.
    /// @dev Placeholder MVP value (50 USDC, 6 decimals) — tune before mainnet launch.
    uint256 internal constant DISPUTE_BOND = 50_000_000;
}
