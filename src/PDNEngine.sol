// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IPDNEngine} from "./IPDNEngine.sol";
import {Podzian} from "./Podzian.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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
contract PDNEngine is IPDNEngine, ReentrancyGuard {
    /**
     * Errors
     */
    error PDNEngine__NeedsMoreThanZero();
    error PDNEngine__TokenAddressesAndPriceFeedsLengthMismatch();
    error PDNEngine__TokenNotSupported();
    error PDNEngine__TransferFailed();
    error PDNEngine__BreaksHealthFactor(uint256 healthFactor);
    error PDNEngine__MintFailed();
    error PDNEngine__HealthFactorIsFine();
    error PDNEngine__HealthFactorNotImproved();

    /**
     * State Variables
     */
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // this means 10%

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountPdnMinted) private s_PDNMinted;
    address[] private s_collateralTokens;

    Podzian private immutable i_pdn;

    /**
     * Events
     */
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, address redeemedTo, address indexed token, uint256 amount);

    /**
     * Modifiers
     */
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert PDNEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert PDNEngine__TokenNotSupported();
        }
        _;
    }

    /**
     * Functions
     */
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address pdnAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert PDNEngine__TokenAddressesAndPriceFeedsLengthMismatch();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_pdn = Podzian(pdnAddress);
    }

    /**
     * External Functions
     */

    /**
     *
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountPdnToMint The amount of PDN to mint
     * @notice This function will deposit your collateral and mint PDN in one transaction
     */
    function depositCollateralAndMintPdn(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountPdnToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintPdn(amountPdnToMint);
    }
    /**
     * @notice follows CEI
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert PDNEngine__TransferFailed();
        }
    }

    /**
     *
     * @param tokenCollateralAddress The address of the token to redeem as collateral
     * @param amountCollateral The amount of collateral to redeem
     * @param amountPdnToBurn The amount of PDN to burn
     * @notice This function will redeem your collateral and burn PDN in one transaction
     */
    function redeemCollateralForPdn(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountPdnToBurn)
        external
    {
        burnPdn(amountPdnToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral); // this function will revert if health factor is broken
    }

    // in order to redeem collateral,
    // 1. health factor must be over 1 AFTER collateral pulled
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice follows CEI
     * @param amountPdnToMint The amount of PDN to mint
     * @notice they must have more collateral value than the minimum threshold
     */
    function mintPdn(uint256 amountPdnToMint) public moreThanZero(amountPdnToMint) nonReentrant {
        s_PDNMinted[msg.sender] += amountPdnToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_pdn.mint(msg.sender, amountPdnToMint);
        if (!minted) {
            revert PDNEngine__MintFailed();
        }
    }

    function burnPdn(uint256 amount) public moreThanZero(amount) {
        _burnPdn(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // Probably this would never hit
    }

    /**
     *
     * @param collateral The address of the collateral to liquidate
     * @param user The address of the user to liquidate
     * @param debtToCover The amount of debt to cover
     * @notice You can partially liquidate a user
     * @notice You will get a liquidation bonus for taking the users funds
     * @notice This function working assumes the protocol will be rougly 200%
     * overcollateralized at all times
     * @notice A known bug would be if the protocol were 100% or less collateralized, then
     * we wouldn't be able to incentive the liquidators.
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert PDNEngine__HealthFactorIsFine();
        }
        uint256 tokenAmountFromDeptCovered = getTokenAmountFromUsd(collateral, debtToCover); // amount of collateral in USD
        uint256 bonusCollateral = (tokenAmountFromDeptCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToReedem = tokenAmountFromDeptCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateral, totalCollateralToReedem);
        _burnPdn(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert PDNEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * Private & Internal View Function
     */

    /**
     * @dev Low-level i nternal function, do not call unlesss the function calling
     * it is checking for health factors being broken
     */
    function _burnPdn(uint256 amountPdnToBurn, address onBehalfOf, address pdnFrom) private {
        s_PDNMinted[onBehalfOf] -= amountPdnToBurn;
        bool success = i_pdn.transferFrom(pdnFrom, address(this), amountPdnToBurn);
        if (!success) {
            revert PDNEngine__TransferFailed();
        }
        i_pdn.burn(amountPdnToBurn);
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert PDNEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalPdnMinted, uint256 collateralValueInUsd)
    {
        totalPdnMinted = s_PDNMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * Returns how close to liquidation a user is
     * If a user goes below 1, then they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalPdnMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(collateralValueInUsd, totalPdnMinted);
    }

    function _calculateHealthFactor(uint256 collateralValueInUsd, uint256 totalPdnMinted) private pure returns(uint256) {
        if (totalPdnMinted == 0) {
            return type(uint256).max;
        }
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalPdnMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert PDNEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /**
     * Public & External View Functions
     */
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountInformation(address user) external view returns (uint256 totalPdnMinted, uint256 collateralValueInUsd) {
        (totalPdnMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function calculateHealthFactor(uint256 collateralValueInUsd, uint256 totalPdnMinted) external pure returns (uint256) {
        return _calculateHealthFactor(collateralValueInUsd, totalPdnMinted);
    }

    function getHealthFactor(address user) public view returns (uint256) {
        return _healthFactor(user);
    }
}
