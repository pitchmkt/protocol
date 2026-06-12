// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Matchweek} from "../src/Matchweek.sol";

contract MatchweekScript is Script {
    function run() public {
        address admin = vm.envOr("ADMIN", msg.sender);

        Matchweek.Match[] memory matches = new Matchweek.Match[](10);
        matches[0] = Matchweek.Match(keccak256("arsenal"), keccak256("chelsea"));
        matches[1] = Matchweek.Match(keccak256("man_city"), keccak256("liverpool"));
        matches[2] = Matchweek.Match(keccak256("man_utd"), keccak256("tottenham"));
        matches[3] = Matchweek.Match(keccak256("newcastle"), keccak256("aston_villa"));
        matches[4] = Matchweek.Match(keccak256("brighton"), keccak256("west_ham"));
        matches[5] = Matchweek.Match(keccak256("everton"), keccak256("wolves"));
        matches[6] = Matchweek.Match(keccak256("brentford"), keccak256("crystal_palace"));
        matches[7] = Matchweek.Match(keccak256("fulham"), keccak256("nottm_forest"));
        matches[8] = Matchweek.Match(keccak256("bournemouth"), keccak256("leicester"));
        matches[9] = Matchweek.Match(keccak256("southampton"), keccak256("ipswich"));

        uint32 matchweekId = 1;
        uint40 entryDeadline = uint40(block.timestamp + 7 days);

        vm.startBroadcast();

        Matchweek matchweek = new Matchweek(matchweekId, entryDeadline, matches, admin);

        vm.stopBroadcast();

        console.log("Matchweek deployed at:", address(matchweek));
        console.log("Matchweek ID:         ", matchweekId);
        console.log("Entry deadline:       ", entryDeadline);
        console.log("Admin:                ", admin);
    }
}
