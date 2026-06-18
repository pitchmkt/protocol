// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MatchweekFactory} from "../src/MatchweekFactory.sol";

/// @dev Deploys MatchweekFactory only. Matchweek creation is driven by the admin panel calling
///      `createMatchweek(...)` with real match data, not by this deploy script.
contract MatchweekFactoryScript is Script {
    function run() public {
        vm.startBroadcast();

        address admin = vm.envOr("ADMIN", msg.sender);
        MatchweekFactory factory = new MatchweekFactory(admin);

        vm.stopBroadcast();

        console.log("MatchweekFactory deployed at:", address(factory));
        console.log("Admin:                       ", admin);
    }
}
