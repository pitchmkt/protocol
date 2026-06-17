// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Matchweek} from "./Matchweek.sol";

/// @title MatchweekFactory
/// @author PitchMkt
/// @notice Restricts deployment of new Matchweek instances to the contract owner, and keeps
///         an on-chain registry of every Matchweek deployed through it.
/// @dev Deploys a single Matchweek implementation at construction and creates new instances
///      as EIP-1167 minimal proxy clones, initialized via {Matchweek.initialize}.
contract MatchweekFactory is Ownable {
    /// @notice Address of the Matchweek implementation that every clone delegates to.
    address public immutable IMPLEMENTATION;

    /// @notice Deployed Matchweek address for a given matchweekId.
    mapping(uint32 matchweekId => address matchweek) public matchweeks;

    /// @notice All Matchweek addresses deployed by this factory, in deployment order.
    address[] public deployedMatchweeks;

    /// @notice Emitted when a new Matchweek clone is deployed and initialized.
    /// @param matchweek   Address of the newly deployed Matchweek clone.
    /// @param matchweekId Unique identifier for this matchweek.
    event MatchweekDeployed(address indexed matchweek, uint32 indexed matchweekId);

    /// @notice Deploys the Matchweek implementation and sets the factory owner.
    /// @param admin Address that becomes the owner of this factory.
    constructor(address admin) Ownable(admin) {
        IMPLEMENTATION = address(new Matchweek());
    }

    /// @notice Deploys and initializes a new Matchweek instance.
    /// @dev Reverts if called by anyone other than the owner, or if the underlying
    ///      {Matchweek.initialize} call reverts.
    /// @param matchweekId   Unique identifier for this matchweek.
    /// @param entryDeadline Timestamp after which no more entries are accepted.
    /// @param matches       Exactly 10 matches.
    /// @param admin         Address that becomes the owner of the new Matchweek instance.
    /// @return matchweek Address of the newly deployed Matchweek clone.
    function createMatchweek(
        uint32 matchweekId,
        uint40 entryDeadline,
        Matchweek.Match[] calldata matches,
        address admin
    ) external onlyOwner returns (address matchweek) {
        matchweek = Clones.clone(IMPLEMENTATION);
        Matchweek(matchweek).initialize(matchweekId, entryDeadline, matches, admin);

        matchweeks[matchweekId] = matchweek;
        deployedMatchweeks.push(matchweek);

        emit MatchweekDeployed(matchweek, matchweekId);
    }
}
