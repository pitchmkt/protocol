// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Treasury
/// @author PitchMkt
/// @notice Standalone contract that accumulates the protocol fee retained from every matchweek,
///         accepts donations from anyone in either stablecoin or native currency (HYPE), and lets
///         the owner withdraw the balance to fund platform operations and protocol development.
/// @dev Deployed once and shared by every {Matchweek} instance, the same way {CarryPool} is.
///      Fee deposits are restricted to matchweeks registered by {factory} and withdrawals to the
///      owner, but {donate} and the {receive} fallback are deliberately open to everyone.
///      Stablecoin and native balances are accounted separately and never mixed.
///      Kept separate from {CarryPool} because the carry pool must only ever hold unawarded
///      prize money, never fee revenue.
contract Treasury is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice ERC20 token accepted as stake, matching every registered matchweek's stablecoin.
    IERC20 public immutable STABLECOIN;

    /// @notice PitchMkt allowed to register matchweeks via {registerMatchweek}.
    /// @dev Settable once by the owner, after both this contract and the factory are deployed.
    address public factory;

    /// @notice Whether an address is a matchweek authorized to call {deposit}.
    mapping(address matchweek => bool) public isMatchweek;

    /// @notice Fee collected from a given matchweekId.
    mapping(uint32 matchweekId => uint256 amount) public collectedByMatchweek;

    /// @notice Total stablecoin held by the treasury and available to withdraw, from both
    ///         protocol fees and donations.
    uint256 public collectedBalance;

    /// @notice Total stablecoin donated to the treasury by third parties, tracked separately from
    ///         fee revenue.
    uint256 public totalDonated;

    /// @notice Total native currency (HYPE) donated to the treasury.
    /// @dev Native donations are accounted separately from {collectedBalance} because that balance
    ///      is denominated in {STABLECOIN}. Mixing the two would let {withdraw} promise stablecoin
    ///      the treasury does not hold.
    uint256 public totalDonatedNative;

    /// @notice Emitted when the owner sets the factory allowed to register matchweeks.
    /// @param factory Address of the PitchMkt.
    event FactorySet(address indexed factory);

    /// @notice Emitted when the factory registers a newly deployed matchweek.
    /// @param matchweek Address of the registered matchweek.
    event MatchweekRegistered(address indexed matchweek);

    /// @notice Emitted when a matchweek deposits its protocol fee.
    /// @param matchweekId      Unique identifier of the depositing matchweek.
    /// @param amount           Amount added to the treasury.
    /// @param collectedBalance Total treasury balance after this deposit.
    event TreasuryFunded(uint32 indexed matchweekId, uint256 amount, uint256 collectedBalance);

    /// @notice Emitted when anyone donates stablecoin to the treasury.
    /// @param donor            Address that sent the donation.
    /// @param amount           Amount donated.
    /// @param collectedBalance Total treasury balance after this donation.
    event Donated(address indexed donor, uint256 amount, uint256 collectedBalance);

    /// @notice Emitted when anyone donates native currency (HYPE) to the treasury.
    /// @param donor       Address that sent the donation.
    /// @param amount      Amount donated, in wei.
    /// @param totalNative Total native balance held by the treasury after this donation.
    event NativeDonated(address indexed donor, uint256 amount, uint256 totalNative);

    /// @notice Emitted when the owner withdraws native currency (HYPE).
    /// @param to          Address that received the withdrawal.
    /// @param amount      Amount withdrawn, in wei.
    /// @param totalNative Total native balance held by the treasury after this withdrawal.
    event NativeWithdrawn(address indexed to, uint256 amount, uint256 totalNative);

    /// @notice Emitted when the owner withdraws collected fees.
    /// @param to               Address that received the withdrawal.
    /// @param amount           Amount withdrawn.
    /// @param collectedBalance Total treasury balance after this withdrawal.
    event TreasuryWithdrawn(address indexed to, uint256 amount, uint256 collectedBalance);

    /// @notice Thrown if the constructor is given the zero address as the stablecoin.
    error InvalidStablecoin();

    /// @notice Thrown if {setFactory} is called after the factory has already been set.
    error FactoryAlreadySet();

    /// @notice Thrown if {registerMatchweek} is called by any account other than {factory}.
    error NotFactory();

    /// @notice Thrown if {deposit} is called by an unregistered address.
    error NotMatchweek();

    /// @notice Thrown if {withdraw} is given the zero address as the recipient.
    error InvalidRecipient();

    /// @notice Thrown if {donate} or a native donation is made with a zero amount.
    error ZeroAmount();

    /// @notice Thrown if a native withdrawal exceeds the treasury's native balance.
    error InsufficientNativeBalance(uint256 requested, uint256 available);

    /// @notice Thrown if a native withdrawal fails because the recipient rejected the transfer.
    error NativeTransferFailed();

    /// @notice Thrown if {withdraw} is called for more than {collectedBalance}.
    error InsufficientBalance(uint256 requested, uint256 available);

    modifier onlyFactory() {
        _onlyFactory();
        _;
    }

    modifier onlyMatchweek() {
        _onlyMatchweek();
        _;
    }

    /// @notice Sets the stablecoin shared by every matchweek and the treasury owner.
    /// @param admin       Address that becomes the owner of this contract.
    /// @param stablecoin_ ERC20 token accepted as stake for predictions.
    constructor(address admin, IERC20 stablecoin_) Ownable(admin) {
        if (address(stablecoin_) == address(0)) revert InvalidStablecoin();
        STABLECOIN = stablecoin_;
    }

    /// @notice Accepts native currency (HYPE) sent directly to the treasury as a donation.
    /// @dev Deliberately open, so a plain transfer with no calldata works as a donation without
    ///      the donor needing to call a function. Accounted in {totalDonatedNative} only — never
    ///      in {collectedBalance}, which is denominated in {STABLECOIN}. Withdrawn via
    ///      {withdrawNative}.
    receive() external payable {
        if (msg.value == 0) revert ZeroAmount();

        totalDonatedNative += msg.value;

        emit NativeDonated(msg.sender, msg.value, address(this).balance);
    }

    /// @notice Sets the PitchMkt allowed to register matchweeks.
    /// @dev Reverts if called by anyone other than the owner, or if already set.
    /// @param factory_ Address of the PitchMkt.
    function setFactory(address factory_) external onlyOwner {
        if (factory != address(0)) revert FactoryAlreadySet();
        factory = factory_;
        emit FactorySet(factory_);
    }

    /// @notice Registers a newly deployed matchweek, authorizing it to call {deposit}.
    /// @dev Reverts if called by anyone other than {factory}.
    /// @param matchweek Address of the matchweek to register.
    function registerMatchweek(address matchweek) external onlyFactory {
        isMatchweek[matchweek] = true;
        emit MatchweekRegistered(matchweek);
    }

    /// @notice Records the protocol fee that a matchweek has transferred into the treasury.
    /// @dev Reverts if called by an unregistered address. The caller must transfer `amount`
    ///      STABLECOIN to this contract before calling; this function only updates accounting.
    /// @param matchweekId Unique identifier of the depositing matchweek.
    /// @param amount      Amount of stablecoin already transferred to this contract.
    function deposit(uint32 matchweekId, uint256 amount) external onlyMatchweek {
        collectedByMatchweek[matchweekId] += amount;
        collectedBalance += amount;
        emit TreasuryFunded(matchweekId, amount, collectedBalance);
    }

    /// @notice Donates stablecoin to the treasury, from any address.
    /// @dev Open to everyone by design, so supporters can fund platform operations directly.
    ///      Unlike {deposit}, this pulls the tokens itself via `transferFrom`, which requires prior
    ///      `approve`. Accounting can therefore never be credited without the funds actually
    ///      arriving — the reason donations do not reuse the matchweek-only {deposit} path.
    /// @param amount Amount of stablecoin to donate.
    function donate(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        totalDonated += amount;
        collectedBalance += amount;

        emit Donated(msg.sender, amount, collectedBalance);

        STABLECOIN.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice Withdraws collected fees to an arbitrary recipient.
    /// @dev Reverts if called by anyone other than the owner, if `to` is the zero address, or if
    ///      `amount` exceeds {collectedBalance}. Withdrawing is capped by the accounted balance
    ///      rather than the raw token balance, so tokens sent here directly are not withdrawable.
    /// @param to     Address that receives the withdrawn fees.
    /// @param amount Amount of stablecoin to withdraw.
    function withdraw(address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert InvalidRecipient();
        if (amount > collectedBalance) revert InsufficientBalance(amount, collectedBalance);

        collectedBalance -= amount;

        emit TreasuryWithdrawn(to, amount, collectedBalance);

        STABLECOIN.safeTransfer(to, amount);
    }

    /// @notice Withdraws donated native currency (HYPE) to an arbitrary recipient.
    /// @dev Reverts if called by anyone other than the owner, if `to` is the zero address, if
    ///      `amount` exceeds the treasury's native balance, or if the recipient rejects the
    ///      transfer. Capped by the raw native balance rather than {totalDonatedNative}, so
    ///      anything force-sent via `selfdestruct` is still recoverable.
    /// @param to     Address that receives the withdrawn native currency.
    /// @param amount Amount of native currency to withdraw, in wei.
    function withdrawNative(address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert InvalidRecipient();

        uint256 available = address(this).balance;
        if (amount > available) revert InsufficientNativeBalance(amount, available);

        emit NativeWithdrawn(to, amount, available - amount);

        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert NativeTransferFailed();
    }

    function _onlyFactory() internal view {
        if (msg.sender != factory) revert NotFactory();
    }

    function _onlyMatchweek() internal view {
        if (!isMatchweek[msg.sender]) revert NotMatchweek();
    }
}
