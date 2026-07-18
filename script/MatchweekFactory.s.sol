// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MatchweekFactory} from "../src/MatchweekFactory.sol";
import {FaucetStablecoin} from "./FaucetStablecoin.sol";

uint256 constant ANVIL_CHAIN_ID = 31337;
uint256 constant HYPEREVM_MAINNET_CHAIN_ID = 999;
uint256 constant HYPEREVM_TESTNET_CHAIN_ID = 998;

// TODO: replace with the real USDC address on HyperEVM mainnet before deploying there.
address constant HYPEREVM_MAINNET_USDC = address(0);

/// @dev Deploys MatchweekFactory only. Matchweek creation is driven by the admin panel calling
///      `createMatchweek(...)` with real match data, not by this deploy script.
///      The stablecoin accepted as stake is fixed for every matchweek deployed through the
///      factory and is resolved here per chain ID — never passed in by the caller. On anvil
///      there's no real stablecoin to point to, so a fresh FaucetStablecoin is deployed instead.
contract MatchweekFactoryScript is Script {
    function run() public {
        vm.startBroadcast();

        (, address deployer,) = vm.readCallers();
        address admin = vm.envOr("ADMIN", deployer);
        IERC20 stablecoin = _resolveStablecoin();
        MatchweekFactory factory = new MatchweekFactory(admin, stablecoin);

        vm.stopBroadcast();

        console.log("MatchweekFactory deployed at:", address(factory));
        console.log("Admin:                       ", admin);
        console.log("Stablecoin:                  ", address(stablecoin));
    }

    /// @dev Resolves the stablecoin address for the chain being deployed to. Anvil and HyperEVM
    ///      Testnet get a fresh FaucetStablecoin since there's no real, trusted stablecoin on
    ///      either; HyperEVM Mainnet maps to a hardcoded address.
    function _resolveStablecoin() private returns (IERC20) {
        if (block.chainid == ANVIL_CHAIN_ID || block.chainid == HYPEREVM_TESTNET_CHAIN_ID) {
            FaucetStablecoin faucet = new FaucetStablecoin();
            console.log("Deployed FaucetStablecoin stablecoin at:", address(faucet));
            return IERC20(address(faucet));
        }

        if (block.chainid == HYPEREVM_MAINNET_CHAIN_ID) {
            require(HYPEREVM_MAINNET_USDC != address(0), "HYPEREVM_MAINNET_USDC not set");
            return IERC20(HYPEREVM_MAINNET_USDC);
        }

        revert("Unsupported chain ID: no stablecoin configured");
    }
}
