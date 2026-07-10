// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title FaucetStablecoin
/// @notice Local-only stand-in for a stablecoin, used solely by the Anvil deploy script so
///         developers can mint test funds without a real USDC contract.
/// @dev Unlike OpenZeppelin's ERC20Mock, minting is rate-limited per wallet so no single address
///      can mint without bound and push totalSupply toward overflow, which would brick the
///      faucet for every other wallet on the local chain.
contract FaucetStablecoin is ERC20 {
    /// @notice Amount minted to the caller on each successful faucet claim.
    uint256 public constant FAUCET_AMOUNT = 100 * 10 ** 6;

    /// @notice Minimum time a wallet must wait between faucet claims.
    uint256 public constant CLAIM_COOLDOWN = 24 hours;

    /// @notice Timestamp at which each wallet is next allowed to claim from the faucet.
    mapping(address => uint256) public nextClaimAt;

    /// @notice Thrown when a wallet claims before its {CLAIM_COOLDOWN} has elapsed.
    error FaucetCooldownActive(uint256 nextClaimAt_);

    constructor() ERC20("Mock USD Coin", "mUSDC") {}

    /// @notice Mints {FAUCET_AMOUNT} of test stablecoin to the caller, at most once per
    ///         {CLAIM_COOLDOWN}.
    /// @dev Reverts with {FaucetCooldownActive} if called again before the cooldown elapses.
    function mint() external {
        if (block.timestamp < nextClaimAt[msg.sender]) revert FaucetCooldownActive(nextClaimAt[msg.sender]);
        nextClaimAt[msg.sender] = block.timestamp + CLAIM_COOLDOWN;
        _mint(msg.sender, FAUCET_AMOUNT);
    }

    /// @notice Matches USDC's 6 decimals so local amounts line up with {Matchweek.STAKE_AMOUNT}.
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
