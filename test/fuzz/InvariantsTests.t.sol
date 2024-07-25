// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

// 1. The total supply of DSC should be less than the total value of colalteral

// Getter view functions should never revert

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployPDN} from "../../script/DeployPDN.s.sol";
import {PDNEngine} from "../../src/PDNEngine.sol";
import {Podzian} from "../../src/Podzian.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract Invariants is StdInvariant, Test{
    DeployPDN deployer;
    PDNEngine engine;
    Podzian pdn;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployPDN();
        (pdn, engine, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        // targetContract(address(engine));
        handler = new Handler(engine, pdn);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = pdn.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(pdn));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(pdn));

        uint256 wethValue = engine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = engine.getUsdValue(wbtc, totalWbtcDeposited);

        assert(wethValue + wbtcValue >= totalSupply);
    }
}