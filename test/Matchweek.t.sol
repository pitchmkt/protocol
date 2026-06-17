// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Matchweek} from "../src/Matchweek.sol";

contract MatchweekTest is Test {
    uint32 constant MATCHWEEK_ID = 1;
    address constant ADMIN = address(0xAD);

    uint40 private _entryDeadline;
    address private _implementation;
    Matchweek public matchweek;

    function setUp() public {
        _entryDeadline = uint40(block.timestamp + 1 days);
        _implementation = address(new Matchweek());
        matchweek = _deployClone();
        matchweek.initialize(MATCHWEEK_ID, _entryDeadline, _buildValidMatches(), ADMIN);
    }

    function test_deploy_emitsMatchweekCreated() public {
        Matchweek.Match[] memory m = _buildValidMatches();
        Matchweek.Match[10] memory expected;
        for (uint256 i = 0; i < 10; ++i) {
            expected[i] = m[i];
        }

        Matchweek fresh = _deployClone();

        vm.expectEmit(true, false, false, true);
        emit Matchweek.MatchweekCreated(MATCHWEEK_ID, address(fresh), _entryDeadline, expected);
        fresh.initialize(MATCHWEEK_ID, _entryDeadline, m, ADMIN);
    }

    function testRevert_wrongMatchCount_tooFew() public {
        Matchweek.Match[] memory tooFew = new Matchweek.Match[](9);
        for (uint256 i = 0; i < 9; ++i) {
            tooFew[i] = Matchweek.Match({homeTeam: bytes32(0), awayTeam: bytes32(0)});
        }
        Matchweek fresh = _deployClone();
        vm.expectRevert(abi.encodeWithSelector(Matchweek.WrongMatchCount.selector, uint256(9)));
        fresh.initialize(MATCHWEEK_ID, _entryDeadline, tooFew, ADMIN);
    }

    function testRevert_wrongMatchCount_tooMany() public {
        Matchweek.Match[] memory tooMany = new Matchweek.Match[](11);
        for (uint256 i = 0; i < 11; ++i) {
            tooMany[i] = Matchweek.Match({homeTeam: bytes32(0), awayTeam: bytes32(0)});
        }
        Matchweek fresh = _deployClone();
        vm.expectRevert(abi.encodeWithSelector(Matchweek.WrongMatchCount.selector, uint256(11)));
        fresh.initialize(MATCHWEEK_ID, _entryDeadline, tooMany, ADMIN);
    }

    function testRevert_deadlineInPast() public {
        // equal to now — not strictly future
        uint40 bad = uint40(block.timestamp);
        Matchweek fresh = _deployClone();
        vm.expectRevert(abi.encodeWithSelector(Matchweek.DeadlineInPast.selector, bad));
        fresh.initialize(MATCHWEEK_ID, bad, _buildValidMatches(), ADMIN);
    }

    function testRevert_adminIsZeroAddress() public {
        Matchweek fresh = _deployClone();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        fresh.initialize(MATCHWEEK_ID, _entryDeadline, _buildValidMatches(), address(0));
    }

    function testRevert_alreadyInitialized() public {
        vm.expectRevert(Matchweek.AlreadyInitialized.selector);
        matchweek.initialize(MATCHWEEK_ID, _entryDeadline, _buildValidMatches(), ADMIN);
    }

    function testRevert_implementationLocked() public {
        vm.expectRevert(Matchweek.AlreadyInitialized.selector);
        Matchweek(_implementation).initialize(MATCHWEEK_ID, _entryDeadline, _buildValidMatches(), ADMIN);
    }

    function test_deploy() public view {
        assertEq(uint8(matchweek.state()), uint8(Matchweek.State.Open));
        assertEq(matchweek.matchweekId(), MATCHWEEK_ID);
        assertEq(matchweek.entryDeadline(), _entryDeadline);
        assertEq(matchweek.owner(), ADMIN);

        Matchweek.Match[10] memory stored = matchweek.getMatches();
        Matchweek.Match[] memory expected = _buildValidMatches();
        for (uint256 i = 0; i < 10; ++i) {
            assertEq(stored[i].homeTeam, expected[i].homeTeam);
            assertEq(stored[i].awayTeam, expected[i].awayTeam);
        }
    }

    /// @dev Deploys a fresh EIP-1167 minimal proxy clone of the implementation, mirroring how
    ///      MatchweekFactory creates instances.
    function _deployClone() internal returns (Matchweek) {
        return Matchweek(Clones.clone(_implementation));
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
