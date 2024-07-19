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
    error PDNEngine__TrasnferFailed();
    error PDNEngine__BreaksHealthFactor(uint256 healthFactor);
    error PDNEngine__MintFailed();

    /**
     * State Variables
     */
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountPdnMinted) private s_PDNMinted;
    address[] private s_collateralTokens;

    Podzian private immutable i_pdn;

    /**
     * Events
     */
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

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
    function depositCollateralAndMintPdn(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountPdnToMint
    ) external {}

    /**
     * @notice follows CEI
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert PDNEngine__TrasnferFailed();
        }
    }

    function redeemCollateralForPdn(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountPdnToBurn)
        external
    {}

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) external {}

    /**
     * @notice follows CEI
     * @param amountPdnToMint The amount of PDN to mint
     * @notice they must have more collateral value than the minimum threshold
     */
    function mintPdn(uint256 amountPdnToMint) external moreThanZero(amountPdnToMint) nonReentrant {
        s_PDNMinted[msg.sender] += amountPdnToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_pdn.mint(msg.sender, amountPdnToMint);
        if (!minted) {
            revert PDNEngine__MintFailed();
        }
    }

    function burnPdn(uint256 amount) external {}

    function liquidate(address collateral, address user, uint256 debtToCover) external {}

    function getHealthFactor() external view {}

    /**
     * Private & Internal View Function
     */
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
}
