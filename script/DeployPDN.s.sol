// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Podzian} from "../src/Podzian.sol";
import {PDNEngine} from "../src/PDNEngine.sol";
import {HelperConfig} from  "./HelperConfig.s.sol";

contract DeployPDN is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (Podzian, PDNEngine) {
        HelperConfig helper = new HelperConfig();

        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) = helper.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        Podzian pdn = new Podzian();
        PDNEngine engine = new PDNEngine(tokenAddresses, priceFeedAddresses, address(pdn));
        pdn.transferOwnership(address(engine));
        vm.stopBroadcast();

        return (pdn, engine);
    }
}