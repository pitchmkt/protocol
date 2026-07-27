// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {CarryPool} from "../src/CarryPool.sol";

contract CarryPoolTest is Test {
    address constant ADMIN = address(0xAD);
    address constant FACTORY = address(0xFAC);
    address constant MATCHWEEK_A = address(0xAAA1);
    address constant MATCHWEEK_B = address(0xAAA2);
    address constant STRANGER = address(0xBAD);

    uint32 constant MATCHWEEK_ID_A = 1;
    uint32 constant MATCHWEEK_ID_B = 2;

    CarryPool public carryPool;
    ERC20Mock public stablecoin;

    function setUp() public {
        stablecoin = new ERC20Mock();
        carryPool = new CarryPool(ADMIN, stablecoin);

        vm.prank(ADMIN);
        carryPool.setFactory(FACTORY);

        vm.prank(FACTORY);
        carryPool.registerMatchweek(MATCHWEEK_A);
        vm.prank(FACTORY);
        carryPool.registerMatchweek(MATCHWEEK_B);
    }

    function testRevert_stablecoinIsZeroAddress() public {
        vm.expectRevert(CarryPool.InvalidStablecoin.selector);
        new CarryPool(ADMIN, ERC20Mock(address(0)));
    }

    ////
    /// setFactory / registerMatchweek Tests
    ////

    function test_setFactory() public view {
        assertEq(carryPool.factory(), FACTORY);
    }

    function testRevert_setFactory_alreadySet() public {
        vm.expectRevert(CarryPool.FactoryAlreadySet.selector);
        vm.prank(ADMIN);
        carryPool.setFactory(STRANGER);
    }

    function testRevert_setFactory_notOwner() public {
        CarryPool fresh = new CarryPool(ADMIN, stablecoin);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, STRANGER));
        vm.prank(STRANGER);
        fresh.setFactory(FACTORY);
    }

    function test_registerMatchweek() public view {
        assertEq(carryPool.isMatchweek(MATCHWEEK_A), true);
        assertEq(carryPool.isMatchweek(MATCHWEEK_B), true);
        assertEq(carryPool.isMatchweek(STRANGER), false);
    }

    function testRevert_registerMatchweek_notFactory() public {
        vm.expectRevert(CarryPool.NotFactory.selector);
        vm.prank(STRANGER);
        carryPool.registerMatchweek(STRANGER);
    }

    ////
    /// fund Tests
    ////

    function test_fund_accumulatesAcrossMatchweeks() public {
        stablecoin.mint(address(carryPool), 100);
        vm.prank(MATCHWEEK_A);
        carryPool.fund(MATCHWEEK_ID_A, 100);
        assertEq(carryPool.carriedBalance(), 100);

        stablecoin.mint(address(carryPool), 50);
        vm.prank(MATCHWEEK_B);
        carryPool.fund(MATCHWEEK_ID_B, 50);
        assertEq(carryPool.carriedBalance(), 150);
    }

    function test_fund_emitsCarryPoolFunded() public {
        vm.expectEmit(true, false, false, true);
        emit CarryPool.CarryPoolFunded(MATCHWEEK_ID_A, 100, 100);
        vm.prank(MATCHWEEK_A);
        carryPool.fund(MATCHWEEK_ID_A, 100);
    }

    function testRevert_fund_notMatchweek() public {
        vm.expectRevert(CarryPool.NotMatchweek.selector);
        vm.prank(STRANGER);
        carryPool.fund(MATCHWEEK_ID_A, 100);
    }

    ////
    /// release Tests
    ////

    function test_release_transfersFullBalanceToCaller() public {
        stablecoin.mint(address(carryPool), 100);
        vm.prank(MATCHWEEK_A);
        carryPool.fund(MATCHWEEK_ID_A, 100);

        vm.prank(MATCHWEEK_B);
        uint256 released = carryPool.release(MATCHWEEK_ID_B);

        assertEq(released, 100);
        assertEq(carryPool.carriedBalance(), 0);
        assertEq(stablecoin.balanceOf(MATCHWEEK_B), 100);
        assertEq(stablecoin.balanceOf(address(carryPool)), 0);
    }

    function test_release_zeroBalance() public {
        vm.prank(MATCHWEEK_A);
        uint256 released = carryPool.release(MATCHWEEK_ID_A);

        assertEq(released, 0);
        assertEq(carryPool.released(MATCHWEEK_ID_A), true);
    }

    function test_release_emitsCarryPoolReleased() public {
        stablecoin.mint(address(carryPool), 100);
        vm.prank(MATCHWEEK_A);
        carryPool.fund(MATCHWEEK_ID_A, 100);

        vm.expectEmit(true, true, false, true);
        emit CarryPool.CarryPoolReleased(MATCHWEEK_ID_B, MATCHWEEK_B, 100);
        vm.prank(MATCHWEEK_B);
        carryPool.release(MATCHWEEK_ID_B);
    }

    function testRevert_release_alreadyReleased() public {
        vm.prank(MATCHWEEK_A);
        carryPool.release(MATCHWEEK_ID_A);

        vm.expectRevert(abi.encodeWithSelector(CarryPool.AlreadyReleased.selector, MATCHWEEK_ID_A));
        vm.prank(MATCHWEEK_B);
        carryPool.release(MATCHWEEK_ID_A);
    }

    function testRevert_release_notMatchweek() public {
        vm.expectRevert(CarryPool.NotMatchweek.selector);
        vm.prank(STRANGER);
        carryPool.release(MATCHWEEK_ID_A);
    }
}
