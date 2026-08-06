// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CarryPool} from "./CarryPool.sol";
import {Matchweek} from "./Matchweek.sol";
import {Treasury} from "./Treasury.sol";

/// @title PitchMkt
/// @author PitchMkt
/// @notice Restricts deployment of new Matchweek instances to the contract owner, and keeps
///         an on-chain registry of every Matchweek deployed through it.
/// @dev Deploys a single Matchweek implementation at construction and creates new instances
///      as EIP-1167 minimal proxy clones, initialized via {Matchweek.initialize}.
contract PitchMkt is Ownable {
    /// @notice Address of the Matchweek implementation that every clone delegates to.
    address public immutable IMPLEMENTATION;

    /// @notice Standalone carry pool shared by every matchweek deployed through this factory.
    CarryPool public immutable CARRY_POOL;

    /// @notice Standalone treasury shared by every matchweek deployed through this factory.
    Treasury public immutable TREASURY;

    /// @notice Deployed Matchweek address for a given matchweekId.
    mapping(uint32 matchweekId => address matchweek) public matchweeks;

    /// @notice All Matchweek addresses deployed by this factory, in deployment order.
    address[] public deployedMatchweeks;

    /// @notice Emitted when a new Matchweek clone is deployed and initialized.
    /// @param matchweek   Address of the newly deployed Matchweek clone.
    /// @param matchweekId Unique identifier for this matchweek.
    event MatchweekDeployed(address indexed matchweek, uint32 indexed matchweekId);

    /// @notice Deploys the Matchweek implementation and sets the factory owner.
    /// @param admin       Address that becomes the owner of this factory.
    /// @param stablecoin  ERC20 token accepted as stake for predictions, shared by every matchweek.
    /// @param carryPool   Standalone carry pool shared by every matchweek deployed through this
    ///                    factory. Its owner must call `carryPool.setFactory(address(this))`
    ///                    after this factory is deployed, so it can register new matchweeks.
    /// @param treasury    Standalone treasury shared by every matchweek deployed through this
    ///                    factory. Its owner must call `treasury.setFactory(address(this))`
    ///                    after this factory is deployed, so it can register new matchweeks.
    constructor(address admin, IERC20 stablecoin, CarryPool carryPool, Treasury treasury) Ownable(admin) {
        CARRY_POOL = carryPool;
        TREASURY = treasury;
        IMPLEMENTATION = address(new Matchweek(stablecoin, carryPool, treasury));
    }

    /// @notice Deploys and initializes a new Matchweek instance.
    /// @dev Reverts if called by anyone other than the owner, or if the underlying
    ///      {Matchweek.initialize} call reverts.
    /// @param matchweekId   Unique identifier for this matchweek.
    /// @param predictionDeadline Timestamp after which no more predictions are accepted.
    /// @param matches       Exactly 10 matches.
    /// @param admin         Address that becomes the owner of the new Matchweek instance.
    /// @return matchweek Address of the newly deployed Matchweek clone.
    function createMatchweek(
        uint32 matchweekId,
        uint40 predictionDeadline,
        Matchweek.Match[] calldata matches,
        address admin
    ) external onlyOwner returns (address matchweek) {
        matchweek = Clones.clone(IMPLEMENTATION);
        Matchweek(matchweek).initialize(matchweekId, predictionDeadline, matches, admin);
        CARRY_POOL.registerMatchweek(matchweek);
        TREASURY.registerMatchweek(matchweek);

        matchweeks[matchweekId] = matchweek;
        deployedMatchweeks.push(matchweek);

        emit MatchweekDeployed(matchweek, matchweekId);
    }
}
