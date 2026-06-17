// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Matchweek
/// @author PitchMkt
/// @notice Stores the ten matches for a single PitchMkt matchweek and tracks
///         the lifecycle state from Open through to Finalized.
contract Matchweek is Ownable {
    /// @dev homeTeam / awayTeam are bytes32 (e.g. keccak256 of a team slug).
    struct Match {
        bytes32 homeTeam;
        bytes32 awayTeam;
    }

    /// @notice Lifecycle states of a matchweek, tracked by the `state` variable.
    enum State {
        Open,
        Closed,
        Finalized
    }

    uint32 public matchweekId;
    uint40 public entryDeadline;
    State public state;
    Match[10] private _matches;
    bool private _initialized;

    /// @notice Emitted at construction to enable off-chain indexing by matchweekId.
    /// @param matchweekId   Unique identifier for this matchweek.
    /// @param matchweek     Address of the deployed matchweek contract.
    /// @param entryDeadline Timestamp after which no more entries are accepted.
    /// @param matches       The ten matches created with this matchweek.
    event MatchweekCreated(uint32 indexed matchweekId, address matchweek, uint40 entryDeadline, Match[10] matches);

    /// @notice Thrown if the constructor is given a matches array of incorrect length.
    error WrongMatchCount(uint256 provided);

    /// @notice Thrown if the entry deadline is not in the future at construction.
    error DeadlineInPast(uint40 entryDeadline);

    /// @notice Thrown if `initialize` is called more than once on the same instance.
    error AlreadyInitialized();

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
        state = State.Open;
        _initMatches(matches);
        _transferOwnership(admin);

        emit MatchweekCreated(matchweekId, address(this), entryDeadline, _matches);
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
