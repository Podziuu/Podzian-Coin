// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployPDN} from "../../script/DeployPDN.s.sol";
import {Podzian} from "../../src/Podzian.sol";
import {PDNEngine} from "../../src/PDNEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract PDNEngineTest is Test {
    DeployPDN deployer;
    Podzian pdn;
    PDNEngine engine;
    HelperConfig helper;
    address ethUsdPriceFeed;
    address weth;
    address btcUsdPriceFeed;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 100 ether;

    event CollateralRedeemed(address indexed redeemedFrom, address redeemedTo, address indexed token, uint256 amount);

    function setUp() external {
        deployer = new DeployPDN();
        (pdn, engine, helper) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = helper.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    /**
     * Constructor Tests
     */
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    function testRevertsIfTokenLengthDoeesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(PDNEngine.PDNEngine__TokenAddressesAndPriceFeedsLengthMismatch.selector);
        new PDNEngine(tokenAddresses, priceFeedAddresses, address(pdn));
    }

    /**
     * Price Tests
     */
    function testGetUsdValue() external view {
        uint256 ethAmount = 15e18;

        uint256 expectedUsd = 60000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.025 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    /**
     * DepositCollateral Tests
     */
    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        vm.expectRevert(PDNEngine.PDNEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock();
        ranToken.mint(USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(PDNEngine.PDNEngine__TokenNotSupported.selector);
        engine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral() {
        (uint256 totalPdnMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);

        uint256 expectedTotalPdnMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assertEq(totalPdnMinted, expectedTotalPdnMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    /**
     * depositCollateralAndMintPdn Tests
     */
    function testMintIfHealthFactorBreaks() public {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        uint256 amountToMint = (AMOUNT_COLLATERAL * (uint256(price) * 1e10)) / 1e18;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        uint256 expectedHealthFactor = engine.calculateHealthFactor(engine.getUsdValue(weth, AMOUNT_COLLATERAL), amountToMint);
        vm.expectRevert(abi.encodeWithSelector(PDNEngine.PDNEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.depositCollateralAndMintPdn(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
    }

    function testCanDepositAndMint() public {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        uint256 amountToMint = ((AMOUNT_COLLATERAL * (uint256(price) * 1e10)) / 1e18) / 2; // minting half of our collateral
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintPdn(weth, AMOUNT_COLLATERAL, amountToMint);
        (uint256 totalPdnMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        vm.stopPrank();
        assertEq(totalPdnMinted, amountToMint);
        assertEq(AMOUNT_COLLATERAL, engine.getTokenAmountFromUsd(weth, collateralValueInUsd));
    }

    /**
     * MintPdn Tests
     */
    function testRevertsMintIfZero() public {
        vm.expectRevert(PDNEngine.PDNEngine__NeedsMoreThanZero.selector);
        engine.mintPdn(0);
    }

    function testRevertsIfBreaksHealthFactor() public {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        uint256 amountToMint = (AMOUNT_COLLATERAL * (uint256(price) * 1e10)) / 1e18;
        uint256 expectedHealthFactor = engine.calculateHealthFactor(engine.getUsdValue(weth, 0), amountToMint);
        vm.expectRevert(abi.encodeWithSelector(PDNEngine.PDNEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.mintPdn(amountToMint);
    }

    function testCanMint() public depositedCollateral {
        uint256 amountToMint = 1 ether;
        vm.prank(USER);
        engine.mintPdn(amountToMint);

        uint256 userBalance = pdn.balanceOf(USER);
        assertEq(userBalance, amountToMint);
    }

    /**
     * RedeemPdn Tests
     */
    function testCanReddemCollateral() public depositedCollateral {
        vm.startPrank(USER);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        (,uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        vm.stopPrank();
        assertEq(collateralValueInUsd, 0);
    }

    function testRedeemPdnEmitsEvent() public depositedCollateral {
        vm.expectEmit(true, true, true, true, address(engine));
        emit CollateralRedeemed(USER, USER, weth, AMOUNT_COLLATERAL);
        vm.prank(USER);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
    }

    /**
     * BurnPdn Tests
     */
    function testRevertsBurnIfZero() public {
        vm.expectRevert(PDNEngine.PDNEngine__NeedsMoreThanZero.selector);
        engine.burnPdn(0);
    }
 
    function testBurnDecreasePdnMinted() public depositedCollateral {
        uint256 amountToMint = 1 ether;
        uint256 amountToBurn = 0.5 ether;
        vm.startPrank(USER);
        engine.mintPdn(amountToMint);
        pdn.approve(address(engine), amountToBurn);
        engine.burnPdn(amountToBurn);
        (uint256 totalPdnMinted,) = engine.getAccountInformation(USER);
        vm.stopPrank();
        assertEq(totalPdnMinted, amountToMint - amountToBurn);
    }

    /**
     * ReddemCorrateralForPdn Tests
     */
    function testCanReedemCollateralForPdn() public depositedCollateral() {
        uint256 amountToMint = 1 ether;
        vm.startPrank(USER);
        engine.mintPdn(amountToMint);
        pdn.approve(address(engine), amountToMint);
        engine.redeemCollateralForPdn(weth, AMOUNT_COLLATERAL, amountToMint);
        (uint256 totalPdnMinted ,uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        vm.stopPrank();
        assertEq(collateralValueInUsd, 0);
        assertEq(totalPdnMinted, 0);
    }

    /**
     * Liquidate tests
     */
    function testRevertsIfHealthFactorIsFine() public depositedCollateral() {
        uint256 amountToMint = 1 ether;
        vm.startPrank(USER);
        engine.mintPdn(amountToMint);
        vm.expectRevert(PDNEngine.PDNEngine__HealthFactorIsFine.selector);
        engine.liquidate(weth, USER, 1 ether);
    }

    function testCanLiquidate() public depositedCollateral() {
        
    }
}
