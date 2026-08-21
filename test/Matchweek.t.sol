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
import {MarketConfig} from "../src/MarketConfig.sol";
import {Treasury} from "../src/Treasury.sol";

contract MatchweekTest is Test {
    uint32 constant MATCHWEEK_ID = 1;

    // Single-outcome masks: bit0 home, bit1 draw, bit2 away.
    uint8 constant MASK_HOME = 1;
    uint8 constant MASK_DRAW = 2;
    uint8 constant MASK_AWAY = 4;

    address constant ADMIN = address(0xAD);
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    address constant CHALLENGER = address(0xC4A1);

    uint40 private _predictionDeadline;
    address private _implementation;
    Matchweek public matchweek;
    ERC20Mock public stablecoin;
    CarryPool public carryPool;
    Treasury public treasury;
    Disputes public disputes;

    function setUp() public {
        _predictionDeadline = uint40(block.timestamp + 1 days);
        stablecoin = new ERC20Mock();
        carryPool = new CarryPool(ADMIN, stablecoin);
        treasury = new Treasury(ADMIN, stablecoin);
        disputes = new Disputes(ADMIN, stablecoin, treasury);
        _implementation = address(new Matchweek(stablecoin, carryPool, treasury, disputes));
        matchweek = _deployClone();
        matchweek.initialize(MATCHWEEK_ID, _predictionDeadline, _buildValidMatches(), ADMIN);

        // This test contract stands in for PitchMkt, the only account allowed to
        // register matchweeks with the carry pool, the treasury and the disputes contract.
        vm.prank(ADMIN);
        carryPool.setFactory(address(this));
        carryPool.registerMatchweek(address(matchweek));
        vm.prank(ADMIN);
        treasury.setFactory(address(this));
        treasury.registerMatchweek(address(matchweek));
        vm.prank(ADMIN);
        disputes.setFactory(address(this));
        disputes.registerMatchweek(address(matchweek));
        vm.prank(ADMIN);
        treasury.setDisputes(address(disputes));

        stablecoin.mint(ALICE, 1_000_000_000);
        vm.prank(ALICE);
        stablecoin.approve(address(matchweek), type(uint256).max);
    }

    /// @notice The fixed-array lengths hardcoded in {Matchweek} must equal the config constants.
    /// @dev Solidity rejects a library-qualified constant as an array length, so `Match[10]`,
    ///      `uint8[10]` and `uint256[5]` are spelled as literals rather than derived from
    ///      {MarketConfig}. That makes them the one place the config cannot enforce itself, so the
    ///      pairing is asserted here instead. The per-tier arrays have no whole-array getter, so
    ///      their width is probed through the generated index getter: the last valid index must
    ///      answer and the next one must revert.
    function test_arrayLengthsMatchMarketConfig() public view {
        assertEq(matchweek.getMatches().length, MarketConfig.MATCH_COUNT, "_matches spans a matchweek");
        assertEq(matchweek.getOutcomes().length, MarketConfig.MATCH_COUNT, "_outcomes spans a matchweek");

        _assertTierArrayWidth("prizePerTier(uint256)");
        _assertTierArrayWidth("totalStakePerTier(uint256)");
    }

    /// @notice The constants re-exported on {Matchweek}'s ABI must match {MarketConfig}.
    /// @dev Callers and the indexer read the price and the matchweek size off the contract rather
    ///      than the library, so the two must not be allowed to diverge.
    function test_reexportedConstantsMatchMarketConfig() public view {
        assertEq(matchweek.UNIT_PRICE(), MarketConfig.UNIT_PRICE, "UNIT_PRICE is re-exported verbatim");
        assertEq(matchweek.MATCH_COUNT(), MarketConfig.MATCH_COUNT, "MATCH_COUNT is re-exported verbatim");
    }

    function test_deploy_emitsMatchweekCreated() public {
        Matchweek.Match[] memory m = _buildValidMatches();
        Matchweek.Match[10] memory expected;
        for (uint256 i = 0; i < 10; ++i) {
            expected[i] = m[i];
        }

        Matchweek fresh = _deployClone();

        vm.expectEmit(true, false, false, true);
        emit Matchweek.MatchweekCreated(MATCHWEEK_ID, address(fresh), _predictionDeadline, expected);
        fresh.initialize(MATCHWEEK_ID, _predictionDeadline, m, ADMIN);
    }

    function testRevert_wrongMatchCount_tooFew() public {
        Matchweek.Match[] memory tooFew = new Matchweek.Match[](9);
        for (uint256 i = 0; i < 9; ++i) {
            tooFew[i] = Matchweek.Match({homeTeam: bytes32(0), awayTeam: bytes32(0)});
        }
        Matchweek fresh = _deployClone();
        vm.expectRevert(abi.encodeWithSelector(Matchweek.WrongMatchCount.selector, uint256(9)));
        fresh.initialize(MATCHWEEK_ID, _predictionDeadline, tooFew, ADMIN);
    }

    function testRevert_wrongMatchCount_tooMany() public {
        Matchweek.Match[] memory tooMany = new Matchweek.Match[](11);
        for (uint256 i = 0; i < 11; ++i) {
            tooMany[i] = Matchweek.Match({homeTeam: bytes32(0), awayTeam: bytes32(0)});
        }
        Matchweek fresh = _deployClone();
        vm.expectRevert(abi.encodeWithSelector(Matchweek.WrongMatchCount.selector, uint256(11)));
        fresh.initialize(MATCHWEEK_ID, _predictionDeadline, tooMany, ADMIN);
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
        fresh.initialize(MATCHWEEK_ID, _predictionDeadline, _buildValidMatches(), address(0));
    }

    function testRevert_stablecoinIsZeroAddress() public {
        vm.expectRevert(Matchweek.InvalidStablecoin.selector);
        new Matchweek(ERC20Mock(address(0)), carryPool, treasury, disputes);
    }

    function testRevert_carryPoolIsZeroAddress() public {
        vm.expectRevert(Matchweek.InvalidCarryPool.selector);
        new Matchweek(stablecoin, CarryPool(address(0)), treasury, disputes);
    }

    function testRevert_treasuryIsZeroAddress() public {
        vm.expectRevert(Matchweek.InvalidTreasury.selector);
        new Matchweek(stablecoin, carryPool, Treasury(payable(address(0))), disputes);
    }

    function testRevert_disputesIsZeroAddress() public {
        vm.expectRevert(Matchweek.InvalidDisputes.selector);
        new Matchweek(stablecoin, carryPool, treasury, Disputes(payable(address(0))));
    }

    function testRevert_alreadyInitialized() public {
        vm.expectRevert(Matchweek.AlreadyInitialized.selector);
        matchweek.initialize(MATCHWEEK_ID, _predictionDeadline, _buildValidMatches(), ADMIN);
    }

    function testRevert_implementationLocked() public {
        vm.expectRevert(Matchweek.AlreadyInitialized.selector);
        Matchweek(_implementation).initialize(MATCHWEEK_ID, _predictionDeadline, _buildValidMatches(), ADMIN);
    }

    function test_deploy() public view {
        assertEq(matchweek.matchweekId(), MATCHWEEK_ID);
        assertEq(matchweek.predictionDeadline(), _predictionDeadline);
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
        other.initialize(MATCHWEEK_ID + 1, _predictionDeadline, _buildValidMatches(), ADMIN);

        assertEq(address(other.STABLECOIN()), address(stablecoin));
        assertEq(address(other.STABLECOIN()), address(matchweek.STABLECOIN()));
    }

    ////
    /// Submit Prediction Tests
    ////

    function test_submitPrediction() public {
        uint8[10] memory masks = _buildValidMasks();
        uint256 cost = matchweek.UNIT_PRICE();

        vm.expectEmit(true, true, true, true);
        emit Matchweek.PredictionSubmitted(0, ALICE, MATCHWEEK_ID, masks, 1, cost);
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(masks);

        assertEq(predictionId, 0);
        assertEq(matchweek.predictionCount(), 1);
        assertEq(matchweek.predictionOwner(0), ALICE);
        assertEq(matchweek.predictionHash(0), keccak256(abi.encode(masks)));
        assertEq(matchweek.predictionColumns(0), 1);
        assertEq(matchweek.predictionCost(0), cost);
        assertEq(matchweek.totalStaked(), cost);
        assertEq(stablecoin.balanceOf(address(matchweek)), cost);
        assertEq(stablecoin.balanceOf(ALICE), 1_000_000_000 - cost);
    }

    function test_submitPrediction_sameAddressMultiplePredictions() public {
        uint8[10] memory masks = _buildValidMasks();
        uint256 cost = matchweek.UNIT_PRICE();

        vm.startPrank(ALICE);
        uint256 first = matchweek.submitPrediction(masks);
        uint256 second = matchweek.submitPrediction(masks);
        vm.stopPrank();

        assertEq(first, 0);
        assertEq(second, 1);
        assertEq(matchweek.predictionCount(), 2);
        assertEq(matchweek.predictionOwner(0), ALICE);
        assertEq(matchweek.predictionOwner(1), ALICE);
        assertEq(matchweek.predictionHash(0), keccak256(abi.encode(masks)));
        assertEq(matchweek.predictionHash(1), keccak256(abi.encode(masks)));
        assertEq(matchweek.totalStaked(), cost * 2);
        assertEq(stablecoin.balanceOf(address(matchweek)), cost * 2);
    }

    function test_submitPrediction_costIsUnitPriceTimesColumns() public {
        uint8[10] memory masks = _buildValidMasks();
        masks[0] = 3; // H,D — double
        masks[1] = 6; // D,A — double
        uint256 expectedCost = matchweek.UNIT_PRICE() * 4;

        vm.expectEmit(true, true, true, true);
        emit Matchweek.PredictionSubmitted(0, ALICE, MATCHWEEK_ID, masks, 4, expectedCost);
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(masks);

        assertEq(matchweek.predictionColumns(predictionId), 4);
        assertEq(matchweek.predictionCost(predictionId), expectedCost);
        assertEq(matchweek.totalStaked(), expectedCost);
        assertEq(stablecoin.balanceOf(address(matchweek)), expectedCost);
        assertEq(stablecoin.balanceOf(ALICE), 1_000_000_000 - expectedCost);
    }

    function test_submitPrediction_columnsAreTheProductOfPopcounts() public {
        uint8[10] memory masks = _buildValidMasks();
        masks[0] = 3; // H,D — double
        masks[1] = 6; // D,A — double
        masks[2] = 7; // H,D,A — triple

        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(masks);

        assertEq(matchweek.predictionColumns(predictionId), 12);
    }

    function test_submitPrediction_tenTriplesSpanTheFullOutcomeSpace() public {
        uint8[10] memory masks;
        for (uint256 i = 0; i < 10; ++i) {
            masks[i] = 7;
        }
        // 59,049 columns at 2 USDC each is far beyond ALICE's default balance.
        stablecoin.mint(ALICE, matchweek.UNIT_PRICE() * 59_049);

        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(masks);

        assertEq(matchweek.predictionColumns(predictionId), 59_049); // 3**10
        assertEq(matchweek.predictionCost(predictionId), matchweek.UNIT_PRICE() * 59_049);
    }

    function testRevert_submitPrediction_maskMarksNothing() public {
        uint8[10] memory masks = _buildValidMasks();
        masks[3] = 0;

        vm.expectRevert(abi.encodeWithSelector(Matchweek.InvalidMask.selector, uint256(3), uint8(0)));
        vm.prank(ALICE);
        matchweek.submitPrediction(masks);
    }

    function testRevert_submitPrediction_maskAboveTriple() public {
        uint8[10] memory masks = _buildValidMasks();
        masks[7] = 8; // lowest mask with a bit that maps to no outcome

        vm.expectRevert(abi.encodeWithSelector(Matchweek.InvalidMask.selector, uint256(7), uint8(8)));
        vm.prank(ALICE);
        matchweek.submitPrediction(masks);
    }

    function testRevert_submitPrediction_predictionWindowClosed() public {
        vm.warp(_predictionDeadline);

        vm.expectRevert(Matchweek.PredictionWindowClosed.selector);
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidMasks());
    }

    function testRevert_submitPrediction_insufficientAllowance() public {
        vm.prank(ALICE);
        stablecoin.approve(address(matchweek), 0);

        vm.expectRevert();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidMasks());
    }

    function testRevert_submitPrediction_insufficientBalance() public {
        address poor = address(0xB0B);
        vm.prank(poor);
        stablecoin.approve(address(matchweek), type(uint256).max);

        vm.expectRevert();
        vm.prank(poor);
        matchweek.submitPrediction(_buildValidMasks());
    }

    /// @dev Deploys a fresh EIP-1167 minimal proxy clone of the implementation, mirroring how
    ///      PitchMkt creates instances.
    function _deployClone() internal returns (Matchweek) {
        return Matchweek(Clones.clone(_implementation));
    }

    /// @dev Asserts a per-tier public array holds exactly {MarketConfig.TIER_COUNT} slots, by
    ///      calling its generated index getter at the last valid index and one past it. A
    ///      fixed-size array's getter reverts with a bounds panic out of range, so the pair of
    ///      answers brackets the width exactly.
    /// @param getter Signature of the generated getter, e.g. `"prizePerTier(uint256)"`.
    function _assertTierArrayWidth(string memory getter) internal view {
        uint256 lastIndex = MarketConfig.TIER_COUNT - 1;

        assertTrue(_indexAnswers(getter, lastIndex), string.concat(getter, " must hold TIER_COUNT slots"));
        assertFalse(_indexAnswers(getter, lastIndex + 1), string.concat(getter, " must hold no more slots"));
    }

    /// @dev Whether a generated index getter answers for `index`, as opposed to reverting with the
    ///      bounds panic a fixed-size array raises past its end.
    function _indexAnswers(string memory getter, uint256 index) internal view returns (bool answers) {
        (answers,) = address(matchweek).staticcall(abi.encodeWithSignature(getter, index));
    }

    /// @dev Builds a valid set of ten outcomes (alternating home/draw/away).
    function _buildValidOutcomes() internal pure returns (uint8[10] memory outcomes) {
        for (uint256 i = 0; i < 10; ++i) {
            // forge-lint: disable-next-line(unsafe-typecast)
            outcomes[i] = uint8(i % 3);
        }
    }

    /// @dev Builds ten single masks (alternating home/draw/away) — a one-column prediction that
    ///      matches {_buildValidOutcomes} outcome for outcome.
    function _buildValidMasks() internal pure returns (uint8[10] memory masks) {
        uint8[3] memory singles = [MASK_HOME, MASK_DRAW, MASK_AWAY];
        for (uint256 i = 0; i < 10; ++i) {
            masks[i] = singles[i % 3];
        }
    }

    /// @dev Builds ten masks where the first `doubles` matches are doubles and the rest singles —
    ///      a prediction spanning `2**doubles` columns, so it costs `2**doubles × UNIT_PRICE`.
    function _buildMasksWithDoubles(uint256 doubles) internal pure returns (uint8[10] memory masks) {
        masks = _buildValidMasks();
        for (uint256 i = 0; i < doubles; ++i) {
            masks[i] = MASK_HOME | MASK_DRAW;
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

    ////
    /// Publish Results Tests
    ////

    function test_publishResults() public {
        uint8[10] memory outcomes = _buildValidOutcomes();

        vm.warp(_predictionDeadline);
        vm.expectEmit(true, false, false, true);
        emit Matchweek.ResultsPublished(MATCHWEEK_ID, outcomes);
        vm.prank(ADMIN);
        matchweek.publishResults(outcomes);

        assertEq(matchweek.resultsPublished(), true);
        uint8[10] memory stored = matchweek.getOutcomes();
        for (uint256 i = 0; i < 10; ++i) {
            assertEq(stored[i], outcomes[i]);
        }
    }

    function test_publishResults_opensDisputeWindow() public {
        vm.warp(_predictionDeadline);
        vm.prank(ADMIN);
        matchweek.publishResults(_buildValidOutcomes());

        assertEq(disputes.disputeDeadline(address(matchweek)), block.timestamp + DisputeConfig.DISPUTE_WINDOW);
    }

    function testRevert_publishResults_deadlineNotPassed() public {
        vm.expectRevert(Matchweek.DeadlineNotPassed.selector);
        vm.prank(ADMIN);
        matchweek.publishResults(_buildValidOutcomes());
    }

    function testRevert_publishResults_alreadyPublished() public {
        vm.warp(_predictionDeadline);
        vm.prank(ADMIN);
        matchweek.publishResults(_buildValidOutcomes());

        vm.expectRevert(Matchweek.ResultsAlreadyPublished.selector);
        vm.prank(ADMIN);
        matchweek.publishResults(_buildValidOutcomes());
    }

    function testRevert_publishResults_invalidOutcome() public {
        uint8[10] memory bad = _buildValidOutcomes();
        bad[4] = 3;

        vm.warp(_predictionDeadline);
        vm.expectRevert(abi.encodeWithSelector(Matchweek.InvalidOutcome.selector, uint256(4), uint8(3)));
        vm.prank(ADMIN);
        matchweek.publishResults(bad);
    }

    function testRevert_publishResults_notOwner() public {
        vm.warp(_predictionDeadline);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        vm.prank(ALICE);
        matchweek.publishResults(_buildValidOutcomes());
    }

    function testRevert_publishResults_publishWindowClosed() public {
        vm.warp(_predictionDeadline + MarketConfig.PUBLISH_TIMEOUT);
        vm.expectRevert(Matchweek.PublishWindowClosed.selector);
        vm.prank(ADMIN);
        matchweek.publishResults(_buildValidOutcomes());
    }

    ////
    /// Apply Dispute Correction Tests
    ////

    function test_applyDisputeCorrection_overwritesOutcomes() public {
        vm.warp(_predictionDeadline);
        vm.prank(ADMIN);
        matchweek.publishResults(_buildValidOutcomes());

        uint8[10] memory corrected = _buildValidOutcomes();
        corrected[0] = corrected[0] == 0 ? uint8(1) : uint8(0);

        vm.expectEmit(true, false, false, true);
        emit Matchweek.ResultsCorrected(MATCHWEEK_ID, corrected);
        vm.prank(address(disputes));
        matchweek.applyDisputeCorrection(corrected);

        uint8[10] memory stored = matchweek.getOutcomes();
        for (uint256 i = 0; i < 10; ++i) {
            assertEq(stored[i], corrected[i]);
        }
    }

    function testRevert_applyDisputeCorrection_notDisputes() public {
        vm.warp(_predictionDeadline);
        vm.prank(ADMIN);
        matchweek.publishResults(_buildValidOutcomes());

        vm.expectRevert(Matchweek.NotDisputes.selector);
        vm.prank(ADMIN);
        matchweek.applyDisputeCorrection(_buildValidOutcomes());
    }

    function testRevert_applyDisputeCorrection_invalidOutcome() public {
        vm.warp(_predictionDeadline);
        vm.prank(ADMIN);
        matchweek.publishResults(_buildValidOutcomes());

        uint8[10] memory bad = _buildValidOutcomes();
        bad[2] = 3;

        vm.expectRevert(abi.encodeWithSelector(Matchweek.InvalidOutcome.selector, uint256(2), uint8(3)));
        vm.prank(address(disputes));
        matchweek.applyDisputeCorrection(bad);
    }

    ////
    /// Commit Distribution Tests
    ////

    function testRevert_commitDistribution_disputeWindowOpen() public {
        vm.warp(_predictionDeadline);
        vm.prank(ADMIN);
        matchweek.publishResults(_buildValidOutcomes());

        // Dispute window still open — no warp past DisputeConfig.DISPUTE_WINDOW.
        vm.expectRevert(Matchweek.DisputeNotSettled.selector);
        vm.prank(ADMIN);
        matchweek.commitDistribution(bytes32(0), _emptyUint5());
    }

    function test_commitDistribution_prizeComputedOnChain() public {
        uint256 cost = matchweek.UNIT_PRICE();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidMasks());

        _publishResults();

        // Alice is the only winner, in tier 6 (index 0, TIER6_PRIZE_PCT of pool).
        bytes32 root = _merkleLeaf(0, _columnsAt(6, 1));
        uint256[5] memory totalStakePerTier_;
        totalStakePerTier_[0] = cost;

        // prizePerTier[0] = cost * TIER6_PRIZE_PCT / 100, fee = cost * PROTOCOL_FEE_PCT / 100,
        // unallocated = remainder after both.
        uint256 expectedPrize = cost * MarketConfig.TIER6_PRIZE_PCT / 100;
        uint256 expectedFee = cost * MarketConfig.PROTOCOL_FEE_PCT / 100;
        uint256 expectedUnallocated = cost - expectedPrize - expectedFee;

        uint256[5] memory expectedPrizes;
        expectedPrizes[0] = expectedPrize;

        vm.expectEmit(true, false, false, true);
        emit Matchweek.DistributionCommitted(MATCHWEEK_ID, root, expectedPrizes, expectedUnallocated, expectedFee);
        vm.prank(ADMIN);
        matchweek.commitDistribution(root, totalStakePerTier_);

        assertEq(matchweek.distributionCommittedAt(), uint40(block.timestamp));
        assertEq(matchweek.claimsRoot(), root);
        assertEq(matchweek.prizePerTier(0), expectedPrize);
        assertEq(matchweek.unallocated(), expectedUnallocated);
        assertEq(matchweek.protocolFee(), expectedFee);
    }

    function test_commitDistribution_emptyTiersGoToUnallocated() public {
        uint256 cost = matchweek.UNIT_PRICE();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidMasks());

        _publishResults();

        // No winners in any tier → everything except the protocol fee goes to unallocated.
        vm.prank(ADMIN);
        matchweek.commitDistribution(bytes32(0), _emptyUint5());

        uint256 expectedFee = cost * MarketConfig.PROTOCOL_FEE_PCT / 100;
        assertEq(matchweek.unallocated(), cost - expectedFee);
        assertEq(matchweek.protocolFee(), expectedFee);
        for (uint256 i = 0; i < MarketConfig.TIER_COUNT; ++i) {
            assertEq(matchweek.prizePerTier(i), 0);
        }
    }

    function test_commitDistribution_totalStakedSumsDerivedCosts() public {
        stablecoin.mint(BOB, 1_000_000_000);
        vm.prank(BOB);
        stablecoin.approve(address(matchweek), type(uint256).max);

        uint256 aliceCost = matchweek.UNIT_PRICE(); // ten singles — one column
        uint256 bobCost = matchweek.UNIT_PRICE() * 4; // two doubles — four columns
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidMasks());
        vm.prank(BOB);
        matchweek.submitPrediction(_buildMasksWithDoubles(2));

        assertEq(matchweek.totalStaked(), aliceCost + bobCost);

        _publishResults();
        vm.prank(ADMIN);
        matchweek.commitDistribution(bytes32(0), _emptyUint5());

        uint256 expectedFee = (aliceCost + bobCost) * MarketConfig.PROTOCOL_FEE_PCT / 100;
        assertEq(matchweek.protocolFee(), expectedFee);
    }

    function testRevert_commitDistribution_resultsNotPublished() public {
        vm.expectRevert(Matchweek.ResultsNotPublished.selector);
        vm.prank(ADMIN);
        matchweek.commitDistribution(bytes32(0), _emptyUint5());
    }

    function testRevert_commitDistribution_alreadyCommitted() public {
        _publishResults();
        vm.prank(ADMIN);
        matchweek.commitDistribution(bytes32(0), _emptyUint5());

        vm.expectRevert(Matchweek.DistributionAlreadyCommitted.selector);
        vm.prank(ADMIN);
        matchweek.commitDistribution(bytes32(0), _emptyUint5());
    }

    function testRevert_commitDistribution_notOwner() public {
        _publishResults();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        vm.prank(ALICE);
        matchweek.commitDistribution(bytes32(0), _emptyUint5());
    }

    ////
    /// Claim Prize Tests
    ////

    function test_claimPrize_singleWinner() public {
        uint256 cost = matchweek.UNIT_PRICE();
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidMasks());

        _publishResults();

        // Single leaf: root = leaf, proof = [].
        // Tier 7 (index 1) = 10% of totalStaked.
        uint8 tier = 7;
        uint256[5] memory columns = _columnsAt(tier, 1);
        bytes32 leaf = _merkleLeaf(predictionId, columns);

        uint256[5] memory totalStakePerTier_;
        totalStakePerTier_[tier - MarketConfig.MIN_WINNING_TIER] = cost;

        vm.prank(ADMIN);
        matchweek.commitDistribution(leaf, totalStakePerTier_);

        uint256 expectedShare = cost * MarketConfig.TIER7_PRIZE_PCT / 100; // tier 7 = index 1
        uint256 balanceBefore = stablecoin.balanceOf(ALICE);

        vm.expectEmit(true, true, true, true);
        emit Matchweek.PrizeClaimed(matchweek.matchweekId(), predictionId, ALICE, expectedShare, columns);
        vm.prank(ALICE);
        matchweek.claimPrize(predictionId, columns, new bytes32[](0));

        assertEq(stablecoin.balanceOf(ALICE), balanceBefore + expectedShare);
        assertEq(matchweek.claimed(predictionId), true);
    }

    // One correctly-guessed double splits Bob's 4 columns across tiers 10, 9 and 8, and a single
    // call pays all three.
    function test_claimPrize_everyTierInOneCall() public {
        stablecoin.mint(BOB, 1_000_000_000);
        vm.prank(BOB);
        stablecoin.approve(address(matchweek), type(uint256).max);

        uint256 unitPrice = matchweek.UNIT_PRICE();
        vm.prank(BOB);
        uint256 predictionId = matchweek.submitPrediction(_buildMasksWithDoubles(2));
        assertEq(matchweek.predictionColumns(predictionId), 4);

        _publishResults();

        // 1 column at ten, 2 at nine, 1 at eight — the whole prediction, in one leaf.
        uint256[5] memory columns = [uint256(0), 0, 1, 2, 1];
        uint256[5] memory totalStakePerTier_ = [uint256(0), 0, unitPrice, 2 * unitPrice, unitPrice];

        vm.prank(ADMIN);
        matchweek.commitDistribution(_merkleLeaf(predictionId, columns), totalStakePerTier_);

        // Bob is the only winner in each tier, so he takes all three pools whole.
        uint256 expectedShare = matchweek.prizePerTier(2) + matchweek.prizePerTier(3) + matchweek.prizePerTier(4);
        uint256 balanceBefore = stablecoin.balanceOf(BOB);

        vm.expectEmit(true, true, true, true);
        emit Matchweek.PrizeClaimed(matchweek.matchweekId(), predictionId, BOB, expectedShare, columns);
        vm.prank(BOB);
        matchweek.claimPrize(predictionId, columns, new bytes32[](0));

        assertEq(stablecoin.balanceOf(BOB), balanceBefore + expectedShare);
        assertEq(matchweek.claimed(predictionId), true);
    }

    function test_claimPrize_multipleWinners_evenSplit() public {
        stablecoin.mint(BOB, 1_000_000_000);
        vm.prank(BOB);
        stablecoin.approve(address(matchweek), type(uint256).max);

        uint256 cost = matchweek.UNIT_PRICE();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidMasks());
        vm.prank(BOB);
        matchweek.submitPrediction(_buildValidMasks());

        _publishResults();
        _commitTwoPredictionDistribution(0, _columnsAt(8, 1), 1, _columnsAt(8, 1));

        // Tier 8 (index 2) = 15% of totalStaked, split evenly since both reach it with one column.
        uint256 tierPool = matchweek.prizePerTier(8 - MarketConfig.MIN_WINNING_TIER);
        uint256 tierTotalStake = matchweek.totalStakePerTier(8 - MarketConfig.MIN_WINNING_TIER);

        (bytes32[] memory proofAlice, bytes32[] memory proofBob) =
            _buildTwoPredictionProofs(0, _columnsAt(8, 1), 1, _columnsAt(8, 1));

        uint256 shareAlice = tierPool * cost / tierTotalStake;
        uint256 shareBob = tierPool * cost / tierTotalStake;

        vm.prank(ALICE);
        matchweek.claimPrize(0, _columnsAt(8, 1), proofAlice);
        vm.prank(BOB);
        matchweek.claimPrize(1, _columnsAt(8, 1), proofBob);

        assertEq(stablecoin.balanceOf(ALICE), 1_000_000_000 - cost + shareAlice);
        assertEq(stablecoin.balanceOf(BOB), 1_000_000_000 - cost + shareBob);
    }

    function test_claimPrize_proportionalSplit() public {
        stablecoin.mint(BOB, 1_000_000_000);
        vm.prank(BOB);
        stablecoin.approve(address(matchweek), type(uint256).max);

        uint256 aliceCost = matchweek.UNIT_PRICE(); // ten singles — one column
        uint256 bobCost = matchweek.UNIT_PRICE() * 2; // one double — two columns
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidMasks());
        vm.prank(BOB);
        matchweek.submitPrediction(_buildMasksWithDoubles(1));

        _publishResults();
        _commitTwoPredictionDistribution(0, _columnsAt(8, 1), 1, _columnsAt(8, 2));

        uint256 tierPool = matchweek.prizePerTier(8 - MarketConfig.MIN_WINNING_TIER);
        uint256 tierTotalStake = matchweek.totalStakePerTier(8 - MarketConfig.MIN_WINNING_TIER);
        (bytes32[] memory proofAlice, bytes32[] memory proofBob) =
            _buildTwoPredictionProofs(0, _columnsAt(8, 1), 1, _columnsAt(8, 2));

        uint256 expectedShareAlice = tierPool * aliceCost / tierTotalStake;
        uint256 expectedShareBob = tierPool * bobCost / tierTotalStake;

        vm.prank(ALICE);
        matchweek.claimPrize(0, _columnsAt(8, 1), proofAlice);
        vm.prank(BOB);
        matchweek.claimPrize(1, _columnsAt(8, 2), proofBob);

        assertEq(stablecoin.balanceOf(ALICE), 1_000_000_000 - aliceCost + expectedShareAlice);
        assertEq(stablecoin.balanceOf(BOB), 1_000_000_000 - bobCost + expectedShareBob);
        // Bob reaches the tier with twice the columns Alice does, so his share is exactly twice hers.
        assertEq(expectedShareBob, expectedShareAlice * 2);
    }

    // Bob plays two doubles (4 columns) but reaches tier 8 with only one of them.
    function test_claimPrize_sharesOnlyWinningColumns() public {
        stablecoin.mint(BOB, 1_000_000_000);
        vm.prank(BOB);
        stablecoin.approve(address(matchweek), type(uint256).max);

        uint256 unitPrice = matchweek.UNIT_PRICE();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidMasks());
        vm.prank(BOB);
        matchweek.submitPrediction(_buildMasksWithDoubles(2));
        assertEq(matchweek.predictionCost(1), unitPrice * 4);

        _publishResults();
        _commitTwoPredictionDistribution(0, _columnsAt(8, 1), 1, _columnsAt(8, 1));

        uint256 tierPool = matchweek.prizePerTier(8 - MarketConfig.MIN_WINNING_TIER);
        uint256 tierTotalStake = matchweek.totalStakePerTier(8 - MarketConfig.MIN_WINNING_TIER);
        (, bytes32[] memory proofBob) = _buildTwoPredictionProofs(0, _columnsAt(8, 1), 1, _columnsAt(8, 1));

        uint256 expectedShare = tierPool * unitPrice / tierTotalStake;
        uint256 balanceBefore = stablecoin.balanceOf(BOB);

        vm.prank(BOB);
        matchweek.claimPrize(1, _columnsAt(8, 1), proofBob);

        assertEq(stablecoin.balanceOf(BOB), balanceBefore + expectedShare);
        assertEq(expectedShare, tierPool / 2);
    }

    // The double is on a match whose actual outcome it excludes, so both columns miss it equally
    // and land in the same tier — a multiple does not always split.
    function test_claimPrize_missedMultipleDoesNotSplit() public {
        uint256 unitPrice = matchweek.UNIT_PRICE();
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildMasksWithMissedDouble());
        assertEq(matchweek.predictionColumns(predictionId), 2);

        _publishResults();

        // Both columns at tier 9, nothing anywhere else.
        uint256[5] memory columns = _columnsAt(9, 2);
        uint256[5] memory totalStakePerTier_ = _columnsAt(9, 2 * unitPrice);

        vm.prank(ADMIN);
        matchweek.commitDistribution(_merkleLeaf(predictionId, columns), totalStakePerTier_);

        uint256 expectedShare = matchweek.prizePerTier(9 - MarketConfig.MIN_WINNING_TIER);
        uint256 balanceBefore = stablecoin.balanceOf(ALICE);

        vm.prank(ALICE);
        matchweek.claimPrize(predictionId, columns, new bytes32[](0));

        assertEq(stablecoin.balanceOf(ALICE), balanceBefore + expectedShare);
    }

    // Alice (two doubles) and Bob (one double) reach tiers 10 and 9 with different column counts,
    // and Alice reaches 8 alone. Every tier splits on its own denominator.
    function test_claimPrize_proportionalAcrossSeveralTiers() public {
        stablecoin.mint(BOB, 1_000_000_000);
        vm.prank(BOB);
        stablecoin.approve(address(matchweek), type(uint256).max);

        vm.prank(ALICE);
        matchweek.submitPrediction(_buildMasksWithDoubles(2));
        vm.prank(BOB);
        matchweek.submitPrediction(_buildMasksWithDoubles(1));

        _publishResults();

        uint256[5] memory columnsAlice = [uint256(0), 0, 1, 2, 1];
        uint256[5] memory columnsBob = [uint256(0), 0, 0, 1, 1];
        _commitTwoPredictionDistribution(0, columnsAlice, 1, columnsBob);

        (bytes32[] memory proofAlice, bytes32[] memory proofBob) =
            _buildTwoPredictionProofs(0, columnsAlice, 1, columnsBob);

        // Tier 10: 1 of 2 columns each. Tier 9: 2 of 3 for Alice, 1 of 3 for Bob. Tier 8: Alice alone.
        uint256 expectedAlice =
            matchweek.prizePerTier(4) / 2 + matchweek.prizePerTier(3) * 2 / 3 + matchweek.prizePerTier(2);
        uint256 expectedBob = matchweek.prizePerTier(4) / 2 + matchweek.prizePerTier(3) * 1 / 3;

        uint256 balanceAlice = stablecoin.balanceOf(ALICE);
        uint256 balanceBob = stablecoin.balanceOf(BOB);

        vm.prank(ALICE);
        matchweek.claimPrize(0, columnsAlice, proofAlice);
        vm.prank(BOB);
        matchweek.claimPrize(1, columnsBob, proofBob);

        assertEq(stablecoin.balanceOf(ALICE), balanceAlice + expectedAlice);
        assertEq(stablecoin.balanceOf(BOB), balanceBob + expectedBob);

        // Everything paid across both claims stays within the three tier pools — integer division
        // can only leave dust behind, never overdraw.
        uint256 pools = matchweek.prizePerTier(2) + matchweek.prizePerTier(3) + matchweek.prizePerTier(4);
        assertLe(expectedAlice + expectedBob, pools);
    }

    // Same prediction and same total columns, but moved from tier 9 to tier 10 — fails at Merkle.
    function testRevert_claimPrize_tamperedVector() public {
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildMasksWithDoubles(1));

        _publishResults();

        uint256[5] memory committed = [uint256(0), 0, 0, 1, 1];
        uint256[5] memory tampered = [uint256(0), 0, 0, 0, 2];
        uint256[5] memory totalStakePerTier_ = [uint256(0), 0, 0, matchweek.UNIT_PRICE(), matchweek.UNIT_PRICE()];

        vm.prank(ADMIN);
        matchweek.commitDistribution(_merkleLeaf(predictionId, committed), totalStakePerTier_);

        vm.expectRevert(abi.encodeWithSelector(Matchweek.InvalidProof.selector, predictionId));
        vm.prank(ALICE);
        matchweek.claimPrize(predictionId, tampered, new bytes32[](0));
    }

    // The vector reaches tier 10 but the admin left that tier's total at zero.
    function testRevert_claimPrize_emptyTierPoolInVector() public {
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildMasksWithDoubles(1));

        _publishResults();

        uint256[5] memory columns = [uint256(0), 0, 0, 1, 1];
        uint256[5] memory totalStakePerTier_ = _columnsAt(9, matchweek.UNIT_PRICE());

        vm.prank(ADMIN);
        matchweek.commitDistribution(_merkleLeaf(predictionId, columns), totalStakePerTier_);

        vm.expectRevert(abi.encodeWithSelector(Matchweek.EmptyTierPool.selector, uint8(10)));
        vm.prank(ALICE);
        matchweek.claimPrize(predictionId, columns, new bytes32[](0));
    }

    // Right prediction, inflated column count — the leaf no longer matches, fails at Merkle.
    function testRevert_claimPrize_wrongColumnCount() public {
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildMasksWithDoubles(2));

        _publishResults();
        bytes32 root = _merkleLeaf(predictionId, _columnsAt(8, 1));
        uint256[5] memory totalStakePerTier_;
        totalStakePerTier_[8 - MarketConfig.MIN_WINNING_TIER] = matchweek.UNIT_PRICE();
        vm.prank(ADMIN);
        matchweek.commitDistribution(root, totalStakePerTier_);

        vm.expectRevert(abi.encodeWithSelector(Matchweek.InvalidProof.selector, predictionId));
        vm.prank(ALICE);
        matchweek.claimPrize(predictionId, _columnsAt(8, 4), new bytes32[](0));
    }

    // Alice is in the tree at tier 7 but claims her column at tier 10 — wrong proof, fails at Merkle.
    function testRevert_claimPrize_wrongTierProof() public {
        uint256 cost = matchweek.UNIT_PRICE();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidMasks());

        _publishResults();

        uint8 aliceTier = 7;
        bytes32 root = _merkleLeaf(0, _columnsAt(aliceTier, 1));

        uint256[5] memory totalStakePerTier_;
        totalStakePerTier_[aliceTier - 6] = cost;

        vm.prank(ADMIN);
        matchweek.commitDistribution(root, totalStakePerTier_);

        vm.expectRevert(abi.encodeWithSelector(Matchweek.InvalidProof.selector, uint256(0)));
        vm.prank(ALICE);
        matchweek.claimPrize(0, _columnsAt(10, 1), new bytes32[](0));
    }

    // Alice is in the tree at tier 7 but admin set totalStakePerTier[7-6] = 0 by mistake
    // → contract computes prizePerTier[7-6] = 0 → EmptyTierPool.
    function testRevert_claimPrize_emptyTierPool() public {
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidMasks());

        _publishResults();

        uint8 tier = 7;
        bytes32 root = _merkleLeaf(0, _columnsAt(tier, 1));

        // Winning tier total is 0 → contract sets prizePerTier[tier-6] = 0 → EmptyTierPool on claim.
        vm.prank(ADMIN);
        matchweek.commitDistribution(root, _emptyUint5());

        vm.expectRevert(abi.encodeWithSelector(Matchweek.EmptyTierPool.selector, tier));
        vm.prank(ALICE);
        matchweek.claimPrize(0, _columnsAt(tier, 1), new bytes32[](0));
    }

    function testRevert_claimPrize_distributionNotCommitted() public {
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidMasks());

        vm.expectRevert(Matchweek.DistributionNotCommitted.selector);
        vm.prank(ALICE);
        matchweek.claimPrize(0, _columnsAt(7, 1), new bytes32[](0));
    }

    function testRevert_claimPrize_notPredictionOwner() public {
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidMasks());

        _publishAndCommitSinglePrediction(predictionId, 7);

        vm.expectRevert(abi.encodeWithSelector(Matchweek.NotPredictionOwner.selector, predictionId));
        vm.prank(address(0xB0B));
        matchweek.claimPrize(predictionId, _columnsAt(7, 1), new bytes32[](0));
    }

    function testRevert_claimPrize_alreadyClaimed() public {
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidMasks());

        _publishAndCommitSinglePrediction(predictionId, 7);

        vm.prank(ALICE);
        matchweek.claimPrize(predictionId, _columnsAt(7, 1), new bytes32[](0));

        vm.expectRevert(abi.encodeWithSelector(Matchweek.AlreadyClaimed.selector, predictionId));
        vm.prank(ALICE);
        matchweek.claimPrize(predictionId, _columnsAt(7, 1), new bytes32[](0));
    }

    function testRevert_claimPrize_invalidProof() public {
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidMasks());

        _publishAndCommitSinglePrediction(predictionId, 7);

        // Correct tier is 7 but claiming tier 8
        vm.expectRevert(abi.encodeWithSelector(Matchweek.InvalidProof.selector, predictionId));
        vm.prank(ALICE);
        matchweek.claimPrize(predictionId, _columnsAt(8, 1), new bytes32[](0));
    }

    ////
    /// Carry Pool Tests
    ////

    function test_commitDistribution_unallocatedFundsCarryPool() public {
        uint256 cost = matchweek.UNIT_PRICE();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidMasks());

        _publishResults();

        // No winners in any tier → everything except the protocol fee moves to the carry pool.
        vm.prank(ADMIN);
        matchweek.commitDistribution(bytes32(0), _emptyUint5());

        uint256 expectedCarry = cost - cost * MarketConfig.PROTOCOL_FEE_PCT / 100;
        assertEq(carryPool.carriedBalance(), expectedCarry);
        assertEq(stablecoin.balanceOf(address(carryPool)), expectedCarry);
        assertEq(stablecoin.balanceOf(address(matchweek)), 0);
    }

    function test_commitDistribution_perfectTenReleasesCarryPool() public {
        uint256 cost = matchweek.UNIT_PRICE();

        // Deploy the second matchweek and have Bob enter before time is warped forward, since
        // {initialize} requires a future predictionDeadline.
        Matchweek matchweek2 = _deployClone();
        matchweek2.initialize(MATCHWEEK_ID + 1, _predictionDeadline, _buildValidMatches(), ADMIN);
        carryPool.registerMatchweek(address(matchweek2));
        treasury.registerMatchweek(address(matchweek2));
        disputes.registerMatchweek(address(matchweek2));

        stablecoin.mint(BOB, 1_000_000_000);
        vm.prank(BOB);
        stablecoin.approve(address(matchweek2), type(uint256).max);
        vm.prank(BOB);
        uint256 predictionId = matchweek2.submitPrediction(_buildValidMasks());

        uint256 fee = cost * MarketConfig.PROTOCOL_FEE_PCT / 100;

        // First matchweek: no winners, its only prediction's cost net of the fee seeds the carry pool.
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidMasks());
        _publishResults();
        vm.prank(ADMIN);
        matchweek.commitDistribution(bytes32(0), _emptyUint5());
        assertEq(carryPool.carriedBalance(), cost - fee);

        // Second matchweek: Bob hits a perfect ten and should receive the carried balance on
        // top of the normal tier-10 prize.
        vm.prank(ADMIN);
        matchweek2.publishResults(_buildValidOutcomes());
        vm.warp(block.timestamp + DisputeConfig.DISPUTE_WINDOW);

        uint8 tier = 10;
        bytes32 root = _merkleLeaf(predictionId, _columnsAt(tier, 1));
        uint256[5] memory totalStakePerTier_;
        totalStakePerTier_[tier - MarketConfig.MIN_WINNING_TIER] = cost;

        vm.prank(ADMIN);
        matchweek2.commitDistribution(root, totalStakePerTier_);

        uint256 tier10Prize = cost * MarketConfig.TIER10_PRIZE_PCT / 100;
        uint256 expectedPrizePerTier10 = tier10Prize + (cost - fee);
        assertEq(matchweek2.prizePerTier(MarketConfig.TIER_COUNT - 1), expectedPrizePerTier10);

        // matchweek2's own leftover, net of its fee, reseeds the carry pool for the next cycle.
        uint256 expectedUnallocated2 = cost - tier10Prize - fee;
        assertEq(carryPool.carriedBalance(), expectedUnallocated2);

        uint256 balanceBefore = stablecoin.balanceOf(BOB);
        vm.prank(BOB);
        matchweek2.claimPrize(predictionId, _columnsAt(tier, 1), new bytes32[](0));
        assertEq(stablecoin.balanceOf(BOB), balanceBefore + expectedPrizePerTier10);
    }

    ////
    /// Protocol Fee Tests
    ////

    function test_commitDistribution_feeGoesToTreasury() public {
        uint256 cost = matchweek.UNIT_PRICE();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidMasks());

        _publishResults();

        vm.prank(ADMIN);
        matchweek.commitDistribution(bytes32(0), _emptyUint5());

        uint256 expectedFee = cost * MarketConfig.PROTOCOL_FEE_PCT / 100;
        assertEq(treasury.collectedBalance(), expectedFee);
        assertEq(treasury.collectedByMatchweek(MATCHWEEK_ID), expectedFee);
        assertEq(stablecoin.balanceOf(address(treasury)), expectedFee);
    }

    /// @dev The whitepaper requires the carry pool to hold unawarded prize money only, never fees.
    function test_commitDistribution_carryPoolExcludesFee() public {
        uint256 cost = matchweek.UNIT_PRICE();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidMasks());

        _publishResults();

        vm.prank(ADMIN);
        matchweek.commitDistribution(bytes32(0), _emptyUint5());

        uint256 expectedFee = cost * MarketConfig.PROTOCOL_FEE_PCT / 100;
        assertEq(carryPool.carriedBalance(), cost - expectedFee);
        assertEq(matchweek.unallocated(), cost - expectedFee);
    }

    /// @dev Every staked unit must end up in exactly one of: tier prizes, carry pool, treasury.
    function test_commitDistribution_reconcilesToTotalStaked() public {
        uint256 cost = matchweek.UNIT_PRICE();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidMasks());
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidMasks());
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidMasks());

        _publishResults();

        // Winners in tiers 6 and 9, leaving tiers 7, 8 and 10 empty.
        uint256[5] memory totalStakePerTier_;
        totalStakePerTier_[0] = cost;
        totalStakePerTier_[3] = cost;

        vm.prank(ADMIN);
        matchweek.commitDistribution(bytes32(0), totalStakePerTier_);

        uint256 totalStakedExpected = 3 * cost;
        uint256 totalPrizes;
        for (uint256 i = 0; i < MarketConfig.TIER_COUNT; ++i) {
            totalPrizes += matchweek.prizePerTier(i);
        }

        assertEq(totalPrizes + carryPool.carriedBalance() + treasury.collectedBalance(), totalStakedExpected);
        assertEq(stablecoin.balanceOf(address(matchweek)), totalPrizes);
    }

    /// @dev Integer-division dust must fall to the carry pool, never inflate the fee.
    function test_commitDistribution_feeNeverExceedsItsPercentage() public {
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidMasks());

        _publishResults();

        vm.prank(ADMIN);
        matchweek.commitDistribution(bytes32(0), _emptyUint5());

        uint256 totalStakedExpected = matchweek.totalStaked();
        assertLe(matchweek.protocolFee() * 100, totalStakedExpected * MarketConfig.PROTOCOL_FEE_PCT);
    }

    ////
    /// Sweep Unclaimed Tests
    ////

    // Alice is the only winner (tier 7) and never claims. The other four tiers have no winners,
    // so their percentages already left for CarryPool as `unallocated` at commit time — what's
    // left in the clone once the window closes is exactly `prizePerTier[7-6]`, and CarryPool.fund
    // gets called a second time on top of that commit-time funding.
    function test_sweepUnclaimed_transfersRemainingBalanceToCarryPool() public {
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidMasks());

        _publishAndCommitSinglePrediction(predictionId, 7);

        uint256 unclaimedPrize = matchweek.prizePerTier(7 - MarketConfig.MIN_WINNING_TIER);
        assertEq(stablecoin.balanceOf(address(matchweek)), unclaimedPrize, "clone holds only the unclaimed prize");

        uint256 carryPoolBalanceBefore = carryPool.carriedBalance();

        vm.warp(matchweek.distributionCommittedAt() + MarketConfig.CLAIM_WINDOW);
        // Callable by anyone — a bystander with no stake in the matchweek, not the admin.
        vm.prank(address(0xBEEF));
        matchweek.sweepUnclaimed();

        assertEq(stablecoin.balanceOf(address(matchweek)), 0);
        assertEq(carryPool.carriedBalance(), carryPoolBalanceBefore + unclaimedPrize);
        assertEq(matchweek.swept(), true);
    }

    function test_sweepUnclaimed_emitsEvent() public {
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidMasks());

        _publishAndCommitSinglePrediction(predictionId, 7);

        uint256 unclaimedPrize = matchweek.prizePerTier(7 - MarketConfig.MIN_WINNING_TIER);
        vm.warp(matchweek.distributionCommittedAt() + MarketConfig.CLAIM_WINDOW);

        vm.expectEmit(true, false, false, true);
        emit Matchweek.UnclaimedSwept(MATCHWEEK_ID, unclaimedPrize);
        matchweek.sweepUnclaimed();
    }

    // A prize claimed before the window closes is not part of the sweep.
    function test_sweepUnclaimed_excludesAlreadyClaimedPrizes() public {
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidMasks());

        _publishAndCommitSinglePrediction(predictionId, 7);

        vm.prank(ALICE);
        matchweek.claimPrize(predictionId, _columnsAt(7, 1), new bytes32[](0));
        assertEq(stablecoin.balanceOf(address(matchweek)), 0);

        vm.warp(matchweek.distributionCommittedAt() + MarketConfig.CLAIM_WINDOW);
        uint256 carryPoolBalanceBefore = carryPool.carriedBalance();
        matchweek.sweepUnclaimed();

        assertEq(carryPool.carriedBalance(), carryPoolBalanceBefore);
    }

    function testRevert_sweepUnclaimed_beforeWindowCloses() public {
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidMasks());

        _publishAndCommitSinglePrediction(predictionId, 7);

        vm.warp(matchweek.distributionCommittedAt() + MarketConfig.CLAIM_WINDOW - 1);
        vm.expectRevert(Matchweek.ClaimWindowNotClosed.selector);
        matchweek.sweepUnclaimed();
    }

    function testRevert_sweepUnclaimed_distributionNotCommitted() public {
        vm.expectRevert(Matchweek.DistributionNotCommitted.selector);
        matchweek.sweepUnclaimed();
    }

    function testRevert_sweepUnclaimed_alreadySwept() public {
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidMasks());

        _publishAndCommitSinglePrediction(predictionId, 7);

        vm.warp(matchweek.distributionCommittedAt() + MarketConfig.CLAIM_WINDOW);
        matchweek.sweepUnclaimed();

        vm.expectRevert(Matchweek.AlreadySwept.selector);
        matchweek.sweepUnclaimed();
    }

    function testRevert_claimPrize_afterClaimWindowClosed() public {
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidMasks());

        _publishAndCommitSinglePrediction(predictionId, 7);

        vm.warp(matchweek.distributionCommittedAt() + MarketConfig.CLAIM_WINDOW);
        vm.expectRevert(Matchweek.ClaimWindowClosed.selector);
        vm.prank(ALICE);
        matchweek.claimPrize(predictionId, _columnsAt(7, 1), new bytes32[](0));
    }

    function test_claimPrize_stillWorksJustBeforeWindowCloses() public {
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidMasks());

        _publishAndCommitSinglePrediction(predictionId, 7);

        vm.warp(matchweek.distributionCommittedAt() + MarketConfig.CLAIM_WINDOW - 1);
        vm.prank(ALICE);
        matchweek.claimPrize(predictionId, _columnsAt(7, 1), new bytes32[](0));

        assertEq(matchweek.claimed(predictionId), true);
    }

    ////
    /// claimRefund Tests
    ////

    function test_claimRefund_paysPredictionCost() public {
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidMasks());
        uint256 cost = matchweek.predictionCost(predictionId);
        uint256 balanceBefore = stablecoin.balanceOf(ALICE);

        _publishDisputeAndTimeoutRefund();

        vm.expectEmit(true, true, true, true);
        emit Matchweek.RefundClaimed(MATCHWEEK_ID, predictionId, ALICE, cost);
        vm.prank(ALICE);
        matchweek.claimRefund(predictionId);

        assertEq(stablecoin.balanceOf(ALICE), balanceBefore + cost);
        assertEq(matchweek.refundClaimed(predictionId), true);
    }

    function testRevert_claimRefund_notRefunded() public {
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidMasks());

        vm.expectRevert(Matchweek.MatchweekNotRefunded.selector);
        vm.prank(ALICE);
        matchweek.claimRefund(predictionId);
    }

    function test_claimRefund_afterPublishTimeout_paysPredictionCost() public {
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidMasks());
        uint256 cost = matchweek.predictionCost(predictionId);
        uint256 balanceBefore = stablecoin.balanceOf(ALICE);

        _timeoutRefundWithoutPublish();

        vm.expectEmit(true, true, true, true);
        emit Matchweek.RefundClaimed(MATCHWEEK_ID, predictionId, ALICE, cost);
        vm.prank(ALICE);
        matchweek.claimRefund(predictionId);

        assertEq(stablecoin.balanceOf(ALICE), balanceBefore + cost);
        assertEq(matchweek.refundClaimed(predictionId), true);
    }

    function testRevert_claimRefund_beforePublishTimeout() public {
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidMasks());

        vm.warp(_predictionDeadline + MarketConfig.PUBLISH_TIMEOUT - 1);
        vm.expectRevert(Matchweek.MatchweekNotRefunded.selector);
        vm.prank(ALICE);
        matchweek.claimRefund(predictionId);
    }

    function testRevert_claimRefund_notOwner() public {
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidMasks());

        _publishDisputeAndTimeoutRefund();

        vm.expectRevert(abi.encodeWithSelector(Matchweek.NotPredictionOwner.selector, predictionId));
        vm.prank(BOB);
        matchweek.claimRefund(predictionId);
    }

    function testRevert_claimRefund_alreadyClaimed() public {
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidMasks());

        _publishDisputeAndTimeoutRefund();

        vm.prank(ALICE);
        matchweek.claimRefund(predictionId);

        vm.expectRevert(abi.encodeWithSelector(Matchweek.RefundAlreadyClaimed.selector, predictionId));
        vm.prank(ALICE);
        matchweek.claimRefund(predictionId);
    }

    function testRevert_commitDistribution_afterTimeoutRefund() public {
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidMasks());

        _publishDisputeAndTimeoutRefund();

        vm.expectRevert(Matchweek.DisputeNotSettled.selector);
        vm.prank(ADMIN);
        matchweek.commitDistribution(bytes32(0), _emptyUint5());
    }

    ////
    /// Test Helpers
    ////

    /// @dev Warps to the prediction deadline, has the admin publish results, then warps past the
    ///      dispute window so the matchweek is settled and {commitDistribution} is unblocked.
    function _publishResults() internal {
        vm.warp(_predictionDeadline);
        vm.prank(ADMIN);
        matchweek.publishResults(_buildValidOutcomes());
        vm.warp(block.timestamp + DisputeConfig.DISPUTE_WINDOW);
    }

    /// @dev Publishes results, has {CHALLENGER} dispute them within the window, then warps past
    ///      {DisputeConfig.RESOLUTION_TIMEOUT} without the admin resolving and triggers the
    ///      timeout refund, leaving the matchweek permanently refunded.
    function _publishDisputeAndTimeoutRefund() internal {
        vm.warp(_predictionDeadline);
        vm.prank(ADMIN);
        matchweek.publishResults(_buildValidOutcomes());

        stablecoin.mint(CHALLENGER, DisputeConfig.DISPUTE_BOND);
        vm.prank(CHALLENGER);
        stablecoin.approve(address(disputes), DisputeConfig.DISPUTE_BOND);
        vm.prank(CHALLENGER);
        disputes.disputeResults(address(matchweek), keccak256("evidence"));

        vm.warp(block.timestamp + DisputeConfig.RESOLUTION_TIMEOUT);
        disputes.refundAfterTimeout(address(matchweek));
    }

    /// @dev Warps past {MarketConfig.PUBLISH_TIMEOUT} since {_predictionDeadline} without the
    ///      admin ever calling {Matchweek.publishResults}, leaving the matchweek refundable via
    ///      the never-published branch of {Matchweek-_whenRefunded}.
    function _timeoutRefundWithoutPublish() internal {
        vm.warp(_predictionDeadline + MarketConfig.PUBLISH_TIMEOUT);
    }

    /// @dev Publishes results and commits a single-prediction distribution where every column of
    ///      the prediction reaches the tier. For a single-leaf tree, root = leaf and proof = [].
    function _publishAndCommitSinglePrediction(uint256 predictionId, uint8 tier) internal {
        _publishResults();
        bytes32 root = _merkleLeaf(predictionId, _columnsAt(tier, matchweek.predictionColumns(predictionId)));
        uint256[5] memory totalStakePerTier_;
        totalStakePerTier_[tier - MarketConfig.MIN_WINNING_TIER] = matchweek.predictionCost(predictionId);
        vm.prank(ADMIN);
        matchweek.commitDistribution(root, totalStakePerTier_);
    }

    /// @dev Merkle leaf for (predictionId, columnsPerTier), matching the contract's double-hash
    ///      encoding.
    function _merkleLeaf(uint256 predictionId, uint256[5] memory columnsPerTier) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(predictionId, columnsPerTier))));
    }

    /// @dev Column vector holding `columns` in a single tier and zero everywhere else.
    function _columnsAt(uint8 tier, uint256 columns) internal pure returns (uint256[5] memory columnsPerTier) {
        columnsPerTier[tier - MarketConfig.MIN_WINNING_TIER] = columns;
    }

    /// @dev Commits a two-leaf distribution from both predictions' column vectors, setting each
    ///      tier total to the columns the two contribute to it, priced at {UNIT_PRICE}.
    function _commitTwoPredictionDistribution(
        uint256 predictionA,
        uint256[5] memory columnsA,
        uint256 predictionB,
        uint256[5] memory columnsB
    ) internal {
        bytes32 leafA = _merkleLeaf(predictionA, columnsA);
        bytes32 leafB = _merkleLeaf(predictionB, columnsB);
        bytes32 root =
            leafA <= leafB ? keccak256(abi.encodePacked(leafA, leafB)) : keccak256(abi.encodePacked(leafB, leafA));

        uint256[5] memory totalStakePerTier_;
        for (uint256 i = 0; i < MarketConfig.TIER_COUNT; ++i) {
            totalStakePerTier_[i] = (columnsA[i] + columnsB[i]) * matchweek.UNIT_PRICE();
        }

        vm.prank(ADMIN);
        matchweek.commitDistribution(root, totalStakePerTier_);
    }

    /// @dev Returns the Merkle proofs for two predictions in a 2-leaf tree.
    function _buildTwoPredictionProofs(
        uint256 predictionA,
        uint256[5] memory columnsA,
        uint256 predictionB,
        uint256[5] memory columnsB
    ) internal pure returns (bytes32[] memory proofA, bytes32[] memory proofB) {
        bytes32 leafA = _merkleLeaf(predictionA, columnsA);
        bytes32 leafB = _merkleLeaf(predictionB, columnsB);
        proofA = new bytes32[](1);
        proofA[0] = leafB;
        proofB = new bytes32[](1);
        proofB[0] = leafA;
    }

    /// @dev Builds ten masks where match 2 is a double that excludes its actual outcome (away),
    ///      so both columns miss it and land in the same tier.
    function _buildMasksWithMissedDouble() internal pure returns (uint8[10] memory masks) {
        masks = _buildValidMasks();
        masks[2] = MASK_HOME | MASK_DRAW;
    }

    /// @dev Returns a zeroed [5] uint256 array (used for empty tier inputs).
    function _emptyUint5() internal pure returns (uint256[5] memory) {
        return [uint256(0), 0, 0, 0, 0];
    }
}
