// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {CarryPool} from "../src/CarryPool.sol";
import {Disputes} from "../src/Disputes.sol";
import {Matchweek} from "../src/Matchweek.sol";
import {PitchMkt} from "../src/PitchMkt.sol";
import {Treasury} from "../src/Treasury.sol";

contract PitchMktTest is Test {
    uint32 constant MATCHWEEK_ID = 1;
    address constant FACTORY_OWNER = address(0xF0);
    address constant ADMIN = address(0xAD);
    address constant STRANGER = address(0xBAD);

    uint40 private _predictionDeadline;
    PitchMkt public factory;
    ERC20Mock public stablecoin;
    CarryPool public carryPool;
    Treasury public treasury;
    Disputes public disputes;

    function setUp() public {
        _predictionDeadline = uint40(block.timestamp + 1 days);
        stablecoin = new ERC20Mock();
        carryPool = new CarryPool(FACTORY_OWNER, stablecoin);
        treasury = new Treasury(FACTORY_OWNER, stablecoin);
        disputes = new Disputes(FACTORY_OWNER, stablecoin, treasury);
        factory = new PitchMkt(FACTORY_OWNER, stablecoin, carryPool, treasury, disputes);

        vm.prank(FACTORY_OWNER);
        carryPool.setFactory(address(factory));
        vm.prank(FACTORY_OWNER);
        treasury.setFactory(address(factory));
        vm.prank(FACTORY_OWNER);
        disputes.setFactory(address(factory));
        vm.prank(FACTORY_OWNER);
        treasury.setDisputes(address(disputes));
    }

    function test_createMatchweek() public {
        Matchweek.Match[] memory matches = _buildValidMatches();

        vm.prank(FACTORY_OWNER);
        vm.expectEmit(false, true, false, false);
        emit PitchMkt.MatchweekDeployed(address(0), MATCHWEEK_ID);
        address deployed = factory.createMatchweek(MATCHWEEK_ID, _predictionDeadline, matches, ADMIN);

        Matchweek matchweek = Matchweek(deployed);
        assertEq(matchweek.matchweekId(), MATCHWEEK_ID);
        assertEq(matchweek.predictionDeadline(), _predictionDeadline);
        assertEq(matchweek.owner(), ADMIN);
        assertEq(address(matchweek.STABLECOIN()), address(stablecoin));

        assertEq(factory.matchweeks(MATCHWEEK_ID), deployed);
        assertEq(factory.deployedMatchweeks(0), deployed);
        assertEq(carryPool.isMatchweek(deployed), true);
        assertEq(treasury.isMatchweek(deployed), true);
        assertEq(disputes.isMatchweek(deployed), true);
        assertEq(address(matchweek.TREASURY()), address(treasury));
        assertEq(address(matchweek.DISPUTES()), address(disputes));
    }

    function testRevert_NotOwner() public {
        Matchweek.Match[] memory matches = _buildValidMatches();

        vm.prank(STRANGER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, STRANGER));
        factory.createMatchweek(MATCHWEEK_ID, _predictionDeadline, matches, ADMIN);
    }

    /// @dev Builds 10 valid matches using deterministic team identifiers.
    function _buildValidMatches() internal pure returns (Matchweek.Match[] memory) {
        Matchweek.Match[] memory m = new Matchweek.Match[](10);
        for (uint256 i = 0; i < 10; ++i) {
            m[i] = Matchweek.Match({
                homeTeam: keccak256(abi.encodePacked("HOME", i)), awayTeam: keccak256(abi.encodePacked("AWAY", i))
            });
        }
        return m;
    }
}
