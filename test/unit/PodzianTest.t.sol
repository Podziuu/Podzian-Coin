//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Podzian} from "../../src/Podzian.sol";

contract PodzianTest is Test {
    Podzian podzian;

    function setUp() public {
        podzian = new Podzian();
    }

    function testBurnWithAmountLessOrEqualZero() public {
        uint256 AMOUNT_TO_BURN = 0;
        vm.prank(podzian.owner());
        vm.expectRevert(Podzian.Podzian__MustBeMoreThanZero.selector);
        podzian.burn(AMOUNT_TO_BURN);
    }

    function testBurnWhenBalanceIsLessThanAmount() public {
        vm.startPrank(podzian.owner());
        podzian.mint(address(this), 100);
        vm.expectRevert(Podzian.Podzian__BurnAmountExceedsBalance.selector);
        podzian.burn(200);
        vm.stopPrank();
    }

    function testCanBurn() public {
        vm.startPrank(podzian.owner());
        podzian.mint(address(this), 100);
        podzian.burn(50);
        vm.stopPrank();
        assertEq(podzian.balanceOf(address(this)), 50);
    }

    function testCanMint() public {
        uint256 AMOUNT_TO_MINT = 100;
        vm.prank(podzian.owner());
        podzian.mint(address(this), AMOUNT_TO_MINT);
        assertEq(podzian.balanceOf(address(this)), AMOUNT_TO_MINT);
    }

    function testCantMintToZeroAddress() public {
        vm.prank(podzian.owner());
        vm.expectRevert(Podzian.Podzian__NotZeroAddress.selector);
        podzian.mint(address(0), 100);
    }

    function testCantMintLessOrEqualZero() public {
        vm.prank(podzian.owner());
        vm.expectRevert(Podzian.Podzian__MustBeMoreThanZero.selector);
        podzian.mint(address(this), 0);
    }
}
