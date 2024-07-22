// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeployPDN} from "../../script/DeployPDN.s.sol";
import {Podzian} from "../../src/Podzian.sol";
import {PDNEngine} from "../../src/PDNEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract PDNEngineTest is Test {
    DeployPDN deployer;
    Podzian pdn;
    PDNEngine engine;
    HelperConfig helper;
    address ethUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() external {
        deployer = new DeployPDN();
        (pdn, engine, helper) = deployer.run();
        (ethUsdPriceFeed,, weth,,) = helper.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    /**
     * Price Tests
     */
    function testGetUsdValue() external view {
        uint256 ethAmount = 15e18;

        uint256 expectedUsd = 51000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    /**
     * DepositCollateral Tests
     */
    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        // ERC20Mock(weth).

        vm.expectRevert(PDNEngine.PDNEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }
}
