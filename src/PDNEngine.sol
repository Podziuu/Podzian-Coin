// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IPDNEngine} from "./IPDNEngine.sol";

/**
 * @title PDNEngine
 * @author Bartosz Podemski
 * 
 * The system is designed to be as minimal as possible,
 * and have the tokens maintain a 1 token == 1$ peg.
 * This stablecoin has the properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmically Stable
 * 
 * It is similar to DAI if DAI had no governance, no fees,
 * and was only backed by WETH and WBTC.
 * 
 * Our PDN system should always be "overcollateralized". At
 * no point, should the value of all collateral <= the $ backed
 * value of all the PDN.
 * 
 * @notice This contract is the core of the PDN System. It
 * handles all the logic for mining and redeeming PDN, as well
 * as depositing & withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS
 * (DAI) system.
 */
contract PDNEngine is IPDNEngine {
    function depositCollateralAndMintPdn() external {}

    function depositCollateral() external {}

    function redeemCollateralForPdn() external {}

    function redeemCollateral() external {}

    function mintPdn() external {}

    function burnPdn() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}