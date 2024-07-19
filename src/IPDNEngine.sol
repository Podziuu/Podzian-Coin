// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/**
 * @title IPDNEngine
 * @author Bartosz Podemski
 * @notice This interace consists of all the functions that
 * the PDNEngine contract should implement.
 */
interface IPDNEngine {
    function depositCollateralAndMintPdn(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountPdnToMint
    ) external;

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) external;

    function redeemCollateralForPdn(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountPdnToBurn)
        external;

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) external;

    function mintPdn(uint256 amountPdnToMint) external;

    function burnPdn(uint256 amount) external;

    function liquidate(address collateral, address user, uint256 debtToCover) external;
}
