// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Treasury} from "../src/Treasury.sol";

/// @dev Recipient that rejects native transfers, to exercise {Treasury.NativeTransferFailed}.
contract RejectsNative {
    receive() external payable {
        revert("no thanks");
    }
}

contract TreasuryTest is Test {
    address constant ADMIN = address(0xAD);
    address constant FACTORY = address(0xFAC);
    address constant MATCHWEEK_A = address(0xAAA1);
    address constant MATCHWEEK_B = address(0xAAA2);
    address constant DONOR = address(0xD00);
    address constant RECIPIENT = address(0x0F5);
    address constant STRANGER = address(0xBAD);

    uint32 constant MATCHWEEK_ID_A = 1;
    uint32 constant MATCHWEEK_ID_B = 2;

    Treasury public treasury;
    ERC20Mock public stablecoin;

    function setUp() public {
        stablecoin = new ERC20Mock();
        treasury = new Treasury(ADMIN, stablecoin);

        vm.prank(ADMIN);
        treasury.setFactory(FACTORY);

        vm.prank(FACTORY);
        treasury.registerMatchweek(MATCHWEEK_A);
        vm.prank(FACTORY);
        treasury.registerMatchweek(MATCHWEEK_B);
    }

    function testRevert_stablecoinIsZeroAddress() public {
        vm.expectRevert(Treasury.InvalidStablecoin.selector);
        new Treasury(ADMIN, ERC20Mock(address(0)));
    }

    ////
    /// setFactory / registerMatchweek Tests
    ////

    function test_setFactory() public view {
        assertEq(treasury.factory(), FACTORY);
    }

    function testRevert_setFactory_alreadySet() public {
        vm.expectRevert(Treasury.FactoryAlreadySet.selector);
        vm.prank(ADMIN);
        treasury.setFactory(STRANGER);
    }

    function testRevert_setFactory_notOwner() public {
        Treasury fresh = new Treasury(ADMIN, stablecoin);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, STRANGER));
        vm.prank(STRANGER);
        fresh.setFactory(FACTORY);
    }

    function test_registerMatchweek() public view {
        assertEq(treasury.isMatchweek(MATCHWEEK_A), true);
        assertEq(treasury.isMatchweek(MATCHWEEK_B), true);
        assertEq(treasury.isMatchweek(STRANGER), false);
    }

    function testRevert_registerMatchweek_notFactory() public {
        vm.expectRevert(Treasury.NotFactory.selector);
        vm.prank(STRANGER);
        treasury.registerMatchweek(STRANGER);
    }

    ////
    /// deposit Tests
    ////

    function test_deposit_accumulatesAcrossMatchweeks() public {
        stablecoin.mint(address(treasury), 100);
        vm.prank(MATCHWEEK_A);
        treasury.deposit(MATCHWEEK_ID_A, 100);
        assertEq(treasury.collectedBalance(), 100);

        stablecoin.mint(address(treasury), 50);
        vm.prank(MATCHWEEK_B);
        treasury.deposit(MATCHWEEK_ID_B, 50);
        assertEq(treasury.collectedBalance(), 150);
    }

    function test_deposit_tracksPerMatchweek() public {
        stablecoin.mint(address(treasury), 150);
        vm.prank(MATCHWEEK_A);
        treasury.deposit(MATCHWEEK_ID_A, 100);
        vm.prank(MATCHWEEK_B);
        treasury.deposit(MATCHWEEK_ID_B, 50);

        assertEq(treasury.collectedByMatchweek(MATCHWEEK_ID_A), 100);
        assertEq(treasury.collectedByMatchweek(MATCHWEEK_ID_B), 50);
    }

    function test_deposit_emitsTreasuryFunded() public {
        vm.expectEmit(true, false, false, true);
        emit Treasury.TreasuryFunded(MATCHWEEK_ID_A, 100, 100);
        vm.prank(MATCHWEEK_A);
        treasury.deposit(MATCHWEEK_ID_A, 100);
    }

    function testRevert_deposit_notMatchweek() public {
        vm.expectRevert(Treasury.NotMatchweek.selector);
        vm.prank(STRANGER);
        treasury.deposit(MATCHWEEK_ID_A, 100);
    }

    ////
    /// donate Tests
    ////

    function test_donate_pullsFundsAndCredits() public {
        stablecoin.mint(DONOR, 100);
        vm.prank(DONOR);
        stablecoin.approve(address(treasury), 100);

        vm.prank(DONOR);
        treasury.donate(100);

        assertEq(treasury.totalDonated(), 100);
        assertEq(treasury.collectedBalance(), 100);
        assertEq(stablecoin.balanceOf(address(treasury)), 100);
        assertEq(stablecoin.balanceOf(DONOR), 0);
    }

    function test_donate_fromStranger() public {
        // Donating is open to everyone — no factory, matchweek or owner role required.
        stablecoin.mint(STRANGER, 40);
        vm.prank(STRANGER);
        stablecoin.approve(address(treasury), 40);

        vm.prank(STRANGER);
        treasury.donate(40);

        assertEq(treasury.collectedBalance(), 40);
    }

    function test_donate_emitsDonated() public {
        stablecoin.mint(DONOR, 100);
        vm.prank(DONOR);
        stablecoin.approve(address(treasury), 100);

        vm.expectEmit(true, false, false, true);
        emit Treasury.Donated(DONOR, 100, 100);
        vm.prank(DONOR);
        treasury.donate(100);
    }

    function test_donate_addsToFeeRevenueButTrackedSeparately() public {
        stablecoin.mint(address(treasury), 100);
        vm.prank(MATCHWEEK_A);
        treasury.deposit(MATCHWEEK_ID_A, 100);

        stablecoin.mint(DONOR, 25);
        vm.prank(DONOR);
        stablecoin.approve(address(treasury), 25);
        vm.prank(DONOR);
        treasury.donate(25);

        assertEq(treasury.collectedBalance(), 125);
        assertEq(treasury.totalDonated(), 25);
        assertEq(treasury.collectedByMatchweek(MATCHWEEK_ID_A), 100);
    }

    function testRevert_donate_zeroAmount() public {
        vm.expectRevert(Treasury.ZeroAmount.selector);
        vm.prank(DONOR);
        treasury.donate(0);
    }

    function testRevert_donate_insufficientAllowance() public {
        stablecoin.mint(DONOR, 100);
        vm.prank(DONOR);
        vm.expectRevert();
        treasury.donate(100);
    }

    ////
    /// Native (HYPE) Donation Tests
    ////

    function test_receive_creditsNativeDonation() public {
        vm.deal(DONOR, 1 ether);
        vm.prank(DONOR);
        (bool ok,) = address(treasury).call{value: 1 ether}("");

        assertEq(ok, true);
        assertEq(treasury.totalDonatedNative(), 1 ether);
        assertEq(address(treasury).balance, 1 ether);
    }

    function test_receive_emitsNativeDonated() public {
        vm.deal(DONOR, 1 ether);

        vm.expectEmit(true, false, false, true);
        emit Treasury.NativeDonated(DONOR, 1 ether, 1 ether);
        vm.prank(DONOR);
        (bool ok,) = address(treasury).call{value: 1 ether}("");
        assertEq(ok, true);
    }

    /// @dev Native donations must never inflate the stablecoin ledger.
    function test_receive_doesNotAffectStablecoinBalance() public {
        vm.deal(DONOR, 1 ether);
        vm.prank(DONOR);
        (bool ok,) = address(treasury).call{value: 1 ether}("");

        assertEq(ok, true);
        assertEq(treasury.collectedBalance(), 0);
        assertEq(treasury.totalDonated(), 0);
    }

    function testRevert_receive_zeroValue() public {
        vm.prank(DONOR);
        (bool ok,) = address(treasury).call{value: 0}("");
        assertEq(ok, false);
    }

    function test_withdrawNative_transfersToRecipient() public {
        vm.deal(DONOR, 1 ether);
        vm.prank(DONOR);
        (bool ok,) = address(treasury).call{value: 1 ether}("");
        assertEq(ok, true);

        vm.prank(ADMIN);
        treasury.withdrawNative(RECIPIENT, 0.6 ether);

        assertEq(RECIPIENT.balance, 0.6 ether);
        assertEq(address(treasury).balance, 0.4 ether);
    }

    function test_withdrawNative_emitsNativeWithdrawn() public {
        vm.deal(DONOR, 1 ether);
        vm.prank(DONOR);
        (bool ok,) = address(treasury).call{value: 1 ether}("");
        assertEq(ok, true);

        vm.expectEmit(true, false, false, true);
        emit Treasury.NativeWithdrawn(RECIPIENT, 0.6 ether, 0.4 ether);
        vm.prank(ADMIN);
        treasury.withdrawNative(RECIPIENT, 0.6 ether);
    }

    function testRevert_withdrawNative_notOwner() public {
        vm.deal(address(treasury), 1 ether);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, STRANGER));
        vm.prank(STRANGER);
        treasury.withdrawNative(STRANGER, 1 ether);
    }

    function testRevert_withdrawNative_insufficientBalance() public {
        vm.deal(address(treasury), 1 ether);

        vm.expectRevert(abi.encodeWithSelector(Treasury.InsufficientNativeBalance.selector, 2 ether, 1 ether));
        vm.prank(ADMIN);
        treasury.withdrawNative(RECIPIENT, 2 ether);
    }

    function testRevert_withdrawNative_zeroRecipient() public {
        vm.deal(address(treasury), 1 ether);

        vm.expectRevert(Treasury.InvalidRecipient.selector);
        vm.prank(ADMIN);
        treasury.withdrawNative(address(0), 1 ether);
    }

    function testRevert_withdrawNative_recipientRejects() public {
        vm.deal(address(treasury), 1 ether);
        RejectsNative rejector = new RejectsNative();

        vm.expectRevert(Treasury.NativeTransferFailed.selector);
        vm.prank(ADMIN);
        treasury.withdrawNative(address(rejector), 1 ether);
    }

    ////
    /// withdraw Tests
    ////

    function test_withdraw_transfersToRecipient() public {
        stablecoin.mint(address(treasury), 100);
        vm.prank(MATCHWEEK_A);
        treasury.deposit(MATCHWEEK_ID_A, 100);

        vm.prank(ADMIN);
        treasury.withdraw(RECIPIENT, 60);

        assertEq(treasury.collectedBalance(), 40);
        assertEq(stablecoin.balanceOf(RECIPIENT), 60);
        assertEq(stablecoin.balanceOf(address(treasury)), 40);
    }

    function test_withdraw_donatedFunds() public {
        stablecoin.mint(DONOR, 100);
        vm.prank(DONOR);
        stablecoin.approve(address(treasury), 100);
        vm.prank(DONOR);
        treasury.donate(100);

        vm.prank(ADMIN);
        treasury.withdraw(RECIPIENT, 100);

        assertEq(treasury.collectedBalance(), 0);
        assertEq(stablecoin.balanceOf(RECIPIENT), 100);
    }

    function test_withdraw_emitsTreasuryWithdrawn() public {
        stablecoin.mint(address(treasury), 100);
        vm.prank(MATCHWEEK_A);
        treasury.deposit(MATCHWEEK_ID_A, 100);

        vm.expectEmit(true, false, false, true);
        emit Treasury.TreasuryWithdrawn(RECIPIENT, 60, 40);
        vm.prank(ADMIN);
        treasury.withdraw(RECIPIENT, 60);
    }

    function testRevert_withdraw_notOwner() public {
        stablecoin.mint(address(treasury), 100);
        vm.prank(MATCHWEEK_A);
        treasury.deposit(MATCHWEEK_ID_A, 100);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, STRANGER));
        vm.prank(STRANGER);
        treasury.withdraw(STRANGER, 100);
    }

    function testRevert_withdraw_insufficientBalance() public {
        stablecoin.mint(address(treasury), 100);
        vm.prank(MATCHWEEK_A);
        treasury.deposit(MATCHWEEK_ID_A, 100);

        vm.expectRevert(abi.encodeWithSelector(Treasury.InsufficientBalance.selector, uint256(101), uint256(100)));
        vm.prank(ADMIN);
        treasury.withdraw(RECIPIENT, 101);
    }

    /// @dev Tokens sent directly to the treasury are not credited, so they are not withdrawable.
    function testRevert_withdraw_untrackedTokens() public {
        stablecoin.mint(address(treasury), 100);

        vm.expectRevert(abi.encodeWithSelector(Treasury.InsufficientBalance.selector, uint256(100), uint256(0)));
        vm.prank(ADMIN);
        treasury.withdraw(RECIPIENT, 100);
    }

    function testRevert_withdraw_zeroRecipient() public {
        stablecoin.mint(address(treasury), 100);
        vm.prank(MATCHWEEK_A);
        treasury.deposit(MATCHWEEK_ID_A, 100);

        vm.expectRevert(Treasury.InvalidRecipient.selector);
        vm.prank(ADMIN);
        treasury.withdraw(address(0), 100);
    }
}
