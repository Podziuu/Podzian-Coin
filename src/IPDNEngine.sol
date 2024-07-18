// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/**
 * @title IPDNEngine
 * @author Bartosz Podemski 
 * @notice This interace consists of all the functions that 
 * the PDNEngine contract should implement.
 */
interface IPDNEngine {
    function depositCollateralAndMintPdn() external;

    function depositCollateral() external;

    function redeemCollateralForPdn() external;

    function redeemCollateral() external;

    function mintPdn() external;

    function burnPdn() external;

    function liquidate() external;

    function getHealthFactor() external view;
}