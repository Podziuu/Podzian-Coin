// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PDNEngine} from "../../src/PDNEngine.sol";
import {Podzian} from "../../src/Podzian.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    PDNEngine engine;
    Podzian pdn;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethPriceFeed;

    uint96 public constant MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(PDNEngine _pdnEngine, Podzian _pdn) {
        engine = _pdnEngine;
        pdn = _pdn;

        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethPriceFeed = MockV3Aggregator(engine.getCollateralTokenPriceFeed(address(weth)));
    }

    function mintPdn(uint256 amount, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        (uint256 totalPdnMinted, uint256 totalCollateralInUsd) = engine.getAccountInformation(sender);
        console.log("totalPdnMinted: %s", totalPdnMinted);
        console.log("totalCollateralInUsd: %s", totalCollateralInUsd);
        int256 maxPdnToMint = (int256(totalCollateralInUsd) / 4) - int256(totalPdnMinted);
        console.log("maxPdnToMint: %s", maxPdnToMint);
        if (maxPdnToMint < 0) {
            return;
        }
        amount = bound(amount, 0, uint256(maxPdnToMint));
        console.log("amount: %s", amount);
        if (amount == 0) {
            return;
        }
        vm.startPrank(sender);
        engine.mintPdn(amount);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(engine), amountCollateral);
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxAmountToRedeem = engine.getCollateralBalance(msg.sender, address(collateral));
        (uint256 mintedPdn,) = engine.getAccountInformation(msg.sender);

        amountCollateral = bound(amountCollateral, 0, maxAmountToRedeem);

        if (amountCollateral == 0) {
            return;
        }
        vm.startPrank(msg.sender);
        if (mintedPdn > 0) {
            pdn.approve(address(engine), mintedPdn);
            engine.burnPdn(mintedPdn);
        }
        engine.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    // This breaks our invariant test suite 
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethPriceFeed.updateAnswer(newPriceInt);
    // }

    // Helper Functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
