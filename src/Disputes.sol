// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {DisputeConfig} from "./DisputeConfig.sol";
import {Matchweek} from "./Matchweek.sol";
import {Treasury} from "./Treasury.sol";

/// @title Disputes
/// @author PitchMkt
/// @notice Standalone contract that runs the post-publication dispute window for every
///         matchweek: anyone can challenge published results within the window by posting a
///         bond, and the admin resolves the challenge by either correcting the results or
///         rejecting the dispute.
/// @dev Deployed once and shared by every {Matchweek} instance, the same way {CarryPool} and
///      {Treasury} are. Opening the dispute window and reading its resolution are restricted to
///      matchweeks registered by {factory}; resolving a dispute is restricted to the owner, the
///      same admin multi-sig that publishes results in the first place.
contract Disputes is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Tracks a single challenge against a matchweek's published results.
    struct Dispute {
        address challenger;
        uint256 bond;
        uint40 openedAt;
        bool resolved;
    }

    /// @notice ERC20 token accepted as the dispute bond, matching every registered matchweek's
    ///         stablecoin.
    IERC20 public immutable STABLECOIN;

    /// @notice Treasury that receives forfeited bonds from rejected disputes.
    Treasury public immutable TREASURY;

    /// @notice PitchMkt allowed to register matchweeks via {registerMatchweek}.
    /// @dev Settable once by the owner, after both this contract and the factory are deployed.
    address public factory;

    /// @notice Whether an address is a matchweek authorized to call {openDisputeWindow}.
    mapping(address matchweek => bool) public isMatchweek;

    /// @notice Timestamp after which a matchweek's results can no longer be disputed.
    /// @dev Zero means the dispute window was never opened for that matchweek.
    mapping(address matchweek => uint40) public disputeDeadline;

    /// @notice The current (or most recent) dispute opened against a matchweek.
    mapping(address matchweek => Dispute) public disputes;

    /// @notice Whether a matchweek's predictions were refunded after the admin failed to resolve
    ///         an open dispute within {DisputeConfig.RESOLUTION_TIMEOUT}.
    /// @dev Once set, permanent: folded into {isSettled} so {Matchweek.commitDistribution} can
    ///      never unblock again, and read directly by {Matchweek.claimRefund} to gate refunds.
    mapping(address matchweek => bool) public refunded;

    /// @notice Emitted when the owner sets the factory allowed to register matchweeks.
    /// @param factory Address of the PitchMkt.
    event FactorySet(address indexed factory);

    /// @notice Emitted when the factory registers a newly deployed matchweek.
    /// @param matchweek Address of the registered matchweek.
    event MatchweekRegistered(address indexed matchweek);

    /// @notice Emitted when a matchweek opens its dispute window after publishing results.
    /// @param matchweek Address of the matchweek.
    /// @param deadline  Timestamp after which the results can no longer be disputed.
    event DisputeWindowOpened(address indexed matchweek, uint40 deadline);

    /// @notice Emitted when a challenger disputes a matchweek's published results.
    /// @param matchweek    Address of the disputed matchweek.
    /// @param challenger   Address that opened the dispute.
    /// @param bond         Stablecoin bond posted by the challenger.
    /// @param evidenceHash Off-chain reference (e.g. hash of a link to the official source)
    ///                     backing the challenge. Not validated on-chain.
    event ResultsDisputed(address indexed matchweek, address indexed challenger, uint256 bond, bytes32 evidenceHash);

    /// @notice Emitted when the owner confirms a dispute as valid.
    /// @param matchweek        Address of the matchweek.
    /// @param challenger       Address that opened the dispute.
    /// @param correctedOutcomes The corrected ten outcomes applied to the matchweek.
    event DisputeConfirmed(address indexed matchweek, address indexed challenger, uint8[10] correctedOutcomes);

    /// @notice Emitted when the owner rejects a dispute as invalid.
    /// @param matchweek  Address of the matchweek.
    /// @param challenger Address that opened the dispute.
    /// @param bond       Stablecoin bond forfeited to the treasury.
    event DisputeRejected(address indexed matchweek, address indexed challenger, uint256 bond);

    /// @notice Emitted when anyone triggers a refund after the admin failed to resolve a dispute
    ///         within {DisputeConfig.RESOLUTION_TIMEOUT}.
    /// @param matchweek  Address of the matchweek.
    /// @param challenger Address that opened the dispute and receives its bond back.
    /// @param bond       Stablecoin bond returned to the challenger — the timeout is the admin's
    ///                   fault, not theirs.
    event RefundedAfterTimeout(address indexed matchweek, address indexed challenger, uint256 bond);

    /// @notice Thrown if the constructor is given the zero address as the stablecoin.
    error InvalidStablecoin();

    /// @notice Thrown if the constructor is given the zero address as the treasury.
    error InvalidTreasury();

    /// @notice Thrown if {setFactory} is called after the factory has already been set.
    error FactoryAlreadySet();

    /// @notice Thrown if {registerMatchweek} is called by any account other than {factory}.
    error NotFactory();

    /// @notice Thrown if {openDisputeWindow} is called by an unregistered address.
    error NotMatchweek();

    /// @notice Thrown if {disputeResults} is called for a matchweek with no open dispute window.
    error DisputeWindowNotOpen();

    /// @notice Thrown if {disputeResults} is called after the matchweek's dispute deadline.
    error DisputeWindowClosed();

    /// @notice Thrown if {disputeResults} is called while a dispute is already open for that
    ///         matchweek.
    error DisputeAlreadyOpen();

    /// @notice Thrown if {confirmDispute} or {rejectDispute} is called for a matchweek with no
    ///         open dispute.
    error NoActiveDispute();

    /// @notice Thrown if {confirmDispute} or {rejectDispute} is called for a dispute that has
    ///         already been resolved.
    error DisputeAlreadyResolved();

    /// @notice Thrown if {refundAfterTimeout} is called before {DisputeConfig.RESOLUTION_TIMEOUT}
    ///         has elapsed since the dispute was opened.
    error ResolutionNotTimedOut();

    modifier onlyFactory() {
        _onlyFactory();
        _;
    }

    modifier onlyMatchweek() {
        _onlyMatchweek();
        _;
    }

    /// @notice Sets the stablecoin, the treasury and the owner that resolves disputes.
    /// @param admin       Address that becomes the owner of this contract.
    /// @param stablecoin_ ERC20 token accepted as the dispute bond.
    /// @param treasury_   Treasury that receives forfeited bonds from rejected disputes.
    constructor(address admin, IERC20 stablecoin_, Treasury treasury_) Ownable(admin) {
        if (address(stablecoin_) == address(0)) revert InvalidStablecoin();
        if (address(treasury_) == address(0)) revert InvalidTreasury();
        STABLECOIN = stablecoin_;
        TREASURY = treasury_;
    }

    /// @notice Sets the PitchMkt allowed to register matchweeks.
    /// @dev Reverts if called by anyone other than the owner, or if already set.
    /// @param factory_ Address of the PitchMkt.
    function setFactory(address factory_) external onlyOwner {
        if (factory != address(0)) revert FactoryAlreadySet();
        factory = factory_;
        emit FactorySet(factory_);
    }

    /// @notice Registers a newly deployed matchweek, authorizing it to call {openDisputeWindow}.
    /// @dev Reverts if called by anyone other than {factory}.
    /// @param matchweek Address of the matchweek to register.
    function registerMatchweek(address matchweek) external onlyFactory {
        isMatchweek[matchweek] = true;
        emit MatchweekRegistered(matchweek);
    }

    /// @notice Opens the dispute window for the calling matchweek.
    /// @dev Reverts if called by an unregistered address. Meant to be called once, from
    ///      {Matchweek.publishResults}, right after outcomes are published.
    function openDisputeWindow() external onlyMatchweek {
        uint40 deadline = uint40(block.timestamp) + DisputeConfig.DISPUTE_WINDOW;
        disputeDeadline[msg.sender] = deadline;
        emit DisputeWindowOpened(msg.sender, deadline);
    }

    /// @notice Opens a dispute against a matchweek's published results, posting the fixed bond.
    /// @dev Reverts if the matchweek's dispute window was never opened, has already closed, or
    ///      already has an active dispute. Pulls {DisputeConfig.DISPUTE_BOND} from the caller via
    ///      `transferFrom`, which requires prior `approve`.
    /// @param matchweek    Address of the matchweek being disputed.
    /// @param evidenceHash Off-chain reference backing the challenge, not validated on-chain.
    function disputeResults(address matchweek, bytes32 evidenceHash) external nonReentrant {
        uint40 deadline = disputeDeadline[matchweek];
        if (deadline == 0) revert DisputeWindowNotOpen();
        if (block.timestamp >= deadline) revert DisputeWindowClosed();
        if (disputes[matchweek].challenger != address(0)) revert DisputeAlreadyOpen();

        uint256 bond = DisputeConfig.DISPUTE_BOND;
        disputes[matchweek] =
            Dispute({challenger: msg.sender, bond: bond, openedAt: uint40(block.timestamp), resolved: false});

        emit ResultsDisputed(matchweek, msg.sender, bond, evidenceHash);

        STABLECOIN.safeTransferFrom(msg.sender, address(this), bond);
    }

    /// @notice Confirms a dispute as valid: corrects the matchweek's results and refunds the bond.
    /// @dev Reverts if called by anyone other than the owner, or if there is no active,
    ///      unresolved dispute for `matchweek`.
    /// @param matchweek         Address of the disputed matchweek.
    /// @param correctedOutcomes The corrected ten outcomes (0=home, 1=draw, 2=away).
    function confirmDispute(address matchweek, uint8[10] calldata correctedOutcomes) external nonReentrant onlyOwner {
        Dispute memory d = _activeDispute(matchweek);
        disputes[matchweek].resolved = true;

        emit DisputeConfirmed(matchweek, d.challenger, correctedOutcomes);

        Matchweek(matchweek).applyDisputeCorrection(correctedOutcomes);
        STABLECOIN.safeTransfer(d.challenger, d.bond);
    }

    /// @notice Rejects a dispute as invalid: the original results stand and the bond is
    ///         forfeited to the treasury as spam prevention.
    /// @dev Reverts if called by anyone other than the owner, or if there is no active,
    ///      unresolved dispute for `matchweek`.
    /// @param matchweek Address of the disputed matchweek.
    function rejectDispute(address matchweek) external nonReentrant onlyOwner {
        Dispute memory d = _activeDispute(matchweek);
        disputes[matchweek].resolved = true;
        uint32 matchweekId = Matchweek(matchweek).matchweekId();

        emit DisputeRejected(matchweek, d.challenger, d.bond);

        STABLECOIN.safeTransfer(address(TREASURY), d.bond);
        TREASURY.depositForfeitedBond(matchweekId, d.bond);
    }

    /// @notice Refunds the challenger's bond after the admin fails to resolve an open dispute
    ///         within {DisputeConfig.RESOLUTION_TIMEOUT}, and permanently marks the matchweek
    ///         refunded so {Matchweek.commitDistribution} can never unblock and predictions become
    ///         claimable via {Matchweek.claimRefund}.
    /// @dev Callable by anyone — the timeout is the admin's fault, not the challenger's, so no
    ///      permission is required to unstick the funds. Reverts if there is no active,
    ///      unresolved dispute for `matchweek`, or if {DisputeConfig.RESOLUTION_TIMEOUT} has not
    ///      yet elapsed since it was opened.
    /// @param matchweek Address of the matchweek whose dispute timed out.
    function refundAfterTimeout(address matchweek) external nonReentrant {
        Dispute memory d = _activeDispute(matchweek);
        if (block.timestamp < d.openedAt + DisputeConfig.RESOLUTION_TIMEOUT) revert ResolutionNotTimedOut();

        disputes[matchweek].resolved = true;
        refunded[matchweek] = true;

        emit RefundedAfterTimeout(matchweek, d.challenger, d.bond);

        STABLECOIN.safeTransfer(d.challenger, d.bond);
    }

    /// @notice Returns whether a matchweek is clear to distribute prizes: its dispute window has
    ///         closed and it has no unresolved dispute.
    /// @dev Returns false if the dispute window was never opened (results not published yet), or
    ///      permanently once {refundAfterTimeout} has marked the matchweek refunded.
    /// @param matchweek Address of the matchweek.
    /// @return True if the matchweek is settled.
    function isSettled(address matchweek) external view returns (bool) {
        if (refunded[matchweek]) return false;

        uint40 deadline = disputeDeadline[matchweek];
        if (deadline == 0 || block.timestamp < deadline) return false;

        Dispute memory d = disputes[matchweek];
        return d.challenger == address(0) || d.resolved;
    }

    function _onlyFactory() internal view {
        if (msg.sender != factory) revert NotFactory();
    }

    function _onlyMatchweek() internal view {
        if (!isMatchweek[msg.sender]) revert NotMatchweek();
    }

    /// @dev Returns the active, unresolved dispute for `matchweek`. Reverts if there is none or
    ///      it was already resolved. Read-only: callers are responsible for marking it resolved,
    ///      so this can't be mistaken for a no-op getter when it actually has a side effect.
    function _activeDispute(address matchweek) private view returns (Dispute memory d) {
        d = disputes[matchweek];
        if (d.challenger == address(0)) revert NoActiveDispute();
        if (d.resolved) revert DisputeAlreadyResolved();
    }
}
