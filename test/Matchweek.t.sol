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
        uint8[10] memory predictions = _buildValidPredictions();
        uint256 stake = matchweek.MIN_STAKE_AMOUNT();

        vm.expectEmit(true, true, true, true);
        emit Matchweek.PredictionSubmitted(0, ALICE, MATCHWEEK_ID, predictions, stake);
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(predictions, stake);

        assertEq(predictionId, 0);
        assertEq(matchweek.predictionCount(), 1);
        assertEq(matchweek.predictionOwner(0), ALICE);
        assertEq(matchweek.predictionHash(0), keccak256(abi.encode(predictions)));
        assertEq(matchweek.predictionStake(0), stake);
        assertEq(matchweek.totalStaked(), stake);
        assertEq(stablecoin.balanceOf(address(matchweek)), stake);
        assertEq(stablecoin.balanceOf(ALICE), 1_000_000_000 - stake);
    }

    function test_submitPrediction_sameAddressMultiplePredictions() public {
        uint8[10] memory predictions = _buildValidPredictions();
        uint256 stake = matchweek.MIN_STAKE_AMOUNT();

        vm.startPrank(ALICE);
        uint256 first = matchweek.submitPrediction(predictions, stake);
        uint256 second = matchweek.submitPrediction(predictions, stake);
        vm.stopPrank();

        assertEq(first, 0);
        assertEq(second, 1);
        assertEq(matchweek.predictionCount(), 2);
        assertEq(matchweek.predictionOwner(0), ALICE);
        assertEq(matchweek.predictionOwner(1), ALICE);
        assertEq(matchweek.predictionHash(0), keccak256(abi.encode(predictions)));
        assertEq(matchweek.predictionHash(1), keccak256(abi.encode(predictions)));
        assertEq(matchweek.totalStaked(), stake * 2);
        assertEq(stablecoin.balanceOf(address(matchweek)), stake * 2);
    }

    function test_submitPrediction_variableStake() public {
        uint256 stake = matchweek.MIN_STAKE_AMOUNT() * 3;

        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidPredictions(), stake);

        assertEq(matchweek.predictionStake(predictionId), stake);
        assertEq(matchweek.totalStaked(), stake);
        assertEq(stablecoin.balanceOf(address(matchweek)), stake);
        assertEq(stablecoin.balanceOf(ALICE), 1_000_000_000 - stake);
    }

    function testRevert_submitPrediction_invalidPredictionValue() public {
        uint8[10] memory predictions = _buildValidPredictions();
        predictions[3] = 3;
        uint256 stake = matchweek.MIN_STAKE_AMOUNT();

        vm.expectRevert(abi.encodeWithSelector(Matchweek.InvalidPredictionValue.selector, uint256(3), uint8(3)));
        vm.prank(ALICE);
        matchweek.submitPrediction(predictions, stake);
    }

    function testRevert_submitPrediction_stakeTooLow() public {
        uint256 tooLow = matchweek.MIN_STAKE_AMOUNT() - 1;

        vm.expectRevert(abi.encodeWithSelector(Matchweek.StakeTooLow.selector, tooLow, matchweek.MIN_STAKE_AMOUNT()));
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions(), tooLow);
    }

    function testRevert_submitPrediction_predictionWindowClosed() public {
        uint256 stake = matchweek.MIN_STAKE_AMOUNT();
        vm.warp(_predictionDeadline);

        vm.expectRevert(Matchweek.PredictionWindowClosed.selector);
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions(), stake);
    }

    function testRevert_submitPrediction_insufficientAllowance() public {
        uint256 stake = matchweek.MIN_STAKE_AMOUNT();
        vm.prank(ALICE);
        stablecoin.approve(address(matchweek), 0);

        vm.expectRevert();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions(), stake);
    }

    function testRevert_submitPrediction_insufficientBalance() public {
        uint256 stake = matchweek.MIN_STAKE_AMOUNT();
        address poor = address(0xB0B);
        vm.prank(poor);
        stablecoin.approve(address(matchweek), type(uint256).max);

        vm.expectRevert();
        vm.prank(poor);
        matchweek.submitPrediction(_buildValidPredictions(), stake);
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

    function test_publishResults_opensDisputeWindow() public {
        vm.warp(_predictionDeadline);
        vm.prank(ADMIN);
        matchweek.publishResults(_buildValidPredictions());

        assertEq(disputes.disputeDeadline(address(matchweek)), block.timestamp + DisputeConfig.DISPUTE_WINDOW);
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
    /// Apply Dispute Correction Tests
    ////

    function test_applyDisputeCorrection_overwritesOutcomes() public {
        vm.warp(_predictionDeadline);
        vm.prank(ADMIN);
        matchweek.publishResults(_buildValidPredictions());

        uint8[10] memory corrected = _buildValidPredictions();
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
        matchweek.publishResults(_buildValidPredictions());

        vm.expectRevert(Matchweek.NotDisputes.selector);
        vm.prank(ADMIN);
        matchweek.applyDisputeCorrection(_buildValidPredictions());
    }

    function testRevert_applyDisputeCorrection_invalidOutcome() public {
        vm.warp(_predictionDeadline);
        vm.prank(ADMIN);
        matchweek.publishResults(_buildValidPredictions());

        uint8[10] memory bad = _buildValidPredictions();
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
        matchweek.publishResults(_buildValidPredictions());

        // Dispute window still open — no warp past DisputeConfig.DISPUTE_WINDOW.
        vm.expectRevert(Matchweek.DisputeNotSettled.selector);
        vm.prank(ADMIN);
        matchweek.commitDistribution(bytes32(0), _emptyUint5());
    }

    function test_commitDistribution_prizeComputedOnChain() public {
        uint256 stake = matchweek.MIN_STAKE_AMOUNT();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions(), stake);

        _publishResults();

        // Alice is the only winner, in tier 6 (index 0, 7% of pool).
        bytes32 root = _merkleLeaf(0, 6);
        uint256[5] memory totalStakePerTier_;
        totalStakePerTier_[0] = stake;

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
        matchweek.commitDistribution(root, totalStakePerTier_);

        assertEq(matchweek.distributionCommitted(), true);
        assertEq(matchweek.claimsRoot(), root);
        assertEq(matchweek.prizePerTier(0), expectedPrize);
        assertEq(matchweek.unallocated(), expectedUnallocated);
        assertEq(matchweek.protocolFee(), expectedFee);
    }

    function test_commitDistribution_emptyTiersGoToUnallocated() public {
        uint256 stake = matchweek.MIN_STAKE_AMOUNT();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions(), stake);

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

    function test_commitDistribution_totalStakedFromVariableStakes() public {
        stablecoin.mint(BOB, 1_000_000_000);
        vm.prank(BOB);
        stablecoin.approve(address(matchweek), type(uint256).max);

        uint256 aliceStake = matchweek.MIN_STAKE_AMOUNT();
        uint256 bobStake = matchweek.MIN_STAKE_AMOUNT() * 4;
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions(), aliceStake);
        vm.prank(BOB);
        matchweek.submitPrediction(_buildValidPredictions(), bobStake);

        assertEq(matchweek.totalStaked(), aliceStake + bobStake);

        _publishResults();
        vm.prank(ADMIN);
        matchweek.commitDistribution(bytes32(0), _emptyUint5());

        uint256 expectedFee = (aliceStake + bobStake) * PrizeConfig.PROTOCOL_FEE_PCT / 100;
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
        uint256 stake = matchweek.MIN_STAKE_AMOUNT();
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidPredictions(), stake);

        _publishResults();

        // Single leaf: root = leaf, proof = [].
        // Tier 7 (index 1) = 10% of totalStaked.
        uint8 tier = 7;
        bytes32 leaf = _merkleLeaf(predictionId, tier);

        uint256[5] memory totalStakePerTier_;
        totalStakePerTier_[tier - PrizeConfig.MIN_WINNING_TIER] = stake;

        vm.prank(ADMIN);
        matchweek.commitDistribution(leaf, totalStakePerTier_);

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

        uint256 stake = matchweek.MIN_STAKE_AMOUNT();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions(), stake);
        vm.prank(BOB);
        matchweek.submitPrediction(_buildValidPredictions(), stake);

        _publishResults();
        _commitTwoPredictionDistribution(0, 1, 8, stake, stake);

        // Tier 8 (index 2) = 15% of totalStaked, split evenly since both staked the same amount.
        uint256 tierPool = matchweek.prizePerTier(8 - PrizeConfig.MIN_WINNING_TIER);
        uint256 tierTotalStake = matchweek.totalStakePerTier(8 - PrizeConfig.MIN_WINNING_TIER);

        (bytes32[] memory proofAlice, bytes32[] memory proofBob) = _buildTwoPredictionProofs(0, 1, 8);

        uint256 shareAlice = tierPool * stake / tierTotalStake;
        uint256 shareBob = tierPool * stake / tierTotalStake;

        vm.prank(ALICE);
        matchweek.claimPrize(0, 8, proofAlice);
        vm.prank(BOB);
        matchweek.claimPrize(1, 8, proofBob);

        assertEq(stablecoin.balanceOf(ALICE), 1_000_000_000 - stake + shareAlice);
        assertEq(stablecoin.balanceOf(BOB), 1_000_000_000 - stake + shareBob);
    }

    function test_claimPrize_proportionalSplit() public {
        stablecoin.mint(BOB, 1_000_000_000);
        vm.prank(BOB);
        stablecoin.approve(address(matchweek), type(uint256).max);

        uint256 aliceStake = matchweek.MIN_STAKE_AMOUNT();
        uint256 bobStake = matchweek.MIN_STAKE_AMOUNT() * 2;
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions(), aliceStake);
        vm.prank(BOB);
        matchweek.submitPrediction(_buildValidPredictions(), bobStake);

        _publishResults();
        _commitTwoPredictionDistribution(0, 1, 8, aliceStake, bobStake);

        uint256 tierPool = matchweek.prizePerTier(8 - PrizeConfig.MIN_WINNING_TIER);
        uint256 tierTotalStake = matchweek.totalStakePerTier(8 - PrizeConfig.MIN_WINNING_TIER);
        (bytes32[] memory proofAlice, bytes32[] memory proofBob) = _buildTwoPredictionProofs(0, 1, 8);

        uint256 expectedShareAlice = tierPool * aliceStake / tierTotalStake;
        uint256 expectedShareBob = tierPool * bobStake / tierTotalStake;

        vm.prank(ALICE);
        matchweek.claimPrize(0, 8, proofAlice);
        vm.prank(BOB);
        matchweek.claimPrize(1, 8, proofBob);

        assertEq(stablecoin.balanceOf(ALICE), 1_000_000_000 - aliceStake + expectedShareAlice);
        assertEq(stablecoin.balanceOf(BOB), 1_000_000_000 - bobStake + expectedShareBob);
        // Bob staked twice as much as Alice, so his share must be exactly twice hers.
        assertEq(expectedShareBob, expectedShareAlice * 2);
    }

    // Alice is in the tree at tier 7 but tries to claim tier 10 — wrong proof, fails at Merkle.
    function testRevert_claimPrize_wrongTierProof() public {
        uint256 stake = matchweek.MIN_STAKE_AMOUNT();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions(), stake);

        _publishResults();

        uint8 aliceTier = 7;
        bytes32 root = _merkleLeaf(0, aliceTier);

        uint256[5] memory totalStakePerTier_;
        totalStakePerTier_[aliceTier - 6] = stake;

        vm.prank(ADMIN);
        matchweek.commitDistribution(root, totalStakePerTier_);

        vm.expectRevert(abi.encodeWithSelector(Matchweek.InvalidProof.selector, uint256(0), uint8(10)));
        vm.prank(ALICE);
        matchweek.claimPrize(0, 10, new bytes32[](0));
    }

    // Alice is in the tree at tier 7 but admin set totalStakePerTier[7-6] = 0 by mistake
    // → contract computes prizePerTier[7-6] = 0 → EmptyTierPool.
    function testRevert_claimPrize_emptyTierPool() public {
        uint256 stake = matchweek.MIN_STAKE_AMOUNT();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions(), stake);

        _publishResults();

        uint8 tier = 7;
        bytes32 root = _merkleLeaf(0, tier);

        // Winning stake is 0 → contract sets prizePerTier[tier-6] = 0 → EmptyTierPool on claim.
        vm.prank(ADMIN);
        matchweek.commitDistribution(root, _emptyUint5());

        vm.expectRevert(abi.encodeWithSelector(Matchweek.EmptyTierPool.selector, tier));
        vm.prank(ALICE);
        matchweek.claimPrize(0, tier, new bytes32[](0));
    }

    function testRevert_claimPrize_distributionNotCommitted() public {
        uint256 stake = matchweek.MIN_STAKE_AMOUNT();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions(), stake);

        vm.expectRevert(Matchweek.DistributionNotCommitted.selector);
        vm.prank(ALICE);
        matchweek.claimPrize(0, 7, new bytes32[](0));
    }

    function testRevert_claimPrize_notPredictionOwner() public {
        uint256 stake = matchweek.MIN_STAKE_AMOUNT();
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidPredictions(), stake);

        _publishAndCommitSinglePrediction(predictionId, 7);

        vm.expectRevert(abi.encodeWithSelector(Matchweek.NotPredictionOwner.selector, predictionId));
        vm.prank(address(0xB0B));
        matchweek.claimPrize(predictionId, 7, new bytes32[](0));
    }

    function testRevert_claimPrize_alreadyClaimed() public {
        uint256 stake = matchweek.MIN_STAKE_AMOUNT();
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidPredictions(), stake);

        _publishAndCommitSinglePrediction(predictionId, 7);

        vm.prank(ALICE);
        matchweek.claimPrize(predictionId, 7, new bytes32[](0));

        vm.expectRevert(abi.encodeWithSelector(Matchweek.AlreadyClaimed.selector, predictionId));
        vm.prank(ALICE);
        matchweek.claimPrize(predictionId, 7, new bytes32[](0));
    }

    function testRevert_claimPrize_invalidTier_tooLow() public {
        uint256 stake = matchweek.MIN_STAKE_AMOUNT();
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidPredictions(), stake);

        _publishAndCommitSinglePrediction(predictionId, 7);

        vm.expectRevert(abi.encodeWithSelector(Matchweek.InvalidTier.selector, uint8(5)));
        vm.prank(ALICE);
        matchweek.claimPrize(predictionId, 5, new bytes32[](0));
    }

    function testRevert_claimPrize_invalidTier_tooHigh() public {
        uint256 stake = matchweek.MIN_STAKE_AMOUNT();
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidPredictions(), stake);

        _publishAndCommitSinglePrediction(predictionId, 7);

        vm.expectRevert(abi.encodeWithSelector(Matchweek.InvalidTier.selector, uint8(11)));
        vm.prank(ALICE);
        matchweek.claimPrize(predictionId, 11, new bytes32[](0));
    }

    function testRevert_claimPrize_invalidProof() public {
        uint256 stake = matchweek.MIN_STAKE_AMOUNT();
        vm.prank(ALICE);
        uint256 predictionId = matchweek.submitPrediction(_buildValidPredictions(), stake);

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
        uint256 stake = matchweek.MIN_STAKE_AMOUNT();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions(), stake);

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
        uint256 stake = matchweek.MIN_STAKE_AMOUNT();

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
        uint256 predictionId = matchweek2.submitPrediction(_buildValidPredictions(), stake);

        uint256 fee = stake * PrizeConfig.PROTOCOL_FEE_PCT / 100;

        // First matchweek: no winners, its stake net of the fee seeds the carry pool.
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions(), stake);
        _publishResults();
        vm.prank(ADMIN);
        matchweek.commitDistribution(bytes32(0), _emptyUint5());
        assertEq(carryPool.carriedBalance(), stake - fee);

        // Second matchweek: Bob hits a perfect ten and should receive the carried balance on
        // top of the normal tier-10 prize.
        vm.prank(ADMIN);
        matchweek2.publishResults(_buildValidPredictions());
        vm.warp(block.timestamp + DisputeConfig.DISPUTE_WINDOW);

        uint8 tier = 10;
        bytes32 root = _merkleLeaf(predictionId, tier);
        uint256[5] memory totalStakePerTier_;
        totalStakePerTier_[tier - PrizeConfig.MIN_WINNING_TIER] = stake;

        vm.prank(ADMIN);
        matchweek2.commitDistribution(root, totalStakePerTier_);

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
        uint256 stake = matchweek.MIN_STAKE_AMOUNT();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions(), stake);

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
        uint256 stake = matchweek.MIN_STAKE_AMOUNT();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions(), stake);

        _publishResults();

        vm.prank(ADMIN);
        matchweek.commitDistribution(bytes32(0), _emptyUint5());

        uint256 expectedFee = stake * PrizeConfig.PROTOCOL_FEE_PCT / 100;
        assertEq(carryPool.carriedBalance(), stake - expectedFee);
        assertEq(matchweek.unallocated(), stake - expectedFee);
    }

    /// @dev Every staked unit must end up in exactly one of: tier prizes, carry pool, treasury.
    function test_commitDistribution_reconcilesToTotalStaked() public {
        uint256 stake = matchweek.MIN_STAKE_AMOUNT();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions(), stake);
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions(), stake);
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions(), stake);

        _publishResults();

        // Winners in tiers 6 and 9, leaving tiers 7, 8 and 10 empty.
        uint256[5] memory totalStakePerTier_;
        totalStakePerTier_[0] = stake;
        totalStakePerTier_[3] = stake;

        vm.prank(ADMIN);
        matchweek.commitDistribution(bytes32(0), totalStakePerTier_);

        uint256 totalStakedExpected = 3 * stake;
        uint256 totalPrizes;
        for (uint256 i = 0; i < PrizeConfig.TIER_COUNT; ++i) {
            totalPrizes += matchweek.prizePerTier(i);
        }

        assertEq(totalPrizes + carryPool.carriedBalance() + treasury.collectedBalance(), totalStakedExpected);
        assertEq(stablecoin.balanceOf(address(matchweek)), totalPrizes);
    }

    /// @dev Integer-division dust must fall to the carry pool, never inflate the fee.
    function test_commitDistribution_feeNeverExceedsItsPercentage() public {
        uint256 stake = matchweek.MIN_STAKE_AMOUNT();
        vm.prank(ALICE);
        matchweek.submitPrediction(_buildValidPredictions(), stake);

        _publishResults();

        vm.prank(ADMIN);
        matchweek.commitDistribution(bytes32(0), _emptyUint5());

        uint256 totalStakedExpected = matchweek.totalStaked();
        assertLe(matchweek.protocolFee() * 100, totalStakedExpected * PrizeConfig.PROTOCOL_FEE_PCT);
    }

    ////
    /// Test Helpers
    ////

    /// @dev Warps to the prediction deadline, has the admin publish results, then warps past the
    ///      dispute window so the matchweek is settled and {commitDistribution} is unblocked.
    function _publishResults() internal {
        vm.warp(_predictionDeadline);
        vm.prank(ADMIN);
        matchweek.publishResults(_buildValidPredictions());
        vm.warp(block.timestamp + DisputeConfig.DISPUTE_WINDOW);
    }

    /// @dev Publishes results and commits a single-prediction distribution for the given
    ///      predictionId/tier, using that prediction's actual stake as the tier total. For a
    ///      single-leaf tree, root = leaf and proof = [].
    function _publishAndCommitSinglePrediction(uint256 predictionId, uint8 tier) internal {
        _publishResults();
        bytes32 root = _merkleLeaf(predictionId, tier);
        uint256[5] memory totalStakePerTier_;
        totalStakePerTier_[tier - PrizeConfig.MIN_WINNING_TIER] = matchweek.predictionStake(predictionId);
        vm.prank(ADMIN);
        matchweek.commitDistribution(root, totalStakePerTier_);
    }

    /// @dev Merkle leaf for (predictionId, tier), matching the contract's double-hash encoding.
    function _merkleLeaf(uint256 predictionId, uint8 tier) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(predictionId, tier))));
    }

    /// @dev Commits a distribution where two predictions (predictionA, predictionB) are both in
    ///      the same tier, with the tier total set to the sum of their individual stakes.
    function _commitTwoPredictionDistribution(
        uint256 predictionA,
        uint256 predictionB,
        uint8 tier,
        uint256 stakeA,
        uint256 stakeB
    ) internal {
        bytes32 leafA = _merkleLeaf(predictionA, tier);
        bytes32 leafB = _merkleLeaf(predictionB, tier);
        bytes32 root =
            leafA <= leafB ? keccak256(abi.encodePacked(leafA, leafB)) : keccak256(abi.encodePacked(leafB, leafA));

        uint256[5] memory totalStakePerTier_;
        totalStakePerTier_[tier - PrizeConfig.MIN_WINNING_TIER] = stakeA + stakeB;

        vm.prank(ADMIN);
        matchweek.commitDistribution(root, totalStakePerTier_);
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
