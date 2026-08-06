// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {CarryPool} from "../src/CarryPool.sol";
import {Matchweek} from "../src/Matchweek.sol";
import {PrizeConfig} from "../src/PrizeConfig.sol";
import {Treasury} from "../src/Treasury.sol";

contract MatchweekTest is Test {
    uint32 constant MATCHWEEK_ID = 1;
    address constant ADMIN = address(0xAD);
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);

    uint40 private _predictionDeadline;
    address private _implementation;
    Matchweek public matchweek;
    ERC20Mock public stablecoin;
    CarryPool public carryPool;
    Treasury public treasury;

    function setUp() public {
        _predictionDeadline = uint40(block.timestamp + 1 days);
        stablecoin = new ERC20Mock();
        carryPool = new CarryPool(ADMIN, stablecoin);
        treasury = new Treasury(ADMIN, stablecoin);
        _implementation = address(new Matchweek(stablecoin, carryPool, treasury));
        matchweek = _deployClone();
        matchweek.initialize(MATCHWEEK_ID, _predictionDeadline, _buildValidMatches(), ADMIN);

        // This test contract stands in for PitchMkt, the only account allowed to
        // register matchweeks with the carry pool and the treasury.
        vm.prank(ADMIN);
        carryPool.setFactory(address(this));
        carryPool.registerMatchweek(address(matchweek));
        vm.prank(ADMIN);
        treasury.setFactory(address(this));
        treasury.registerMatchweek(address(matchweek));

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
        new Matchweek(ERC20Mock(address(0)), carryPool, treasury);
    }

    function testRevert_carryPoolIsZeroAddress() public {
        vm.expectRevert(Matchweek.InvalidCarryPool.selector);
        new Matchweek(stablecoin, CarryPool(address(0)), treasury);
    }

    function testRevert_treasuryIsZeroAddress() public {
        vm.expectRevert(Matchweek.InvalidTreasury.selector);
        new Matchweek(stablecoin, carryPool, Treasury(payable(address(0))));
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
        uint8[10] memory predictions = _buildValidPredictions();
        uint256 stake = matchweek.STAKE_AMOUNT();

        vm.expectEmit(true, true, true, true);
        emit Matchweek.PredictionSubmitted(0, ALICE, MATCHWEEK_ID, predictions);
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(predictions);

        assertEq(predictionId, 0);
        assertEq(matchweek.predictionCount(), 1);
        assertEq(matchweek.predictionOwner(0), ALICE);
        assertEq(matchweek.predictionHash(0), keccak256(abi.encode(predictions)));
        assertEq(stablecoin.balanceOf(address(matchweek)), stake);
        assertEq(stablecoin.balanceOf(ALICE), 1_000_000_000 - stake);
    }

    function test_submitPrediction_sameAddressMultiplePredictions() public {
        uint8[10] memory predictions = _buildValidPredictions();
        uint256 stake = matchweek.STAKE_AMOUNT();

        vm.startPrank(ALICE);
        uint256 first = matchweek.submitPrediction(predictions);
        uint256 second = matchweek.submitPrediction(predictions);
        vm.stopPrank();

        assertEq(first, 0);
        assertEq(second, 1);
        assertEq(matchweek.predictionCount(), 2);
        assertEq(matchweek.predictionOwner(0), ALICE);
        assertEq(matchweek.predictionOwner(1), ALICE);
        assertEq(matchweek.predictionHash(0), keccak256(abi.encode(predictions)));
        assertEq(matchweek.predictionHash(1), keccak256(abi.encode(predictions)));
        assertEq(stablecoin.balanceOf(address(matchweek)), stake * 2);
    }

    function testRevert_submitPrediction_invalidPredictionValue() public {
        uint8[10] memory predictions = _buildValidPredictions();
        predictions[3] = 3;

        vm.expectRevert(abi.encodeWithSelector(Matchweek.InvalidPredictionValue.selector, uint256(3), uint8(3)));
        vm.prank(ALICE);
        matchweek.submitPrediction(predictions);
    }

    function testRevert_submitPrediction_predictionWindowClosed() public {
        vm.warp(_predictionDeadline);

        vm.expectRevert(Matchweek.PredictionWindowClosed.selector);
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions());
    }

    function testRevert_submitPrediction_insufficientAllowance() public {
        vm.prank(ALICE);
        stablecoin.approve(address(matchweek), 0);

        vm.expectRevert();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions());
    }

    function testRevert_submitPrediction_insufficientBalance() public {
        address poor = address(0xB0B);
        vm.prank(poor);
        stablecoin.approve(address(matchweek), type(uint256).max);

        vm.expectRevert();
        vm.prank(poor);
        matchweek.submitPrediction(_buildValidPredictions());
    }

    /// @dev Deploys a fresh EIP-1167 minimal proxy clone of the implementation, mirroring how
    ///      PitchMkt creates instances.
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

    ////
    /// Publish Results Tests
    ////

    function test_publishResults() public {
        uint8[10] memory outcomes = _buildValidPredictions();

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

    function testRevert_publishResults_deadlineNotPassed() public {
        vm.expectRevert(Matchweek.DeadlineNotPassed.selector);
        vm.prank(ADMIN);
        matchweek.publishResults(_buildValidPredictions());
    }

    function testRevert_publishResults_alreadyPublished() public {
        vm.warp(_predictionDeadline);
        vm.prank(ADMIN);
        matchweek.publishResults(_buildValidPredictions());

        vm.expectRevert(Matchweek.ResultsAlreadyPublished.selector);
        vm.prank(ADMIN);
        matchweek.publishResults(_buildValidPredictions());
    }

    function testRevert_publishResults_invalidOutcome() public {
        uint8[10] memory bad = _buildValidPredictions();
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
        matchweek.publishResults(_buildValidPredictions());
    }

    ////
    /// Commit Distribution Tests
    ////

    function test_commitDistribution_prizeComputedOnChain() public {
        uint256 stake = matchweek.STAKE_AMOUNT();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions());

        _publishResults();

        // Alice is the only winner, in tier 6 (index 0, 7% of pool).
        bytes32 root = _merkleLeaf(0, 6);
        uint256[5] memory winners;
        winners[0] = 1;

        // prizePerTier[0] = stake * TIER6_PRIZE_PCT / 100, fee = stake * PROTOCOL_FEE_PCT / 100,
        // unallocated = remainder after both.
        uint256 expectedPrize = stake * PrizeConfig.TIER6_PRIZE_PCT / 100;
        uint256 expectedFee = stake * PrizeConfig.PROTOCOL_FEE_PCT / 100;
        uint256 expectedUnallocated = stake - expectedPrize - expectedFee;

        uint256[5] memory expectedPrizes;
        expectedPrizes[0] = expectedPrize;

        vm.expectEmit(true, false, false, true);
        emit Matchweek.DistributionCommitted(MATCHWEEK_ID, root, expectedPrizes, expectedUnallocated, expectedFee);
        vm.prank(ADMIN);
        matchweek.commitDistribution(root, winners);

        assertEq(matchweek.distributionCommitted(), true);
        assertEq(matchweek.claimsRoot(), root);
        assertEq(matchweek.prizePerTier(0), expectedPrize);
        assertEq(matchweek.unallocated(), expectedUnallocated);
        assertEq(matchweek.protocolFee(), expectedFee);
    }

    function test_commitDistribution_emptyTiersGoToUnallocated() public {
        uint256 stake = matchweek.STAKE_AMOUNT();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions());

        _publishResults();

        // No winners in any tier → everything except the protocol fee goes to unallocated.
        vm.prank(ADMIN);
        matchweek.commitDistribution(bytes32(0), _emptyUint5());

        uint256 expectedFee = stake * PrizeConfig.PROTOCOL_FEE_PCT / 100;
        assertEq(matchweek.unallocated(), stake - expectedFee);
        assertEq(matchweek.protocolFee(), expectedFee);
        for (uint256 i = 0; i < PrizeConfig.TIER_COUNT; ++i) {
            assertEq(matchweek.prizePerTier(i), 0);
        }
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
        uint256 stake = matchweek.STAKE_AMOUNT();
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidPredictions());

        _publishResults();

        // Single leaf: root = leaf, proof = [].
        // Tier 7 (index 1) = 10% of totalStaked.
        uint8 tier = 7;
        bytes32 leaf = _merkleLeaf(predictionId, tier);

        uint256[5] memory winners;
        winners[tier - PrizeConfig.MIN_WINNING_TIER] = 1;

        vm.prank(ADMIN);
        matchweek.commitDistribution(leaf, winners);

        uint256 expectedShare = stake * PrizeConfig.TIER7_PRIZE_PCT / 100; // tier 7 = index 1
        uint256 balanceBefore = stablecoin.balanceOf(ALICE);

        vm.expectEmit(true, true, true, true);
        emit Matchweek.PrizeClaimed(matchweek.matchweekId(), predictionId, ALICE, expectedShare);
        vm.prank(ALICE);
        matchweek.claimPrize(predictionId, tier, new bytes32[](0));

        assertEq(stablecoin.balanceOf(ALICE), balanceBefore + expectedShare);
        assertEq(matchweek.claimed(predictionId), true);
    }

    function test_claimPrize_multipleWinners_evenSplit() public {
        stablecoin.mint(BOB, 1_000_000_000);
        vm.prank(BOB);
        stablecoin.approve(address(matchweek), type(uint256).max);

        uint256 stake = matchweek.STAKE_AMOUNT();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions());
        vm.prank(BOB);
        matchweek.submitPrediction(_buildValidPredictions());

        _publishResults();
        _commitTwoPredictionDistribution(0, 1, 8);

        // Tier 8 (index 2) = 15% of totalStaked, split evenly between Alice and Bob.
        uint256 tierPool = matchweek.prizePerTier(8 - PrizeConfig.MIN_WINNING_TIER);
        uint256 winnersCount = matchweek.winnersCountPerTier(8 - PrizeConfig.MIN_WINNING_TIER);

        (bytes32[] memory proofAlice, bytes32[] memory proofBob) = _buildTwoPredictionProofs(0, 1, 8);

        uint256 shareAlice = tierPool / winnersCount;
        uint256 shareBob = tierPool / winnersCount;

        vm.prank(ALICE);
        matchweek.claimPrize(0, 8, proofAlice);
        vm.prank(BOB);
        matchweek.claimPrize(1, 8, proofBob);

        assertEq(stablecoin.balanceOf(ALICE), 1_000_000_000 - stake + shareAlice);
        assertEq(stablecoin.balanceOf(BOB), 1_000_000_000 - stake + shareBob);
    }

    // Alice is in the tree at tier 7 but tries to claim tier 10 — wrong proof, fails at Merkle.
    function testRevert_claimPrize_wrongTierProof() public {
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions());

        _publishResults();

        uint8 aliceTier = 7;
        bytes32 root = _merkleLeaf(0, aliceTier);

        uint256[5] memory winners;
        winners[aliceTier - 6] = 1;

        vm.prank(ADMIN);
        matchweek.commitDistribution(root, winners);

        vm.expectRevert(abi.encodeWithSelector(Matchweek.InvalidProof.selector, uint256(0), uint8(10)));
        vm.prank(ALICE);
        matchweek.claimPrize(0, 10, new bytes32[](0));
    }

    // Alice is in the tree at tier 7 but admin set winnersCountPerTier[7-6] = 0 by mistake
    // → contract computes prizePerTier[7-6] = 0 → EmptyTierPool.
    function testRevert_claimPrize_emptyTierPool() public {
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions());

        _publishResults();

        uint8 tier = 7;
        bytes32 root = _merkleLeaf(0, tier);

        // Winners count is 0 → contract sets prizePerTier[tier-6] = 0 → EmptyTierPool on claim.
        vm.prank(ADMIN);
        matchweek.commitDistribution(root, _emptyUint5());

        vm.expectRevert(abi.encodeWithSelector(Matchweek.EmptyTierPool.selector, tier));
        vm.prank(ALICE);
        matchweek.claimPrize(0, tier, new bytes32[](0));
    }

    function testRevert_claimPrize_distributionNotCommitted() public {
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions());

        vm.expectRevert(Matchweek.DistributionNotCommitted.selector);
        vm.prank(ALICE);
        matchweek.claimPrize(0, 7, new bytes32[](0));
    }

    function testRevert_claimPrize_notPredictionOwner() public {
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidPredictions());

        _publishAndCommitSinglePrediction(predictionId, 7);

        vm.expectRevert(abi.encodeWithSelector(Matchweek.NotPredictionOwner.selector, predictionId));
        vm.prank(address(0xB0B));
        matchweek.claimPrize(predictionId, 7, new bytes32[](0));
    }

    function testRevert_claimPrize_alreadyClaimed() public {
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidPredictions());

        _publishAndCommitSinglePrediction(predictionId, 7);

        vm.prank(ALICE);
        matchweek.claimPrize(predictionId, 7, new bytes32[](0));

        vm.expectRevert(abi.encodeWithSelector(Matchweek.AlreadyClaimed.selector, predictionId));
        vm.prank(ALICE);
        matchweek.claimPrize(predictionId, 7, new bytes32[](0));
    }

    function testRevert_claimPrize_invalidTier_tooLow() public {
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidPredictions());

        _publishAndCommitSinglePrediction(predictionId, 7);

        vm.expectRevert(abi.encodeWithSelector(Matchweek.InvalidTier.selector, uint8(5)));
        vm.prank(ALICE);
        matchweek.claimPrize(predictionId, 5, new bytes32[](0));
    }

    function testRevert_claimPrize_invalidTier_tooHigh() public {
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidPredictions());

        _publishAndCommitSinglePrediction(predictionId, 7);

        vm.expectRevert(abi.encodeWithSelector(Matchweek.InvalidTier.selector, uint8(11)));
        vm.prank(ALICE);
        matchweek.claimPrize(predictionId, 11, new bytes32[](0));
    }

    function testRevert_claimPrize_invalidProof() public {
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidPredictions());

        _publishAndCommitSinglePrediction(predictionId, 7);

        // Correct tier is 7 but claiming tier 8
        vm.expectRevert(abi.encodeWithSelector(Matchweek.InvalidProof.selector, predictionId, uint8(8)));
        vm.prank(ALICE);
        matchweek.claimPrize(predictionId, 8, new bytes32[](0));
    }

    ////
    /// Carry Pool Tests
    ////

    function test_commitDistribution_unallocatedFundsCarryPool() public {
        uint256 stake = matchweek.STAKE_AMOUNT();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions());

        _publishResults();

        // No winners in any tier → everything except the protocol fee moves to the carry pool.
        vm.prank(ADMIN);
        matchweek.commitDistribution(bytes32(0), _emptyUint5());

        uint256 expectedCarry = stake - stake * PrizeConfig.PROTOCOL_FEE_PCT / 100;
        assertEq(carryPool.carriedBalance(), expectedCarry);
        assertEq(stablecoin.balanceOf(address(carryPool)), expectedCarry);
        assertEq(stablecoin.balanceOf(address(matchweek)), 0);
    }

    function test_commitDistribution_perfectTenReleasesCarryPool() public {
        uint256 stake = matchweek.STAKE_AMOUNT();

        // Deploy the second matchweek and have Bob enter before time is warped forward, since
        // {initialize} requires a future predictionDeadline.
        Matchweek matchweek2 = _deployClone();
        matchweek2.initialize(MATCHWEEK_ID + 1, _predictionDeadline, _buildValidMatches(), ADMIN);
        carryPool.registerMatchweek(address(matchweek2));
        treasury.registerMatchweek(address(matchweek2));

        address BOB = address(0xB0B);
        stablecoin.mint(BOB, 1_000_000_000);
        vm.prank(BOB);
        stablecoin.approve(address(matchweek2), type(uint256).max);
        vm.prank(BOB);
        uint256 predictionId = matchweek2.submitPrediction(_buildValidPredictions());

        uint256 fee = stake * PrizeConfig.PROTOCOL_FEE_PCT / 100;

        // First matchweek: no winners, its stake net of the fee seeds the carry pool.
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions());
        _publishResults();
        vm.prank(ADMIN);
        matchweek.commitDistribution(bytes32(0), _emptyUint5());
        assertEq(carryPool.carriedBalance(), stake - fee);

        // Second matchweek: Bob hits a perfect ten and should receive the carried balance on
        // top of the normal tier-10 prize.
        vm.prank(ADMIN);
        matchweek2.publishResults(_buildValidPredictions());

        uint8 tier = 10;
        bytes32 root = _merkleLeaf(predictionId, tier);
        uint256[5] memory winners;
        winners[tier - PrizeConfig.MIN_WINNING_TIER] = 1;

        vm.prank(ADMIN);
        matchweek2.commitDistribution(root, winners);

        uint256 tier10Prize = stake * PrizeConfig.TIER10_PRIZE_PCT / 100;
        uint256 expectedPrizePerTier10 = tier10Prize + (stake - fee);
        assertEq(matchweek2.prizePerTier(PrizeConfig.TIER_COUNT - 1), expectedPrizePerTier10);

        // matchweek2's own leftover, net of its fee, reseeds the carry pool for the next cycle.
        uint256 expectedUnallocated2 = stake - tier10Prize - fee;
        assertEq(carryPool.carriedBalance(), expectedUnallocated2);

        uint256 balanceBefore = stablecoin.balanceOf(BOB);
        vm.prank(BOB);
        matchweek2.claimPrize(predictionId, tier, new bytes32[](0));
        assertEq(stablecoin.balanceOf(BOB), balanceBefore + expectedPrizePerTier10);
    }

    ////
    /// Protocol Fee Tests
    ////

    function test_commitDistribution_feeGoesToTreasury() public {
        uint256 stake = matchweek.STAKE_AMOUNT();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions());

        _publishResults();

        vm.prank(ADMIN);
        matchweek.commitDistribution(bytes32(0), _emptyUint5());

        uint256 expectedFee = stake * PrizeConfig.PROTOCOL_FEE_PCT / 100;
        assertEq(treasury.collectedBalance(), expectedFee);
        assertEq(treasury.collectedByMatchweek(MATCHWEEK_ID), expectedFee);
        assertEq(stablecoin.balanceOf(address(treasury)), expectedFee);
    }

    /// @dev The whitepaper requires the carry pool to hold unawarded prize money only, never fees.
    function test_commitDistribution_carryPoolExcludesFee() public {
        uint256 stake = matchweek.STAKE_AMOUNT();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions());

        _publishResults();

        vm.prank(ADMIN);
        matchweek.commitDistribution(bytes32(0), _emptyUint5());

        uint256 expectedFee = stake * PrizeConfig.PROTOCOL_FEE_PCT / 100;
        assertEq(carryPool.carriedBalance(), stake - expectedFee);
        assertEq(matchweek.unallocated(), stake - expectedFee);
    }

    /// @dev Every staked unit must end up in exactly one of: tier prizes, carry pool, treasury.
    function test_commitDistribution_reconcilesToTotalStaked() public {
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions());
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions());
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions());

        _publishResults();

        // Winners in tiers 6 and 9, leaving tiers 7, 8 and 10 empty.
        uint256[5] memory winners;
        winners[0] = 1;
        winners[3] = 1;

        vm.prank(ADMIN);
        matchweek.commitDistribution(bytes32(0), winners);

        uint256 totalStaked = 3 * matchweek.STAKE_AMOUNT();
        uint256 totalPrizes;
        for (uint256 i = 0; i < PrizeConfig.TIER_COUNT; ++i) {
            totalPrizes += matchweek.prizePerTier(i);
        }

        assertEq(totalPrizes + carryPool.carriedBalance() + treasury.collectedBalance(), totalStaked);
        assertEq(stablecoin.balanceOf(address(matchweek)), totalPrizes);
    }

    /// @dev Integer-division dust must fall to the carry pool, never inflate the fee.
    function test_commitDistribution_feeNeverExceedsItsPercentage() public {
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions());

        _publishResults();

        vm.prank(ADMIN);
        matchweek.commitDistribution(bytes32(0), _emptyUint5());

        uint256 totalStaked = matchweek.STAKE_AMOUNT();
        assertLe(matchweek.protocolFee() * 100, totalStaked * PrizeConfig.PROTOCOL_FEE_PCT);
    }

    ////
    /// Test Helpers
    ////

    /// @dev Warps to the prediction deadline and has the admin publish results.
    function _publishResults() internal {
        vm.warp(_predictionDeadline);
        vm.prank(ADMIN);
        matchweek.publishResults(_buildValidPredictions());
    }

    /// @dev Publishes results and commits a single-prediction distribution for the given predictionId/tier.
    ///      For a single-leaf tree, root = leaf and proof = [].
    function _publishAndCommitSinglePrediction(uint256 predictionId, uint8 tier) internal {
        _publishResults();
        bytes32 root = _merkleLeaf(predictionId, tier);
        uint256[5] memory winners;
        winners[tier - PrizeConfig.MIN_WINNING_TIER] = 1;
        vm.prank(ADMIN);
        matchweek.commitDistribution(root, winners);
    }

    /// @dev Merkle leaf for (predictionId, tier), matching the contract's double-hash encoding.
    function _merkleLeaf(uint256 predictionId, uint8 tier) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(predictionId, tier))));
    }

    /// @dev Commits a distribution where two predictions (predictionA, predictionB) are both in the same tier.
    function _commitTwoPredictionDistribution(uint256 predictionA, uint256 predictionB, uint8 tier) internal {
        bytes32 leafA = _merkleLeaf(predictionA, tier);
        bytes32 leafB = _merkleLeaf(predictionB, tier);
        bytes32 root =
            leafA <= leafB ? keccak256(abi.encodePacked(leafA, leafB)) : keccak256(abi.encodePacked(leafB, leafA));

        uint256[5] memory winners;
        winners[tier - PrizeConfig.MIN_WINNING_TIER] = 2;

        vm.prank(ADMIN);
        matchweek.commitDistribution(root, winners);
    }

    /// @dev Returns the Merkle proofs for two predictions in a 2-leaf tree (same tier).
    function _buildTwoPredictionProofs(uint256 predictionA, uint256 predictionB, uint8 tier)
        internal
        pure
        returns (bytes32[] memory proofA, bytes32[] memory proofB)
    {
        bytes32 leafA = _merkleLeaf(predictionA, tier);
        bytes32 leafB = _merkleLeaf(predictionB, tier);
        proofA = new bytes32[](1);
        proofA[0] = leafB;
        proofB = new bytes32[](1);
        proofB[0] = leafA;
    }

    /// @dev Returns a zeroed [5] uint256 array (used for empty tier inputs).
    function _emptyUint5() internal pure returns (uint256[5] memory) {
        return [uint256(0), 0, 0, 0, 0];
    }
}
