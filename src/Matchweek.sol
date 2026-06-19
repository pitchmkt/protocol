// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Matchweek
/// @author PitchMkt
/// @notice Stores the ten matches for a single PitchMkt matchweek and accepts
///         predictions until the entry deadline.
contract Matchweek is Ownable {
    /// @dev homeTeam / awayTeam are bytes32 (e.g. keccak256 of a team slug).
    struct Match {
        bytes32 homeTeam;
        bytes32 awayTeam;
    }

    uint32 public matchweekId;
    uint40 public entryDeadline;
    Match[10] private _matches;
    bool private _initialized;
    uint256 public entryCount;
    mapping(uint256 entryId => address user) public entryOwner;
    mapping(uint256 entryId => bytes32 predictionHash) public predictionByEntry;

    /// @notice Emitted at construction to enable off-chain indexing by matchweekId.
    /// @param matchweekId   Unique identifier for this matchweek.
    /// @param matchweek     Address of the deployed matchweek contract.
    /// @param entryDeadline Timestamp after which no more entries are accepted.
    /// @param matches       The ten matches created with this matchweek.
    event MatchweekCreated(uint32 indexed matchweekId, address matchweek, uint40 entryDeadline, Match[10] matches);

    /// @notice Emitted when a user submits a prediction entry.
    /// @param entryId     Unique, sequential identifier for this entry within the matchweek.
    /// @param user        Address that submitted the entry.
    /// @param matchweekId Unique identifier for this matchweek.
    /// @param predictions The ten predicted outcomes (0=home, 1=draw, 2=away).
    event PredictionSubmitted(
        uint256 indexed entryId, address indexed user, uint32 indexed matchweekId, uint8[10] predictions
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

    /// @notice Locks the implementation contract so it can never be initialized directly.
    /// @dev Instances are meant to be deployed as EIP-1167 minimal proxy clones of this
    ///      implementation, then initialized via {initialize}.
    constructor() Ownable(msg.sender) {
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
        if (matches.length != 10) revert WrongMatchCount(matches.length);
        if (entryDeadline_ <= uint40(block.timestamp)) revert DeadlineInPast(entryDeadline_);
        if (admin == address(0)) revert OwnableInvalidOwner(address(0));

        _initialized = true;
        matchweekId = matchweekId_;
        entryDeadline = entryDeadline_;
        _initMatches(matches);
        _transferOwnership(admin);

        emit MatchweekCreated(matchweekId, address(this), entryDeadline, _matches);
    }

    /// @notice Submits a prediction entry for this matchweek.
    /// @dev Reverts if the entry deadline has passed or any predicted outcome is not 0, 1, or 2.
    ///      Multiple entries per address are allowed. The full prediction array is not persisted
    ///      in contract storage — only its hash, recovered from the {PredictionSubmitted} event —
    ///      so a future claim flow can verify that predictions presented on-chain match what was
    ///      originally submitted.
    /// @param predictions The ten predicted outcomes (0=home, 1=draw, 2=away).
    /// @return entryId Unique, sequential identifier assigned to this entry.
    function submitPrediction(uint8[10] calldata predictions) external returns (uint256 entryId) {
        if (block.timestamp >= entryDeadline) revert EntryWindowClosed();

        for (uint256 i = 0; i < 10; ++i) {
            if (predictions[i] > 2) revert InvalidPredictionValue(i, predictions[i]);
        }

        entryId = entryCount++;
        entryOwner[entryId] = msg.sender;
        predictionByEntry[entryId] = keccak256(abi.encode(predictions));

        emit PredictionSubmitted(entryId, msg.sender, matchweekId, predictions);
    }

    /// @notice Returns all ten matches stored in this matchweek.
    /// @dev Returns a fixed-size array copy; safe to call at any lifecycle state.
    /// @return The array of 10 Match structs for this matchweek.
    function getMatches() external view returns (Match[10] memory) {
        return _matches;
    }

    /// @dev Copies matches into storage in a single pass.
    function _initMatches(Match[] memory matches) private {
        for (uint256 i = 0; i < 10; ++i) {
            _matches[i] = matches[i];
        }
    }
}
