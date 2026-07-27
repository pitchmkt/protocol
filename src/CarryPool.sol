// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title CarryPool
/// @author PitchMkt
/// @notice Standalone contract that accumulates unallocated stake across every matchweek and
///         releases the accumulated balance to whichever matchweek reports a perfect-ten winner.
/// @dev Deployed once and shared by every {Matchweek} instance, the same way {Matchweek}'s
///      STABLECOIN is shared across clones. Funding and release are restricted to matchweeks
///      registered by {factory}.
contract CarryPool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice ERC20 token accepted as stake, matching every registered matchweek's stablecoin.
    IERC20 public immutable STABLECOIN;

    /// @notice PitchMkt allowed to register matchweeks via {registerMatchweek}.
    /// @dev Settable once by the owner, after both this contract and the factory are deployed.
    address public factory;

    /// @notice Whether an address is a matchweek authorized to call {fund} and {release}.
    mapping(address matchweek => bool) public isMatchweek;

    /// @notice Whether the carry pool has already been released for a given matchweekId.
    mapping(uint32 matchweekId => bool) public released;

    /// @notice Total stake currently held in the pool, awaiting release to a perfect-ten winner.
    uint256 public carriedBalance;

    /// @notice Emitted when the owner sets the factory allowed to register matchweeks.
    /// @param factory Address of the PitchMkt.
    event FactorySet(address indexed factory);

    /// @notice Emitted when the factory registers a newly deployed matchweek.
    /// @param matchweek Address of the registered matchweek.
    event MatchweekRegistered(address indexed matchweek);

    /// @notice Emitted when a matchweek funds the pool with its unallocated stake.
    /// @param matchweekId    Unique identifier of the funding matchweek.
    /// @param amount         Amount added to the pool.
    /// @param carriedBalance Total pool balance after this deposit.
    event CarryPoolFunded(uint32 indexed matchweekId, uint256 amount, uint256 carriedBalance);

    /// @notice Emitted when the pool is released to a matchweek with a perfect-ten winner.
    /// @param matchweekId Unique identifier of the receiving matchweek.
    /// @param matchweek   Address of the receiving matchweek.
    /// @param amount      Amount released.
    event CarryPoolReleased(uint32 indexed matchweekId, address indexed matchweek, uint256 amount);

    /// @notice Thrown if the constructor is given the zero address as the stablecoin.
    error InvalidStablecoin();

    /// @notice Thrown if {setFactory} is called after the factory has already been set.
    error FactoryAlreadySet();

    /// @notice Thrown if {registerMatchweek} is called by any account other than {factory}.
    error NotFactory();

    /// @notice Thrown if {fund} or {release} is called by an unregistered address.
    error NotMatchweek();

    /// @notice Thrown if {release} is called more than once for the same matchweekId.
    error AlreadyReleased(uint32 matchweekId);

    modifier onlyFactory() {
        if (msg.sender != factory) revert NotFactory();
        _;
    }

    modifier onlyMatchweek() {
        if (!isMatchweek[msg.sender]) revert NotMatchweek();
        _;
    }

    /// @notice Sets the stablecoin shared by every matchweek and the pool owner.
    /// @param admin       Address that becomes the owner of this contract.
    /// @param stablecoin_ ERC20 token accepted as stake for entries.
    constructor(address admin, IERC20 stablecoin_) Ownable(admin) {
        if (address(stablecoin_) == address(0)) revert InvalidStablecoin();
        STABLECOIN = stablecoin_;
    }

    /// @notice Sets the PitchMkt allowed to register matchweeks.
    /// @dev Reverts if called by anyone other than the owner, or if already set.
    /// @param factory_ Address of the PitchMkt.
    function setFactory(address factory_) external onlyOwner {
        if (factory != address(0)) revert FactoryAlreadySet();
        factory = factory_;
        emit FactorySet(factory_);
    }

    /// @notice Registers a newly deployed matchweek, authorizing it to call {fund} and {release}.
    /// @dev Reverts if called by anyone other than {factory}.
    /// @param matchweek Address of the matchweek to register.
    function registerMatchweek(address matchweek) external onlyFactory {
        isMatchweek[matchweek] = true;
        emit MatchweekRegistered(matchweek);
    }

    /// @notice Records stake that a matchweek has transferred into the pool.
    /// @dev Reverts if called by an unregistered address. The caller must transfer `amount`
    ///      STABLECOIN to this contract before calling; this function only updates accounting.
    /// @param matchweekId Unique identifier of the funding matchweek.
    /// @param amount      Amount of stablecoin already transferred to this contract.
    function fund(uint32 matchweekId, uint256 amount) external onlyMatchweek {
        carriedBalance += amount;
        emit CarryPoolFunded(matchweekId, amount, carriedBalance);
    }

    /// @notice Releases the entire accumulated pool to the calling matchweek.
    /// @dev Reverts if called by an unregistered address or if already released for this
    ///      matchweekId. Safe to call with an empty pool: transfers zero and still marks
    ///      the matchweekId as released.
    /// @param matchweekId Unique identifier of the receiving matchweek.
    /// @return amount Amount released to the caller.
    function release(uint32 matchweekId) external onlyMatchweek nonReentrant returns (uint256 amount) {
        if (released[matchweekId]) revert AlreadyReleased(matchweekId);

        released[matchweekId] = true;
        amount = carriedBalance;
        carriedBalance = 0;

        emit CarryPoolReleased(matchweekId, msg.sender, amount);

        if (amount > 0) {
            STABLECOIN.safeTransfer(msg.sender, amount);
        }
    }
}
