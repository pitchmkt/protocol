// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Matchweek} from "../src/Matchweek.sol";

contract MatchweekTest is Test {
    uint32 constant MATCHWEEK_ID = 1;
    address constant ADMIN = address(0xAD);
    address constant ALICE = address(0xA11CE);

    uint40 private _entryDeadline;
    address private _implementation;
    Matchweek public matchweek;
    ERC20Mock public stablecoin;

    function setUp() public {
        _entryDeadline = uint40(block.timestamp + 1 days);
        stablecoin = new ERC20Mock();
        _implementation = address(new Matchweek(stablecoin));
        matchweek = _deployClone();
        matchweek.initialize(MATCHWEEK_ID, _entryDeadline, _buildValidMatches(), ADMIN);

        stablecoin.mint(ALICE, 1_000_000_000);
        vm.prank(ALICE);
        stablecoin.approve(address(matchweek), type(uint256).max);
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

    function testRevert_stablecoinIsZeroAddress() public {
        vm.expectRevert(Matchweek.InvalidStablecoin.selector);
        new Matchweek(ERC20Mock(address(0)));
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
        assertEq(matchweek.matchweekId(), MATCHWEEK_ID);
        assertEq(matchweek.entryDeadline(), _entryDeadline);
        assertEq(matchweek.owner(), ADMIN);
        assertEq(address(matchweek.STABLECOIN()), address(stablecoin));

        Matchweek.Match[10] memory stored = matchweek.getMatches();
        Matchweek.Match[] memory expected = _buildValidMatches();
        for (uint256 i = 0; i < 10; ++i) {
            assertEq(stored[i].homeTeam, expected[i].homeTeam);
            assertEq(stored[i].awayTeam, expected[i].awayTeam);
        }
    }

    function test_deploy_sharesStablecoinAcrossClones() public {
        Matchweek other = _deployClone();
        other.initialize(MATCHWEEK_ID + 1, _entryDeadline, _buildValidMatches(), ADMIN);

        assertEq(address(other.STABLECOIN()), address(stablecoin));
        assertEq(address(other.STABLECOIN()), address(matchweek.STABLECOIN()));
    }

    ////
    /// Submit Prediction Tests
    ////

    function test_submitPrediction() public {
        uint8[10] memory predictions = _buildValidPredictions();
        uint256 stake = matchweek.MIN_STAKE();

        vm.expectEmit(true, true, true, true);
        emit Matchweek.PredictionSubmitted(0, ALICE, MATCHWEEK_ID, predictions, stake);
        vm.prank(ALICE);
        uint256 entryId = matchweek.submitPrediction(predictions, stake);

        assertEq(entryId, 0);
        assertEq(matchweek.entryCount(), 1);
        assertEq(matchweek.entryOwner(0), ALICE);
        assertEq(matchweek.predictionByEntry(0), keccak256(abi.encode(predictions)));
        assertEq(matchweek.stakeByEntry(0), stake);
        assertEq(matchweek.totalStaked(), stake);
        assertEq(stablecoin.balanceOf(address(matchweek)), stake);
        assertEq(stablecoin.balanceOf(ALICE), 1_000_000_000 - stake);
    }

    function test_submitPrediction_sameAddressMultipleEntries() public {
        uint8[10] memory predictions = _buildValidPredictions();
        uint256 stake = matchweek.MIN_STAKE();

        vm.startPrank(ALICE);
        uint256 first = matchweek.submitPrediction(predictions, stake);
        uint256 second = matchweek.submitPrediction(predictions, stake * 2);
        vm.stopPrank();

        assertEq(first, 0);
        assertEq(second, 1);
        assertEq(matchweek.entryCount(), 2);
        assertEq(matchweek.entryOwner(0), ALICE);
        assertEq(matchweek.entryOwner(1), ALICE);
        assertEq(matchweek.predictionByEntry(0), keccak256(abi.encode(predictions)));
        assertEq(matchweek.predictionByEntry(1), keccak256(abi.encode(predictions)));
        assertEq(matchweek.stakeByEntry(0), stake);
        assertEq(matchweek.stakeByEntry(1), stake * 2);
        assertEq(matchweek.totalStaked(), stake * 3);
        assertEq(stablecoin.balanceOf(address(matchweek)), stake * 3);
    }

    function testRevert_submitPrediction_invalidPredictionValue() public {
        uint8[10] memory predictions = _buildValidPredictions();
        predictions[3] = 3;
        uint256 stake = matchweek.MIN_STAKE();

        vm.expectRevert(abi.encodeWithSelector(Matchweek.InvalidPredictionValue.selector, uint256(3), uint8(3)));
        vm.prank(ALICE);
        matchweek.submitPrediction(predictions, stake);
    }

    function testRevert_submitPrediction_entryWindowClosed() public {
        uint256 stake = matchweek.MIN_STAKE();
        vm.warp(_entryDeadline);

        vm.expectRevert(Matchweek.EntryWindowClosed.selector);
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions(), stake);
    }

    function testRevert_submitPrediction_belowMinimumStake() public {
        uint256 tooLow = matchweek.MIN_STAKE() - 1;

        vm.expectRevert(abi.encodeWithSelector(Matchweek.BelowMinimumStake.selector, tooLow, matchweek.MIN_STAKE()));
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions(), tooLow);
    }

    function testRevert_submitPrediction_insufficientAllowance() public {
        uint256 stake = matchweek.MIN_STAKE();
        vm.prank(ALICE);
        stablecoin.approve(address(matchweek), 0);

        vm.expectRevert();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions(), stake);
    }

    function testRevert_submitPrediction_insufficientBalance() public {
        uint256 stake = matchweek.MIN_STAKE();
        address poor = address(0xB0B);
        vm.prank(poor);
        stablecoin.approve(address(matchweek), type(uint256).max);

        vm.expectRevert();
        vm.prank(poor);
        matchweek.submitPrediction(_buildValidPredictions(), stake);
    }

    /// @dev Deploys a fresh EIP-1167 minimal proxy clone of the implementation, mirroring how
    ///      MatchweekFactory creates instances.
    function _deployClone() internal returns (Matchweek) {
        return Matchweek(Clones.clone(_implementation));
    }

    /// @dev Builds a valid set of ten predictions (alternating home/draw/away).
    function _buildValidPredictions() internal pure returns (uint8[10] memory predictions) {
        for (uint256 i = 0; i < 10; ++i) {
            // forge-lint: disable-next-line(unsafe-typecast)
            predictions[i] = uint8(i % 3);
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
