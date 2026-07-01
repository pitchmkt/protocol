// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PrizeConfig} from "./PrizeConfig.sol";

/// @title Matchweek
/// @author PitchMkt
/// @notice Stores the ten matches for a single PitchMkt matchweek and accepts
///         predictions until the entry deadline.
contract Matchweek is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Possible outcomes for a single match.
    enum Outcome {
        Home,  // 0 — home team wins
        Draw,  // 1 — match ends in a draw
        Away   // 2 — away team wins
    }

    /// @dev homeTeam / awayTeam are bytes32 (e.g. keccak256 of a team slug).
    struct Match {
        bytes32 homeTeam;
        bytes32 awayTeam;
    }

    /// @notice Minimum stake required per entry: 5 USDC (6 decimals).
    uint256 public constant MIN_STAKE = 5_000_000;

    /// @notice Number of matches per matchweek.
    uint256 public constant MATCH_COUNT = 10;

    /// @dev Upper bound for outcome validation, derived from the {Outcome} enum.
    uint8 private constant MAX_OUTCOME = uint8(type(Outcome).max);

    /// @notice ERC20 token accepted as stake for entries, shared by every matchweek clone.
    IERC20 public immutable STABLECOIN;

    uint32 public matchweekId;
    uint40 public entryDeadline;
    Match[10] private _matches;
    bool private _initialized;
    uint256 public entryCount;
    uint256 public totalStaked;
    mapping(uint256 entryId => address user) public entryOwner;
    mapping(uint256 entryId => bytes32 predictionHash) public predictionHashByEntry;
    mapping(uint256 entryId => uint256 stakedAmount) public stakeByEntry;

    uint8[10] private _outcomes;
    bool public resultsPublished;

    bytes32 public claimsRoot;
    /// @dev Tiers 6–10 are stored at indices 0–4 (index = tier - {PrizeConfig.MIN_WINNING_TIER}).
    ///      winnersStakePerTier is the denominator for proportional distribution within each tier.
    uint256[5] public winnersStakePerTier;
    uint256[5] public prizePerTier;
    // TODO: transfer unallocated amount to a persistent jackpot vault across matchweeks.
    uint256 public unallocated;
    bool public distributionCommitted;

    mapping(uint256 entryId => bool) public claimed;

    /// @notice Emitted at construction to enable off-chain indexing by matchweekId.
    /// @param matchweekId   Unique identifier for this matchweek.
    /// @param matchweek     Address of the deployed matchweek contract.
    /// @param entryDeadline Timestamp after which no more entries are accepted.
    /// @param matches       The ten matches created with this matchweek.
    event MatchweekCreated(uint32 indexed matchweekId, address matchweek, uint40 entryDeadline, Match[10] matches);

    /// @notice Emitted when the admin publishes the ten match outcomes.
    /// @param matchweekId Unique identifier for this matchweek.
    /// @param outcomes    The ten final outcomes (0=home, 1=draw, 2=away).
    event ResultsPublished(uint32 indexed matchweekId, uint8[10] outcomes);

    /// @notice Emitted when the admin commits the prize distribution Merkle root.
    /// @param matchweekId Unique identifier for this matchweek.
    /// @param claimsRoot  Merkle root over (entryId, tier) leaves for all winning entries.
    /// @param prizePerTier Prize pool allocated to each tier (indices 0–4 = tiers 6–10).
    /// @param unallocated  Pool amount from tiers with no winners, carried to the jackpot.
    event DistributionCommitted(
        uint32 indexed matchweekId,
        bytes32 claimsRoot,
        uint256[5] prizePerTier,
        uint256 unallocated
    );

    /// @notice Emitted when a winner claims their prize.
    /// @param entryId  The entry for which the prize is claimed.
    /// @param claimant Address that received the prize.
    /// @param amount   Amount of stablecoin transferred.
    event PrizeClaimed(uint256 indexed entryId, address indexed claimant, uint256 amount);

    /// @notice Emitted when a user submits a prediction entry.
    /// @param entryId     Unique, sequential identifier for this entry within the matchweek.
    /// @param user        Address that submitted the entry.
    /// @param matchweekId Unique identifier for this matchweek.
    /// @param predictions The ten predicted outcomes (0=home, 1=draw, 2=away).
    /// @param stake       Amount of stablecoin staked on this entry.
    event PredictionSubmitted(
        uint256 indexed entryId, address indexed user, uint32 indexed matchweekId, uint8[10] predictions, uint256 stake
    );

    /// @notice Thrown if the constructor is given a matches array of incorrect length.
    error WrongMatchCount(uint256 provided);

    /// @notice Thrown if the entry deadline is not in the future at construction.
    error DeadlineInPast(uint40 entryDeadline);

    /// @notice Thrown if `initialize` is called more than once on the same instance.
    error AlreadyInitialized();

    /// @notice Thrown if a prediction is submitted after the entry deadline has passed.
    error EntryWindowClosed();

    /// @notice Thrown if a predicted outcome is not 0 (home), 1 (draw), or 2 (away).
    error InvalidPredictionValue(uint256 index, uint8 value);

    /// @notice Thrown if a stake is below {MIN_STAKE}.
    error BelowMinimumStake(uint256 provided, uint256 minimum);

    /// @notice Thrown if the constructor is given the zero address as the stablecoin.
    error InvalidStablecoin();

    /// @notice Thrown if `publishResults` is called before the entry deadline has passed.
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
    error InvalidProof(uint256 entryId, uint8 tier);

    /// @notice Thrown if `claimPrize` is called by an address that does not own the entry.
    error NotEntryOwner(uint256 entryId);

    /// @notice Thrown if `claimPrize` is called for an entry that has already been claimed.
    error AlreadyClaimed(uint256 entryId);

    /// @notice Thrown if `claimPrize` is called for a tier whose staked total is zero.
    /// @dev    Indicates a bug in the admin's off-chain computation (winning tier with no stake).
    error EmptyTierPool(uint8 tier);


    modifier duringEntryWindow() {
        if (block.timestamp >= entryDeadline) revert EntryWindowClosed();
        _;
    }

    modifier afterEntryDeadline() {
        if (block.timestamp < entryDeadline) revert DeadlineNotPassed();
        _;
    }

    modifier whenResultsNotPublished() {
        if (resultsPublished) revert ResultsAlreadyPublished();
        _;
    }

    modifier whenResultsPublished() {
        if (!resultsPublished) revert ResultsNotPublished();
        _;
    }

    modifier whenDistributionNotCommitted() {
        if (distributionCommitted) revert DistributionAlreadyCommitted();
        _;
    }

    modifier whenDistributionCommitted() {
        if (!distributionCommitted) revert DistributionNotCommitted();
        _;
    }

    /// @notice Sets the stablecoin shared by every clone and locks the implementation contract
    ///         so it can never be initialized directly.
    /// @dev Instances are meant to be deployed as EIP-1167 minimal proxy clones of this
    ///      implementation, then initialized via {initialize}. Since clones delegatecall into
    ///      the implementation's code, STABLECOIN's value (baked into that code) is shared by
    ///      every clone without needing to be set per-instance.
    /// @param stablecoin_ ERC20 token accepted as stake for entries, for every matchweek clone.
    constructor(IERC20 stablecoin_) Ownable(msg.sender) {
        if (address(stablecoin_) == address(0)) revert InvalidStablecoin();
        STABLECOIN = stablecoin_;
        _initialized = true;
    }

    /// @notice Initializes a cloned matchweek instance with ten matches and sets the owner.
    /// @dev Reverts if already initialized, matches.length != 10, entryDeadline is not in the
    ///      future, or admin is the zero address.
    /// @param matchweekId_   Unique identifier for this matchweek.
    /// @param entryDeadline_ Timestamp after which no more entries are accepted.
    /// @param matches        Exactly 10 matches.
    /// @param admin          Address that becomes the owner of this contract.
    function initialize(uint32 matchweekId_, uint40 entryDeadline_, Match[] calldata matches, address admin) external {
        if (_initialized) revert AlreadyInitialized();
        if (matches.length != MATCH_COUNT) revert WrongMatchCount(matches.length);
        if (entryDeadline_ <= uint40(block.timestamp)) revert DeadlineInPast(entryDeadline_);
        if (admin == address(0)) revert OwnableInvalidOwner(address(0));

        _initialized = true;
        matchweekId = matchweekId_;
        entryDeadline = entryDeadline_;
        for (uint256 i = 0; i < MATCH_COUNT; ++i) {
            _matches[i] = matches[i];
        }
        _transferOwnership(admin);

        emit MatchweekCreated(matchweekId, address(this), entryDeadline, _matches);
    }

    /// @notice Submits a prediction entry for this matchweek, staking stablecoin on it.
    /// @dev Reverts if the entry deadline has passed, any predicted outcome is not 0, 1, or 2,
    ///      or stake is below {MIN_STAKE}. Multiple entries per address are allowed. The full
    ///      prediction array is not persisted in contract storage — only its hash, recoverable
    ///      from the {PredictionSubmitted} event — so {claimPrize} can verify that predictions
    ///      presented on-chain match what was originally submitted. Pulls `stake` from the
    ///      caller via `transferFrom`, which requires prior `approve`.
    /// @param predictions The ten predicted outcomes (0=home, 1=draw, 2=away).
    /// @param stake       Amount of stablecoin to stake on this entry; must be >= {MIN_STAKE}.
    /// @return entryId Unique, sequential identifier assigned to this entry.
    function submitPrediction(uint8[10] calldata predictions, uint256 stake)
        external
        nonReentrant
        duringEntryWindow
        returns (uint256 entryId)
    {
        if (stake < MIN_STAKE) revert BelowMinimumStake(stake, MIN_STAKE);

        for (uint256 i = 0; i < MATCH_COUNT; ++i) {
            if (predictions[i] > MAX_OUTCOME) revert InvalidPredictionValue(i, predictions[i]);
        }

        entryId = entryCount++;
        entryOwner[entryId] = msg.sender;
        predictionHashByEntry[entryId] = keccak256(abi.encode(predictions));
        stakeByEntry[entryId] = stake;
        totalStaked += stake;

        STABLECOIN.safeTransferFrom(msg.sender, address(this), stake);
        emit PredictionSubmitted(entryId, msg.sender, matchweekId, predictions, stake);
    }

    /// @notice Publishes the ten final match outcomes on-chain, opening the claim phase.
    /// @dev Reverts if called before the entry deadline, if outcomes have already been
    ///      published, or if any outcome value is not 0, 1, or 2.
    /// @param outcomes The ten final outcomes (0=home, 1=draw, 2=away).
    function publishResults(uint8[10] calldata outcomes)
        external
        onlyOwner
        afterEntryDeadline
        whenResultsNotPublished
    {
        for (uint256 i = 0; i < MATCH_COUNT; ++i) {
            if (outcomes[i] > MAX_OUTCOME) revert InvalidOutcome(i, outcomes[i]);
        }

        _outcomes = outcomes;
        resultsPublished = true;

        emit ResultsPublished(matchweekId, outcomes);
    }

    /// @notice Commits the prize distribution as a Merkle root and the per-tier winner stakes.
    /// @dev Each Merkle leaf is `keccak256(abi.encode(entryId, tier))`.
    ///      Tiers 6–10 map to indices 0–4 (`index = tier - 6`).
    ///      Prize pools are computed on-chain from {PrizeConfig} percentages and {totalStaked}: tiers with
    ///      no winners contribute their percentage to {unallocated} instead.
    ///      Reverts if results have not been published or distribution has already been committed.
    /// @param claimsRoot_          Merkle root over (entryId, tier) leaves for all winning entries.
    /// @param winnersStakePerTier_ Sum of individual stakes of winning entries per tier
    ///                             (indices 0–4 = tiers 6–10). Zero means no winners in that tier.
    function commitDistribution(
        bytes32 claimsRoot_,
        uint256[5] calldata winnersStakePerTier_
    ) external onlyOwner whenResultsPublished whenDistributionNotCommitted {
        claimsRoot = claimsRoot_;
        winnersStakePerTier = winnersStakePerTier_;

        uint256[5] memory pcts = [
            PrizeConfig.TIER6_PRIZE_PCT,
            PrizeConfig.TIER7_PRIZE_PCT,
            PrizeConfig.TIER8_PRIZE_PCT,
            PrizeConfig.TIER9_PRIZE_PCT,
            PrizeConfig.TIER10_PRIZE_PCT
        ];

        uint256 totalAllocated;
        for (uint256 i = 0; i < PrizeConfig.TIER_COUNT; ++i) {
            if (winnersStakePerTier_[i] > 0) {
                uint256 tierPrize = totalStaked * pcts[i] / PrizeConfig.PCT_DENOMINATOR;
                prizePerTier[i] = tierPrize;
                totalAllocated += tierPrize;
            }
        }
        // Remainder: empty-tier percentages + the 3% not assigned to any tier (fee — TODO).
        // TODO: transfer unallocated to a persistent jackpot vault across matchweeks.
        unallocated = totalStaked - totalAllocated;
        distributionCommitted = true;

        emit DistributionCommitted(matchweekId, claimsRoot_, prizePerTier, unallocated);
    }

    /// @notice Claims the prize for a winning entry by providing a Merkle proof.
    /// @dev Reverts if distribution has not been committed, the caller is not the entry
    ///      owner, the entry has already been claimed, the tier is out of range 6–10,
    ///      or the Merkle proof is invalid. Prize share is proportional to the entry's
    ///      stake within the tier: `stakeByEntry[entryId] * prizePerTier[tier] / winnersStakePerTier[tier]`.
    ///      Follows checks-effects-interactions: `claimed` is set before the transfer.
    /// @param entryId Unique identifier of the entry to claim.
    /// @param tier    Number of correct predictions for this entry (6–10).
    /// @param proof   Merkle proof that `(entryId, tier)` is included in {claimsRoot}.
    function claimPrize(uint256 entryId, uint8 tier, bytes32[] calldata proof)
        external
        nonReentrant
        whenDistributionCommitted
    {
        if (msg.sender != entryOwner[entryId]) revert NotEntryOwner(entryId);
        if (claimed[entryId]) revert AlreadyClaimed(entryId);
        if (tier < PrizeConfig.MIN_WINNING_TIER || tier > PrizeConfig.MAX_WINNING_TIER) revert InvalidTier(tier);

        // Double-hash the leaf: abi.encode produces 64 bytes (uint256 + uint8 padded),
        // which is the same length as an internal Merkle node. Double-hashing separates
        // the two domains and prevents second-preimage attacks.
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(entryId, tier))));
        if (!MerkleProof.verify(proof, claimsRoot, leaf)) revert InvalidProof(entryId, tier);

        uint256 idx = tier - PrizeConfig.MIN_WINNING_TIER;
        if (winnersStakePerTier[idx] == 0) revert EmptyTierPool(tier);

        uint256 share = stakeByEntry[entryId] * prizePerTier[idx] / winnersStakePerTier[idx];

        // Checks-effects-interactions: state update before external call.
        claimed[entryId] = true;
        STABLECOIN.safeTransfer(msg.sender, share);
        emit PrizeClaimed(entryId, msg.sender, share);
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

}
