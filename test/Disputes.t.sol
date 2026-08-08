// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {CarryPool} from "../src/CarryPool.sol";
import {DisputeConfig} from "../src/DisputeConfig.sol";
import {Disputes} from "../src/Disputes.sol";
import {Matchweek} from "../src/Matchweek.sol";
import {Treasury} from "../src/Treasury.sol";

contract DisputesTest is Test {
    uint32 constant MATCHWEEK_ID = 1;
    address constant ADMIN = address(0xAD);
    address constant MATCHWEEK_A = address(0xAAA1);
    address constant MATCHWEEK_B = address(0xAAA2);
    address constant CHALLENGER = address(0xC4A1);
    address constant STRANGER = address(0xBAD);

    uint40 private _predictionDeadline;
    address private _implementation;
    Disputes public disputes;
    Treasury public treasury;
    CarryPool public carryPool;
    ERC20Mock public stablecoin;
    /// @dev Real Matchweek clone, needed only by tests that exercise {Disputes.confirmDispute} /
    ///      {Disputes.rejectDispute}, since those call back into `matchweek` for the correction
    ///      and the matchweekId. Tests that only touch {Disputes} in isolation use the
    ///      MATCHWEEK_A / MATCHWEEK_B address stand-ins instead, same as {CarryPool.t.sol} and
    ///      {Treasury.t.sol}.
    Matchweek public matchweek;

    function setUp() public {
        _predictionDeadline = uint40(block.timestamp + 1 days);
        stablecoin = new ERC20Mock();
        carryPool = new CarryPool(ADMIN, stablecoin);
        treasury = new Treasury(ADMIN, stablecoin);
        disputes = new Disputes(ADMIN, stablecoin, treasury);

        // This test contract stands in for PitchMkt, the only account allowed to register
        // matchweeks with the disputes contract and the treasury.
        vm.prank(ADMIN);
        disputes.setFactory(address(this));
        disputes.registerMatchweek(MATCHWEEK_A);
        disputes.registerMatchweek(MATCHWEEK_B);

        vm.prank(ADMIN);
        treasury.setFactory(address(this));
        vm.prank(ADMIN);
        treasury.setDisputes(address(disputes));

        _implementation = address(new Matchweek(stablecoin, carryPool, treasury, disputes));
        matchweek = Matchweek(Clones.clone(_implementation));
        matchweek.initialize(MATCHWEEK_ID, _predictionDeadline, _buildValidMatches(), ADMIN);
        treasury.registerMatchweek(address(matchweek));
        disputes.registerMatchweek(address(matchweek));

        stablecoin.mint(CHALLENGER, 1_000_000_000);
        vm.prank(CHALLENGER);
        stablecoin.approve(address(disputes), type(uint256).max);
    }

    ////
    /// Constructor Tests
    ////

    function testRevert_stablecoinIsZeroAddress() public {
        vm.expectRevert(Disputes.InvalidStablecoin.selector);
        new Disputes(ADMIN, ERC20Mock(address(0)), treasury);
    }

    function testRevert_treasuryIsZeroAddress() public {
        vm.expectRevert(Disputes.InvalidTreasury.selector);
        new Disputes(ADMIN, stablecoin, Treasury(payable(address(0))));
    }

    ////
    /// setFactory / registerMatchweek Tests
    ////

    function test_setFactory() public view {
        assertEq(disputes.factory(), address(this));
    }

    function testRevert_setFactory_alreadySet() public {
        vm.expectRevert(Disputes.FactoryAlreadySet.selector);
        vm.prank(ADMIN);
        disputes.setFactory(STRANGER);
    }

    function testRevert_setFactory_notOwner() public {
        Disputes fresh = new Disputes(ADMIN, stablecoin, treasury);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, STRANGER));
        vm.prank(STRANGER);
        fresh.setFactory(STRANGER);
    }

    function test_registerMatchweek() public view {
        assertEq(disputes.isMatchweek(MATCHWEEK_A), true);
        assertEq(disputes.isMatchweek(MATCHWEEK_B), true);
        assertEq(disputes.isMatchweek(STRANGER), false);
    }

    function testRevert_registerMatchweek_notFactory() public {
        vm.expectRevert(Disputes.NotFactory.selector);
        vm.prank(STRANGER);
        disputes.registerMatchweek(STRANGER);
    }

    ////
    /// openDisputeWindow Tests
    ////

    function test_openDisputeWindow_setsDeadlineAndEmits() public {
        uint40 expectedDeadline = uint40(block.timestamp) + DisputeConfig.DISPUTE_WINDOW;

        vm.expectEmit(true, false, false, true);
        emit Disputes.DisputeWindowOpened(MATCHWEEK_A, expectedDeadline);
        vm.prank(MATCHWEEK_A);
        disputes.openDisputeWindow();

        assertEq(disputes.disputeDeadline(MATCHWEEK_A), expectedDeadline);
    }

    function testRevert_openDisputeWindow_notMatchweek() public {
        vm.expectRevert(Disputes.NotMatchweek.selector);
        vm.prank(STRANGER);
        disputes.openDisputeWindow();
    }

    ////
    /// disputeResults Tests
    ////

    function test_disputeResults_opensDisputeAndPullsBond() public {
        vm.prank(MATCHWEEK_A);
        disputes.openDisputeWindow();

        bytes32 evidence = keccak256("evidence");
        vm.expectEmit(true, true, false, true);
        emit Disputes.ResultsDisputed(MATCHWEEK_A, CHALLENGER, DisputeConfig.DISPUTE_BOND, evidence);
        vm.prank(CHALLENGER);
        disputes.disputeResults(MATCHWEEK_A, evidence);

        (address challenger, uint256 bond, uint40 openedAt, bool resolved) = disputes.disputes(MATCHWEEK_A);
        assertEq(challenger, CHALLENGER);
        assertEq(bond, DisputeConfig.DISPUTE_BOND);
        assertEq(openedAt, block.timestamp);
        assertEq(resolved, false);
        assertEq(stablecoin.balanceOf(address(disputes)), DisputeConfig.DISPUTE_BOND);
    }

    function testRevert_disputeResults_windowNotOpen() public {
        vm.expectRevert(Disputes.DisputeWindowNotOpen.selector);
        vm.prank(CHALLENGER);
        disputes.disputeResults(MATCHWEEK_A, bytes32(0));
    }

    function testRevert_disputeResults_windowClosed() public {
        vm.prank(MATCHWEEK_A);
        disputes.openDisputeWindow();
        vm.warp(block.timestamp + DisputeConfig.DISPUTE_WINDOW);

        vm.expectRevert(Disputes.DisputeWindowClosed.selector);
        vm.prank(CHALLENGER);
        disputes.disputeResults(MATCHWEEK_A, bytes32(0));
    }

    function testRevert_disputeResults_alreadyOpen() public {
        vm.prank(MATCHWEEK_A);
        disputes.openDisputeWindow();
        vm.prank(CHALLENGER);
        disputes.disputeResults(MATCHWEEK_A, bytes32(0));

        address other = address(0xC4A2);
        stablecoin.mint(other, DisputeConfig.DISPUTE_BOND);
        vm.prank(other);
        stablecoin.approve(address(disputes), DisputeConfig.DISPUTE_BOND);

        vm.expectRevert(Disputes.DisputeAlreadyOpen.selector);
        vm.prank(other);
        disputes.disputeResults(MATCHWEEK_A, bytes32(0));
    }

    function testRevert_disputeResults_insufficientAllowance() public {
        vm.prank(MATCHWEEK_A);
        disputes.openDisputeWindow();

        address poor = address(0xC4A3);
        vm.expectRevert();
        vm.prank(poor);
        disputes.disputeResults(MATCHWEEK_A, bytes32(0));
    }

    ////
    /// isSettled Tests
    ////

    function test_isSettled_falseBeforeWindowOpened() public view {
        assertEq(disputes.isSettled(MATCHWEEK_A), false);
    }

    function test_isSettled_falseWhileWindowOpen() public {
        vm.prank(MATCHWEEK_A);
        disputes.openDisputeWindow();
        assertEq(disputes.isSettled(MATCHWEEK_A), false);
    }

    function test_isSettled_trueAfterWindowClosesWithNoDispute() public {
        vm.prank(MATCHWEEK_A);
        disputes.openDisputeWindow();
        vm.warp(block.timestamp + DisputeConfig.DISPUTE_WINDOW);
        assertEq(disputes.isSettled(MATCHWEEK_A), true);
    }

    function test_isSettled_falseWhileDisputeUnresolved() public {
        vm.prank(MATCHWEEK_A);
        disputes.openDisputeWindow();
        vm.prank(CHALLENGER);
        disputes.disputeResults(MATCHWEEK_A, bytes32(0));
        vm.warp(block.timestamp + DisputeConfig.DISPUTE_WINDOW);
        assertEq(disputes.isSettled(MATCHWEEK_A), false);
    }

    ////
    /// confirmDispute Tests
    ////

    function test_confirmDispute_correctsOutcomesAndRefundsBond() public {
        _publishAndDispute();

        uint8[10] memory corrected = _buildValidPredictions();
        corrected[0] = corrected[0] == 0 ? uint8(1) : uint8(0);
        uint256 challengerBalanceBefore = stablecoin.balanceOf(CHALLENGER);

        vm.expectEmit(true, true, false, true);
        emit Disputes.DisputeConfirmed(address(matchweek), CHALLENGER, corrected);
        vm.prank(ADMIN);
        disputes.confirmDispute(address(matchweek), corrected);

        uint8[10] memory stored = matchweek.getOutcomes();
        for (uint256 i = 0; i < 10; ++i) {
            assertEq(stored[i], corrected[i]);
        }
        assertEq(stablecoin.balanceOf(CHALLENGER), challengerBalanceBefore + DisputeConfig.DISPUTE_BOND);

        // The dispute window still has to fully elapse before the matchweek is settled, even
        // though the dispute itself was already resolved.
        vm.warp(disputes.disputeDeadline(address(matchweek)));
        assertEq(disputes.isSettled(address(matchweek)), true);
    }

    function testRevert_confirmDispute_noActiveDispute() public {
        vm.expectRevert(Disputes.NoActiveDispute.selector);
        vm.prank(ADMIN);
        disputes.confirmDispute(address(matchweek), _buildValidPredictions());
    }

    function testRevert_confirmDispute_alreadyResolved() public {
        _publishAndDispute();
        vm.prank(ADMIN);
        disputes.confirmDispute(address(matchweek), _buildValidPredictions());

        vm.expectRevert(Disputes.DisputeAlreadyResolved.selector);
        vm.prank(ADMIN);
        disputes.confirmDispute(address(matchweek), _buildValidPredictions());
    }

    function testRevert_confirmDispute_notOwner() public {
        _publishAndDispute();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, STRANGER));
        vm.prank(STRANGER);
        disputes.confirmDispute(address(matchweek), _buildValidPredictions());
    }

    ////
    /// rejectDispute Tests
    ////

    function test_rejectDispute_forfeitsBondToTreasuryAndKeepsOriginalResult() public {
        uint8[10] memory original = _publishAndDispute();

        vm.expectEmit(true, true, false, true);
        emit Disputes.DisputeRejected(address(matchweek), CHALLENGER, DisputeConfig.DISPUTE_BOND);
        vm.prank(ADMIN);
        disputes.rejectDispute(address(matchweek));

        uint8[10] memory stored = matchweek.getOutcomes();
        for (uint256 i = 0; i < 10; ++i) {
            assertEq(stored[i], original[i]);
        }
        assertEq(treasury.collectedByMatchweek(MATCHWEEK_ID), DisputeConfig.DISPUTE_BOND);
        assertEq(stablecoin.balanceOf(address(treasury)), DisputeConfig.DISPUTE_BOND);

        vm.warp(disputes.disputeDeadline(address(matchweek)));
        assertEq(disputes.isSettled(address(matchweek)), true);
    }

    function testRevert_rejectDispute_noActiveDispute() public {
        vm.expectRevert(Disputes.NoActiveDispute.selector);
        vm.prank(ADMIN);
        disputes.rejectDispute(address(matchweek));
    }

    function testRevert_rejectDispute_alreadyResolved() public {
        _publishAndDispute();
        vm.prank(ADMIN);
        disputes.rejectDispute(address(matchweek));

        vm.expectRevert(Disputes.DisputeAlreadyResolved.selector);
        vm.prank(ADMIN);
        disputes.rejectDispute(address(matchweek));
    }

    function testRevert_rejectDispute_notOwner() public {
        _publishAndDispute();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, STRANGER));
        vm.prank(STRANGER);
        disputes.rejectDispute(address(matchweek));
    }

    ////
    /// Test Helpers
    ////

    /// @dev Publishes results on {matchweek} and has {CHALLENGER} dispute them.
    /// @return original The published outcomes, for asserting they stand after a rejected dispute.
    function _publishAndDispute() internal returns (uint8[10] memory original) {
        original = _buildValidPredictions();
        vm.warp(_predictionDeadline);
        vm.prank(ADMIN);
        matchweek.publishResults(original);

        vm.prank(CHALLENGER);
        disputes.disputeResults(address(matchweek), keccak256("evidence"));
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

    /// @dev Builds a valid set of ten outcomes (alternating home/draw/away).
    function _buildValidPredictions() internal pure returns (uint8[10] memory predictions) {
        for (uint256 i = 0; i < 10; ++i) {
            // forge-lint: disable-next-line(unsafe-typecast)
            predictions[i] = uint8(i % 3);
        }
    }
}
