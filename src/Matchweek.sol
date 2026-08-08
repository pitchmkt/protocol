// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CarryPool} from "./CarryPool.sol";
import {Disputes} from "./Disputes.sol";
import {PrizeConfig} from "./PrizeConfig.sol";
import {Treasury} from "./Treasury.sol";

/// @title Matchweek
/// @author PitchMkt
/// @notice Stores the ten matches for a single PitchMkt matchweek and accepts
///         predictions until the prediction deadline.
contract Matchweek is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Possible outcomes for a single match.
    enum Outcome {
        Home, // 0 — home team wins
        Draw, // 1 — match ends in a draw
        Away // 2 — away team wins
    }

    /// @dev homeTeam / awayTeam are bytes32 (e.g. keccak256 of a team slug).
    struct Match {
        bytes32 homeTeam;
        bytes32 awayTeam;
    }

    /// @notice Minimum stake accepted per prediction: 5 USDC (6 decimals).
    /// @dev Stake is variable above this floor; each winner's prize share is proportional to
    ///      what it staked (see {claimPrize}), not split evenly by winner count.
    uint256 public constant MIN_STAKE_AMOUNT = 5_000_000;

    /// @notice Number of matches per matchweek.
    uint256 public constant MATCH_COUNT = 10;

    /// @dev Upper bound for outcome validation, derived from the {Outcome} enum.
    uint8 private constant MAX_OUTCOME = uint8(type(Outcome).max);

    /// @dev Index into the tier arrays for the perfect-ten tier (tier 10 → index 4).
    uint256 private constant TIER10_INDEX = PrizeConfig.TIER_COUNT - 1;

    /// @notice ERC20 token accepted as stake for predictions, shared by every matchweek clone.
    IERC20 public immutable STABLECOIN;

    /// @notice Standalone pool that accumulates unallocated stake across matchweeks and pays
    ///         out to a perfect-ten winner, shared by every matchweek clone.
    CarryPool public immutable CARRY_POOL;

    /// @notice Standalone treasury that accumulates the protocol fee retained from every
    ///         matchweek, shared by every matchweek clone.
    Treasury public immutable TREASURY;

    /// @notice Standalone contract that runs the post-publication dispute window and resolves
    ///         challenges against published results, shared by every matchweek clone.
    Disputes public immutable DISPUTES;

    uint32 public matchweekId;
    uint40 public predictionDeadline;
    Match[10] private _matches;
    bool private _initialized;
    uint256 public predictionCount;
    mapping(uint256 predictionId => address user) public predictionOwner;
    mapping(uint256 predictionId => bytes32 hash) public predictionHash;
    mapping(uint256 predictionId => uint256 stake) public predictionStake;
    /// @notice Sum of every prediction's stake in this matchweek.
    uint256 public totalStaked;

    uint8[10] private _outcomes;
    bool public resultsPublished;

    bytes32 public claimsRoot;
    /// @dev Tiers 6–10 are stored at indices 0–4 (index = tier - {PrizeConfig.MIN_WINNING_TIER}).
    ///      totalStakePerTier is the denominator for each winning prediction's proportional share.
    uint256[5] public totalStakePerTier;
    uint256[5] public prizePerTier;
    /// @dev Transferred to {CARRY_POOL} at the end of {commitDistribution}.
    uint256 public unallocated;
    /// @dev Transferred to {TREASURY} at the end of {commitDistribution}.
    uint256 public protocolFee;
    bool public distributionCommitted;

    mapping(uint256 predictionId => bool) public claimed;

    /// @notice Emitted at construction to enable off-chain indexing by matchweekId.
    /// @param matchweekId   Unique identifier for this matchweek.
    /// @param matchweek     Address of the deployed matchweek contract.
    /// @param predictionDeadline Timestamp after which no more predictions are accepted.
    /// @param matches       The ten matches created with this matchweek.
    event MatchweekCreated(uint32 indexed matchweekId, address matchweek, uint40 predictionDeadline, Match[10] matches);

    /// @notice Emitted when the admin publishes the ten match outcomes.
    /// @param matchweekId Unique identifier for this matchweek.
    /// @param outcomes    The ten final outcomes (0=home, 1=draw, 2=away).
    event ResultsPublished(uint32 indexed matchweekId, uint8[10] outcomes);

    /// @notice Emitted when {DISPUTES} applies a correction to the published outcomes after a
    ///         dispute was confirmed as valid.
    /// @param matchweekId Unique identifier for this matchweek.
    /// @param outcomes    The corrected ten outcomes (0=home, 1=draw, 2=away).
    event ResultsCorrected(uint32 indexed matchweekId, uint8[10] outcomes);

    /// @notice Emitted when the admin commits the prize distribution Merkle root.
    /// @param matchweekId Unique identifier for this matchweek.
    /// @param claimsRoot  Merkle root over (predictionId, tier) leaves for all winning predictions.
    /// @param prizePerTier Prize pool allocated to each tier (indices 0–4 = tiers 6–10).
    /// @param unallocated  Pool amount from tiers with no winners, carried to the carry pool.
    /// @param protocolFee  Fee retained by the protocol and sent to the treasury.
    event DistributionCommitted(
        uint32 indexed matchweekId,
        bytes32 claimsRoot,
        uint256[5] prizePerTier,
        uint256 unallocated,
        uint256 protocolFee
    );

    /// @notice Emitted when a winner claims their prize.
    /// @param matchweekId Unique identifier for this matchweek.
    /// @param predictionId     The prediction for which the prize is claimed.
    /// @param claimant    Address that received the prize.
    /// @param amount      Amount of stablecoin transferred.
    event PrizeClaimed(
        uint32 indexed matchweekId, uint256 indexed predictionId, address indexed claimant, uint256 amount
    );

    /// @notice Emitted when a user submits a prediction.
    /// @param predictionId     Unique, sequential identifier for this prediction within the matchweek.
    /// @param user        Address that submitted the prediction.
    /// @param matchweekId Unique identifier for this matchweek.
    /// @param predictions The ten predicted outcomes (0=home, 1=draw, 2=away).
    /// @param stake       Amount of stablecoin staked on this prediction.
    event PredictionSubmitted(
        uint256 indexed predictionId,
        address indexed user,
        uint32 indexed matchweekId,
        uint8[10] predictions,
        uint256 stake
    );

    /// @notice Thrown if the constructor is given a matches array of incorrect length.
    error WrongMatchCount(uint256 provided);

    /// @notice Thrown if the prediction deadline is not in the future at construction.
    error DeadlineInPast(uint40 predictionDeadline);

    /// @notice Thrown if `initialize` is called more than once on the same instance.
    error AlreadyInitialized();

    /// @notice Thrown if a prediction is submitted after the prediction deadline has passed.
    error PredictionWindowClosed();

    /// @notice Thrown if a predicted outcome is not 0 (home), 1 (draw), or 2 (away).
    error InvalidPredictionValue(uint256 index, uint8 value);

    /// @notice Thrown if a prediction is submitted with a stake below {MIN_STAKE_AMOUNT}.
    error StakeTooLow(uint256 provided, uint256 minimum);

    /// @notice Thrown if the constructor is given the zero address as the stablecoin.
    error InvalidStablecoin();

    /// @notice Thrown if the constructor is given the zero address as the carry pool.
    error InvalidCarryPool();

    /// @notice Thrown if the constructor is given the zero address as the treasury.
    error InvalidTreasury();

    /// @notice Thrown if the constructor is given the zero address as the disputes contract.
    error InvalidDisputes();

    /// @notice Thrown if `applyDisputeCorrection` is called by any account other than {DISPUTES}.
    error NotDisputes();

    /// @notice Thrown if `commitDistribution` is called before {DISPUTES} reports this matchweek
    ///         as settled (dispute window closed, no unresolved dispute).
    error DisputeNotSettled();

    /// @notice Thrown if `publishResults` is called before the prediction deadline has passed.
    error DeadlineNotPassed();

    /// @notice Thrown if `publishResults` is called after results have already been published.
    error ResultsAlreadyPublished();

    /// @notice Thrown if `commitDistribution` is called before results have been published.
    error ResultsNotPublished();

    /// @notice Thrown if a published outcome value is not 0 (home), 1 (draw), or 2 (away).
    error InvalidOutcome(uint256 index, uint8 value);

    /// @notice Thrown if `commitDistribution` is called after distribution has already been committed.
    error DistributionAlreadyCommitted();

    /// @notice Thrown if `claimPrize` is called before distribution has been committed.
    error DistributionNotCommitted();

    /// @notice Thrown if a tier value in `claimPrize` is outside the valid range 6–10.
    error InvalidTier(uint8 tier);

    /// @notice Thrown if the Merkle proof in `claimPrize` does not verify against {claimsRoot}.
    error InvalidProof(uint256 predictionId, uint8 tier);

    /// @notice Thrown if `claimPrize` is called by an address that does not own the prediction.
    error NotPredictionOwner(uint256 predictionId);

    /// @notice Thrown if `claimPrize` is called for a prediction that has already been claimed.
    error AlreadyClaimed(uint256 predictionId);

    /// @notice Thrown if `claimPrize` is called for a tier with zero winners.
    /// @dev    Indicates a bug in the admin's off-chain computation (winning tier with no winners).
    error EmptyTierPool(uint8 tier);

    modifier duringPredictionWindow() {
        _duringPredictionWindow();
        _;
    }

    modifier afterPredictionDeadline() {
        _afterPredictionDeadline();
        _;
    }

    modifier whenResultsNotPublished() {
        _whenResultsNotPublished();
        _;
    }

    modifier whenResultsPublished() {
        _whenResultsPublished();
        _;
    }

    modifier whenDistributionNotCommitted() {
        _whenDistributionNotCommitted();
        _;
    }

    modifier whenDistributionCommitted() {
        _whenDistributionCommitted();
        _;
    }

    modifier onlyDisputes() {
        _onlyDisputes();
        _;
    }

    modifier whenDisputeSettled() {
        _whenDisputeSettled();
        _;
    }

    /// @notice Sets the stablecoin, carry pool, treasury and disputes contract shared by every
    ///         clone and locks the implementation contract so it can never be initialized directly.
    /// @dev Instances are meant to be deployed as EIP-1167 minimal proxy clones of this
    ///      implementation, then initialized via {initialize}. Since clones delegatecall into
    ///      the implementation's code, STABLECOIN's, CARRY_POOL's, TREASURY's and DISPUTES's
    ///      values (baked into that code) are shared by every clone without needing to be set
    ///      per-instance.
    /// @param stablecoin_ ERC20 token accepted as stake for predictions, for every matchweek clone.
    /// @param carryPool_  Standalone carry pool shared by every matchweek clone.
    /// @param treasury_   Standalone treasury shared by every matchweek clone.
    /// @param disputes_   Standalone disputes contract shared by every matchweek clone.
    constructor(IERC20 stablecoin_, CarryPool carryPool_, Treasury treasury_, Disputes disputes_) Ownable(msg.sender) {
        if (address(stablecoin_) == address(0)) revert InvalidStablecoin();
        if (address(carryPool_) == address(0)) revert InvalidCarryPool();
        if (address(treasury_) == address(0)) revert InvalidTreasury();
        if (address(disputes_) == address(0)) revert InvalidDisputes();
        STABLECOIN = stablecoin_;
        CARRY_POOL = carryPool_;
        TREASURY = treasury_;
        DISPUTES = disputes_;
        _initialized = true;
    }

    /// @notice Initializes a cloned matchweek instance with ten matches and sets the owner.
    /// @dev Reverts if already initialized, matches.length != 10, predictionDeadline is not in the
    ///      future, or admin is the zero address.
    /// @param matchweekId_   Unique identifier for this matchweek.
    /// @param predictionDeadline_ Timestamp after which no more predictions are accepted.
    /// @param matches        Exactly 10 matches.
    /// @param admin          Address that becomes the owner of this contract.
    function initialize(uint32 matchweekId_, uint40 predictionDeadline_, Match[] calldata matches, address admin)
        external
    {
        if (_initialized) revert AlreadyInitialized();
        if (matches.length != MATCH_COUNT) revert WrongMatchCount(matches.length);
        if (predictionDeadline_ <= uint40(block.timestamp)) revert DeadlineInPast(predictionDeadline_);
        if (admin == address(0)) revert OwnableInvalidOwner(address(0));

        _initialized = true;
        matchweekId = matchweekId_;
        predictionDeadline = predictionDeadline_;
        for (uint256 i = 0; i < MATCH_COUNT; ++i) {
            _matches[i] = matches[i];
        }
        _transferOwnership(admin);

        emit MatchweekCreated(matchweekId, address(this), predictionDeadline, _matches);
    }

    /// @notice Submits a prediction for this matchweek, staking `stake` stablecoin on it.
    /// @dev Reverts if the prediction deadline has passed, `stake` is below {MIN_STAKE_AMOUNT}, or
    ///      any predicted outcome is not 0, 1, or 2. Multiple predictions per address are allowed.
    ///      The full prediction array is not persisted in contract storage — only its hash,
    ///      recoverable from the {PredictionSubmitted} event — so {claimPrize} can verify that
    ///      predictions presented on-chain match what was originally submitted. Pulls `stake` from
    ///      the caller via `transferFrom`, which requires prior `approve`.
    /// @param predictions The ten predicted outcomes (0=home, 1=draw, 2=away).
    /// @param stake       Amount of stablecoin to stake on this prediction, at least {MIN_STAKE_AMOUNT}.
    /// @return predictionId Unique, sequential identifier assigned to this prediction.
    function submitPrediction(uint8[10] calldata predictions, uint256 stake)
        external
        nonReentrant
        duringPredictionWindow
        returns (uint256 predictionId)
    {
        if (stake < MIN_STAKE_AMOUNT) revert StakeTooLow(stake, MIN_STAKE_AMOUNT);
        for (uint256 i = 0; i < MATCH_COUNT; ++i) {
            if (predictions[i] > MAX_OUTCOME) revert InvalidPredictionValue(i, predictions[i]);
        }

        predictionId = predictionCount++;
        predictionOwner[predictionId] = msg.sender;
        predictionHash[predictionId] = keccak256(abi.encode(predictions));
        predictionStake[predictionId] = stake;
        totalStaked += stake;

        STABLECOIN.safeTransferFrom(msg.sender, address(this), stake);
        emit PredictionSubmitted(predictionId, msg.sender, matchweekId, predictions, stake);
    }

    /// @notice Publishes the ten final match outcomes on-chain, opening the dispute window.
    /// @dev Reverts if called before the prediction deadline, if outcomes have already been
    ///      published, or if any outcome value is not 0, 1, or 2. Opens {DISPUTES}'s dispute
    ///      window for this matchweek; {commitDistribution} stays blocked until it reports this
    ///      matchweek as settled.
    /// @param outcomes The ten final outcomes (0=home, 1=draw, 2=away).
    function publishResults(uint8[10] calldata outcomes)
        external
        onlyOwner
        afterPredictionDeadline
        whenResultsNotPublished
    {
        for (uint256 i = 0; i < MATCH_COUNT; ++i) {
            if (outcomes[i] > MAX_OUTCOME) revert InvalidOutcome(i, outcomes[i]);
        }

        _outcomes = outcomes;
        resultsPublished = true;

        emit ResultsPublished(matchweekId, outcomes);

        DISPUTES.openDisputeWindow();
    }

    /// @notice Overwrites the published outcomes after {DISPUTES} confirms a dispute as valid.
    /// @dev Reverts if called by anyone other than {DISPUTES}, or if any outcome value is not
    ///      0, 1, or 2.
    /// @param correctedOutcomes The corrected ten outcomes (0=home, 1=draw, 2=away).
    function applyDisputeCorrection(uint8[10] calldata correctedOutcomes) external onlyDisputes {
        for (uint256 i = 0; i < MATCH_COUNT; ++i) {
            if (correctedOutcomes[i] > MAX_OUTCOME) revert InvalidOutcome(i, correctedOutcomes[i]);
        }

        _outcomes = correctedOutcomes;

        emit ResultsCorrected(matchweekId, correctedOutcomes);
    }

    /// @notice Commits the prize distribution as a Merkle root and the per-tier winning stake.
    /// @dev Each Merkle leaf is `keccak256(abi.encode(predictionId, tier))`.
    ///      Tiers 6–10 map to indices 0–4 (`index = tier - 6`).
    ///      Prize pools are computed on-chain from {PrizeConfig} percentages and {totalStaked}:
    ///      tiers with no winners contribute their percentage to {unallocated} instead.
    ///      {PrizeConfig.PROTOCOL_FEE_PCT} of the total staked is retained as {protocolFee} and
    ///      transferred to {TREASURY}. {unallocated} is the remainder after prizes and fee, so the
    ///      carry pool only ever receives unawarded prize money — never fee revenue.
    ///      If tier 10 has winners (a perfect ten), {CARRY_POOL} releases its entire accumulated
    ///      balance to this matchweek first, added on top of that tier's prize pool. {unallocated}
    ///      is then transferred to {CARRY_POOL} regardless, seeding the next carry cycle.
    ///      Reverts if results have not been published, distribution has already been committed,
    ///      or {DISPUTES} does not yet report this matchweek as settled (dispute window still
    ///      open, or an open dispute not yet resolved).
    /// @param claimsRoot_        Merkle root over (predictionId, tier) leaves for all winning predictions.
    /// @param totalStakePerTier_ Sum of the winning predictions' stakes per tier (indices 0–4 = tiers
    ///                           6–10), used as the denominator for each winner's proportional
    ///                           share in {claimPrize}. Zero means no winners in that tier.
    function commitDistribution(bytes32 claimsRoot_, uint256[5] calldata totalStakePerTier_)
        external
        onlyOwner
        whenResultsPublished
        whenDistributionNotCommitted
        whenDisputeSettled
    {
        claimsRoot = claimsRoot_;
        totalStakePerTier = totalStakePerTier_;

        uint256[5] memory pcts = [
            PrizeConfig.TIER6_PRIZE_PCT,
            PrizeConfig.TIER7_PRIZE_PCT,
            PrizeConfig.TIER8_PRIZE_PCT,
            PrizeConfig.TIER9_PRIZE_PCT,
            PrizeConfig.TIER10_PRIZE_PCT
        ];

        uint256 totalAllocated;
        for (uint256 i = 0; i < PrizeConfig.TIER_COUNT; ++i) {
            if (totalStakePerTier_[i] > 0) {
                uint256 tierPrize = totalStaked * pcts[i] / PrizeConfig.PCT_DENOMINATOR;
                prizePerTier[i] = tierPrize;
                totalAllocated += tierPrize;
            }
        }
        uint256 fee = totalStaked * PrizeConfig.PROTOCOL_FEE_PCT / PrizeConfig.PCT_DENOMINATOR;
        protocolFee = fee;
        // Remainder after prizes and fee: the percentages of tiers that had no winners, plus any
        // dust left by integer division. Dust falls here rather than into the fee, so the protocol
        // never collects more than {PrizeConfig.PROTOCOL_FEE_PCT}.
        unallocated = totalStaked - totalAllocated - fee;
        distributionCommitted = true;

        if (totalStakePerTier_[TIER10_INDEX] > 0) {
            uint256 released = CARRY_POOL.release(matchweekId);
            if (released > 0) {
                prizePerTier[TIER10_INDEX] += released;
            }
        }

        if (fee > 0) {
            STABLECOIN.safeTransfer(address(TREASURY), fee);
            TREASURY.deposit(matchweekId, fee);
        }

        if (unallocated > 0) {
            STABLECOIN.safeTransfer(address(CARRY_POOL), unallocated);
            CARRY_POOL.fund(matchweekId, unallocated);
        }

        emit DistributionCommitted(matchweekId, claimsRoot_, prizePerTier, unallocated, fee);
    }

    /// @notice Claims the prize for a winning prediction by providing a Merkle proof.
    /// @dev Reverts if distribution has not been committed, the caller is not the prediction
    ///      owner, the prediction has already been claimed, the tier is out of range 6–10,
    ///      or the Merkle proof is invalid. Prize share is proportional to what this prediction
    ///      staked relative to the tier's total: `prizePerTier[tier] * predictionStake[predictionId]
    ///      / totalStakePerTier[tier]`.
    /// @param predictionId Unique identifier of the prediction to claim.
    /// @param tier    Number of correct picks for this prediction (6–10).
    /// @param proof   Merkle proof that `(predictionId, tier)` is included in {claimsRoot}.
    function claimPrize(uint256 predictionId, uint8 tier, bytes32[] calldata proof)
        external
        nonReentrant
        whenDistributionCommitted
    {
        if (msg.sender != predictionOwner[predictionId]) revert NotPredictionOwner(predictionId);
        if (claimed[predictionId]) revert AlreadyClaimed(predictionId);
        if (tier < PrizeConfig.MIN_WINNING_TIER || tier > PrizeConfig.MAX_WINNING_TIER) revert InvalidTier(tier);

        // Double-hash the leaf: abi.encode produces 64 bytes (uint256 + uint8 padded),
        // which is the same length as an internal Merkle node. Double-hashing separates
        // the two domains and prevents second-preimage attacks.
        bytes32 leaf;
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, predictionId)
            mstore(add(ptr, 0x20), tier)
            mstore(ptr, keccak256(ptr, 0x40))
            leaf := keccak256(ptr, 0x20)
        }
        if (!MerkleProof.verify(proof, claimsRoot, leaf)) revert InvalidProof(predictionId, tier);

        uint256 idx = tier - PrizeConfig.MIN_WINNING_TIER;
        if (totalStakePerTier[idx] == 0) revert EmptyTierPool(tier);

        uint256 share = prizePerTier[idx] * predictionStake[predictionId] / totalStakePerTier[idx];

        claimed[predictionId] = true;
        STABLECOIN.safeTransfer(msg.sender, share);
        emit PrizeClaimed(matchweekId, predictionId, msg.sender, share);
    }

    /// @notice Returns all ten match outcomes published by the admin.
    /// @dev Returns an empty array before {publishResults} is called.
    /// @return The array of 10 outcome values (0=home, 1=draw, 2=away).
    function getOutcomes() external view returns (uint8[10] memory) {
        return _outcomes;
    }

    /// @notice Returns all ten matches stored in this matchweek.
    /// @dev Returns a fixed-size array copy; safe to call at any lifecycle state.
    /// @return The array of 10 Match structs for this matchweek.
    function getMatches() external view returns (Match[10] memory) {
        return _matches;
    }

    function _duringPredictionWindow() internal view {
        if (block.timestamp >= predictionDeadline) revert PredictionWindowClosed();
    }

    function _afterPredictionDeadline() internal view {
        if (block.timestamp < predictionDeadline) revert DeadlineNotPassed();
    }

    function _whenResultsNotPublished() internal view {
        if (resultsPublished) revert ResultsAlreadyPublished();
    }

    function _whenResultsPublished() internal view {
        if (!resultsPublished) revert ResultsNotPublished();
    }

    function _whenDistributionNotCommitted() internal view {
        if (distributionCommitted) revert DistributionAlreadyCommitted();
    }

    function _whenDistributionCommitted() internal view {
        if (!distributionCommitted) revert DistributionNotCommitted();
    }

    function _onlyDisputes() internal view {
        if (msg.sender != address(DISPUTES)) revert NotDisputes();
    }

    function _whenDisputeSettled() internal view {
        if (!DISPUTES.isSettled(address(this))) revert DisputeNotSettled();
    }
}
