// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Matchweek} from "../src/Matchweek.sol";
import {MatchweekFactory} from "../src/MatchweekFactory.sol";

contract MatchweekFactoryTest is Test {
    uint32 constant MATCHWEEK_ID = 1;
    address constant FACTORY_OWNER = address(0xF0);
    address constant ADMIN = address(0xAD);
    address constant STRANGER = address(0xBAD);

    uint40 private _entryDeadline;
    MatchweekFactory public factory;

    function setUp() public {
        _entryDeadline = uint40(block.timestamp + 1 days);
        factory = new MatchweekFactory(FACTORY_OWNER);
    }

    function test_createMatchweek() public {
        Matchweek.Match[] memory matches = _buildValidMatches();

        vm.prank(FACTORY_OWNER);
        vm.expectEmit(false, true, false, false);
        emit MatchweekFactory.MatchweekDeployed(address(0), MATCHWEEK_ID);
        address deployed = factory.createMatchweek(MATCHWEEK_ID, _entryDeadline, matches, ADMIN);

        Matchweek matchweek = Matchweek(deployed);
        assertEq(matchweek.matchweekId(), MATCHWEEK_ID);
        assertEq(matchweek.entryDeadline(), _entryDeadline);
        assertEq(matchweek.owner(), ADMIN);
        assertEq(uint8(matchweek.state()), uint8(Matchweek.State.Open));

        assertEq(factory.matchweeks(MATCHWEEK_ID), deployed);
        assertEq(factory.deployedMatchweeks(0), deployed);
    }

    function testRevert_NotOwner() public {
        Matchweek.Match[] memory matches = _buildValidMatches();

        vm.prank(STRANGER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, STRANGER));
        factory.createMatchweek(MATCHWEEK_ID, _entryDeadline, matches, ADMIN);
    }

    /// @dev Builds 10 valid matches using deterministic team identifiers.
    function _buildValidMatches() internal pure returns (Matchweek.Match[] memory) {
        Matchweek.Match[] memory m = new Matchweek.Match[](10);
        for (uint256 i = 0; i < 10; ++i) {
            m[i] = Matchweek.Match({
                homeTeam: keccak256(abi.encodePacked("HOME", i)), awayTeam: keccak256(abi.encodePacked("AWAY", i))
            });
        }
        return m;
    }
}
