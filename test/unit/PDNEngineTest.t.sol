// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployPDN} from "../../script/DeployPDN.s.sol";
import {Podzian} from "../../src/Podzian.sol";
import {PDNEngine} from "../../src/PDNEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockERC20TransferFromFail} from "../mocks/MockERC20TransferFromFail.sol";
import {MockERC20TransferFail} from "../mocks/MockERC20TransferFail.sol";
import {MockERC20MintFail} from "../mocks/MockERC20MintFail.sol";
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
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_TO_MINT = 100 ether;
    uint256 public constant AMOUNT_TO_BURN = 10 ether;
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
    function testRevertsIfTransactionFail() public {
        vm.prank(msg.sender);
        MockERC20TransferFromFail failingToken = new MockERC20TransferFromFail();
        tokenAddresses = [address(failingToken)];
        priceFeedAddresses = [ethUsdPriceFeed];
        vm.prank(msg.sender);
        PDNEngine eng = new PDNEngine(tokenAddresses, priceFeedAddresses, address(pdn));
        failingToken.mint(USER, AMOUNT_COLLATERAL);

        vm.expectRevert(PDNEngine.PDNEngine__TransferFailed.selector);
        eng.depositCollateral(address(failingToken), AMOUNT_COLLATERAL);
    }

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

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
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
        uint256 expectedHealthFactor =
            engine.calculateHealthFactor(engine.getUsdValue(weth, AMOUNT_COLLATERAL), amountToMint);
        vm.expectRevert(abi.encodeWithSelector(PDNEngine.PDNEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.depositCollateralAndMintPdn(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
    }

    modifier depositedCollateralAndMintedPdn() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintPdn(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    function testCanDepositAndMint() public depositedCollateralAndMintedPdn {
        (uint256 totalPdnMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        vm.stopPrank();
        assertEq(totalPdnMinted, AMOUNT_TO_MINT);
        assertEq(AMOUNT_COLLATERAL, engine.getTokenAmountFromUsd(weth, collateralValueInUsd));
    }

    /**
     * MintPdn Tests
     */
    function testRevertIfMintFail() public {
        MockERC20MintFail failingToken = new MockERC20MintFail();
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];
        PDNEngine eng = new PDNEngine(tokenAddresses, priceFeedAddresses, address(failingToken));
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(eng), AMOUNT_COLLATERAL);
        eng.depositCollateral(weth, AMOUNT_COLLATERAL);
        failingToken.approve(address(eng), AMOUNT_COLLATERAL);
        vm.expectRevert(PDNEngine.PDNEngine__MintFailed.selector);
        eng.mintPdn(1 ether);
        vm.stopPrank();
    }

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
    function testRevertsIfTransferFail() public {
        // engine with collateral token that fails on transfer
        MockERC20TransferFail failingToken = new MockERC20TransferFail();
        tokenAddresses = [address(failingToken)];
        priceFeedAddresses = [ethUsdPriceFeed];
        PDNEngine eng = new PDNEngine(tokenAddresses, priceFeedAddresses, address(pdn));
        failingToken.mint(USER, AMOUNT_TO_MINT);
        vm.startPrank(USER);
        failingToken.approve(address(eng), AMOUNT_TO_MINT);
        eng.depositCollateral(address(failingToken), AMOUNT_COLLATERAL);
        vm.expectRevert(PDNEngine.PDNEngine__TransferFailed.selector);
        eng.redeemCollateral(address(failingToken), 1 ether);
        vm.stopPrank();
    }

    function testCanReddemCollateral() public depositedCollateral {
        vm.startPrank(USER);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        (, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
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

    function testBurnDecreasePdnMinted() public depositedCollateralAndMintedPdn {
        vm.startPrank(USER);
        pdn.approve(address(engine), AMOUNT_TO_BURN);
        engine.burnPdn(AMOUNT_TO_BURN);
        (uint256 totalPdnMinted,) = engine.getAccountInformation(USER);
        vm.stopPrank();
        assertEq(totalPdnMinted, AMOUNT_TO_MINT - AMOUNT_TO_BURN);
    }

    /**
     * ReddemCorrateralForPdn Tests
     */
    function testCanReedemCollateralForPdn() public depositedCollateralAndMintedPdn {
        vm.startPrank(USER);
        pdn.approve(address(engine), AMOUNT_TO_MINT);
        engine.redeemCollateralForPdn(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        (uint256 totalPdnMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        vm.stopPrank();
        assertEq(collateralValueInUsd, 0);
        assertEq(totalPdnMinted, 0);
    }

    /**
     * Liquidate tests
     */
    function testRevertsIfHealthFactorIsFine() public depositedCollateral {
        uint256 amountToMint = 1 ether;
        vm.startPrank(USER);
        engine.mintPdn(amountToMint);
        vm.expectRevert(PDNEngine.PDNEngine__HealthFactorIsFine.selector);
        engine.liquidate(weth, USER, 1 ether);
    }

    modifier liquidated() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintPdn(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        int256 ethPrice = 18e8;

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethPrice);
        ERC20Mock(weth).mint(LIQUIDATOR, AMOUNT_COLLATERAL * 2);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL * 2);
        engine.depositCollateralAndMintPdn(weth, AMOUNT_COLLATERAL * 2, AMOUNT_TO_MINT);
        pdn.approve(address(engine), AMOUNT_TO_MINT);
        (uint256 minted, uint256 value) = engine.getAccountInformation(LIQUIDATOR);
        engine.liquidate(weth, USER, AMOUNT_TO_MINT);
        vm.stopPrank();
        (uint256 totalPdnMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(LIQUIDATOR);
        _;
    }

    function testCanLiquidate() public liquidated {
        uint256 liquidatorBalance = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        uint256 expectedWeth = // amount token liquidated to the user + 10% of the amount liquidated
         engine.getTokenAmountFromUsd(weth, AMOUNT_TO_MINT) + engine.getTokenAmountFromUsd(weth, AMOUNT_TO_MINT) / 10;
        assertEq(liquidatorBalance, expectedWeth);
    }

    function testUserStillHasEthAfterLiquidation() public liquidated {
        uint256 lostEth =
            engine.getTokenAmountFromUsd(weth, AMOUNT_TO_MINT) + engine.getTokenAmountFromUsd(weth, AMOUNT_TO_MINT) / 10;

        uint256 usdAmountOfLiquidation = engine.getUsdValue(weth, lostEth);
        uint256 expectedUserEthAmount = engine.getUsdValue(weth, AMOUNT_COLLATERAL) - usdAmountOfLiquidation;

        (, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);

        assertEq(collateralValueInUsd, expectedUserEthAmount);
    }

    function testUserHasNoMorePdnAfterLiquidation() public liquidated {
        (uint256 totalPdnMinted,) = engine.getAccountInformation(USER);
        assertEq(totalPdnMinted, 0);
    }

    function testLiquidatorTakesOnUsersDebt() public liquidated {
        (uint256 liquidatorDscMinted,) = engine.getAccountInformation(LIQUIDATOR);
        assertEq(liquidatorDscMinted, AMOUNT_TO_MINT);
    }

    /**
     * Health Factor Tests
     */
    function testCorrectHealhFactorCalculations() public depositedCollateralAndMintedPdn {
        uint256 expectedHealthFactor = 200 ether;
        uint256 healthFactor = engine.getHealthFactor(USER);
        // we are depositing $40,000 value in collateral and
        // minting $100 dolars of value
        // so 40,000 * 0.5 = 20,000
        // 20,000 / 100 = 200
        assertEq(healthFactor, expectedHealthFactor);
    }

    /**
     * Getters functions Tests
     */
    function testGetAccountCollateralValue() public depositedCollateral {
        uint256 expectedValue = 40000 ether;
        uint256 collateralValue = engine.getAccountCollateralValue(USER);
        assertEq(collateralValue, expectedValue);
    }
}
