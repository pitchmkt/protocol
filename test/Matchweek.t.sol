// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Matchweek} from "../src/Matchweek.sol";

contract MatchweekTest is Test {
    uint32 constant MATCHWEEK_ID = 1;
    address constant ADMIN = address(0xAD);

    uint40 private _entryDeadline;
    Matchweek public matchweek;

    function setUp() public {
        _entryDeadline = uint40(block.timestamp + 1 days);
        matchweek = new Matchweek(MATCHWEEK_ID, _entryDeadline, _buildValidMatches(), ADMIN);
    }

    function test_deploy_emitsMatchweekCreated() public {
        Matchweek.Match[] memory m = _buildValidMatches();
        Matchweek.Match[10] memory expected;
        for (uint256 i = 0; i < 10; ++i) {
            expected[i] = m[i];
        }

        // Predict the address before deployment so we can pass it to expectEmit.
        address predicted = computeCreateAddress(address(this), vm.getNonce(address(this)));

        vm.expectEmit(true, false, false, true);
        emit Matchweek.MatchweekCreated(MATCHWEEK_ID, predicted, _entryDeadline, expected);
        new Matchweek(MATCHWEEK_ID, _entryDeadline, m, ADMIN);
    }

    function testRevert_wrongMatchCount_tooFew() public {
        Matchweek.Match[] memory tooFew = new Matchweek.Match[](9);
        for (uint256 i = 0; i < 9; ++i) {
            tooFew[i] = Matchweek.Match({homeTeam: bytes32(0), awayTeam: bytes32(0)});
        }
        vm.expectRevert(abi.encodeWithSelector(Matchweek.WrongMatchCount.selector, uint256(9)));
        new Matchweek(MATCHWEEK_ID, _entryDeadline, tooFew, ADMIN);
    }

    function testRevert_wrongMatchCount_tooMany() public {
        Matchweek.Match[] memory tooMany = new Matchweek.Match[](11);
        for (uint256 i = 0; i < 11; ++i) {
            tooMany[i] = Matchweek.Match({homeTeam: bytes32(0), awayTeam: bytes32(0)});
        }
        vm.expectRevert(abi.encodeWithSelector(Matchweek.WrongMatchCount.selector, uint256(11)));
        new Matchweek(MATCHWEEK_ID, _entryDeadline, tooMany, ADMIN);
    }

    function testRevert_deadlineInPast() public {
        // equal to now — not strictly future
        uint40 bad = uint40(block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(Matchweek.DeadlineInPast.selector, bad));
        new Matchweek(MATCHWEEK_ID, bad, _buildValidMatches(), ADMIN);
    }

    function test_deploy() public view {
        assertEq(uint8(matchweek.state()), uint8(Matchweek.State.Open));
        assertEq(matchweek.MATCHWEEK_ID(), MATCHWEEK_ID);
        assertEq(matchweek.ENTRY_DEADLINE(), _entryDeadline);
        assertEq(matchweek.owner(), ADMIN);

        Matchweek.Match[10] memory stored = matchweek.getMatches();
        Matchweek.Match[] memory expected = _buildValidMatches();
        for (uint256 i = 0; i < 10; ++i) {
            assertEq(stored[i].homeTeam, expected[i].homeTeam);
            assertEq(stored[i].awayTeam, expected[i].awayTeam);
        }
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
