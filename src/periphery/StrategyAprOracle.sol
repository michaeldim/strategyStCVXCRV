// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {AprOracleBase} from "@periphery/AprOracle/AprOracleBase.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
}

interface ICvxCrvUtilities {
    function mainRewardRates() external view returns (
        address[] memory tokens,
        uint256[] memory rates,
        uint256[] memory groups
    );
    function extraRewardRates() external view returns (
        address[] memory tokens,
        uint256[] memory rates,
        uint256[] memory groups
    );
    function apr(
        uint256 rate,
        uint256 rewardPrice,
        uint256 depositPrice
    ) external pure returns (uint256);
}

/**
 * @title cvxCRV Strategy APR Oracle
 * @notice Provides accurate APR calculations for the cvxCRV staking strategy
 * @dev Calculates expected returns via CvxCrvUtilities for cvxCRV staking.
 */
contract StrategyAprOracle is AprOracleBase {
    // Helper to sum APRs for a set of tokens/rates/groups
    function _sumAprGroups(
        address[] memory toks,
        uint256[] memory rates,
        uint256[] memory groups,
        uint256 depositPrice
    ) private view returns (uint256 group0, uint256 group1) {
        for (uint i = 0; i < toks.length; i++) {
            address token = toks[i];
            if (token == THREE_CRV) continue;
            uint256 price = priceOracle.getUSDPrice(token);
            uint256 aprTok = cvxCrvUtilities.apr(rates[i], price, depositPrice);
            if (groups[i] == 0) group0 += aprTok;
            else group1 += aprTok;
        }
    }
    // Constants for rewards contracts and tokens
    address public constant CVXCRV = 0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7;
    address public constant THREE_CRV = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490; // 3CRV token address
    // Address of the token representing the staked asset in the strategy
    address public constant STAKED_ASSET_TOKEN = 0xaa0C3f5F7DFD688C6E646F66CD2a6B66ACdbE434; // Matches test STAKED_CVXCRV

    // Price oracle interface
    IPriceOracle public priceOracle;

    /// @notice CvxCrvUtilities contract for boosted & grouped APR
    ICvxCrvUtilities public cvxCrvUtilities = ICvxCrvUtilities(0xadd2F542f9FF06405Fabf8CaE4A74bD0FE29c673);

    constructor(address _priceOracle) AprOracleBase("cvxCRV Strategy APR Oracle", msg.sender) {
        if (_priceOracle != address(0)) {
            priceOracle = IPriceOracle(_priceOracle);
        }
    }

    /**
     * @notice Updates the price oracle address
     * @param _priceOracle New price oracle address
     */
    function setPriceOracle(address _priceOracle) external onlyGovernance {
        priceOracle = IPriceOracle(_priceOracle);
    }

    /**
     * @notice Update the CvxCrvUtilities contract address
     * @param _utilities The new utilities contract
     */
    function setCvxCrvUtilities(address _utilities) external onlyGovernance {
        cvxCrvUtilities = ICvxCrvUtilities(_utilities);
    }

    /**
     * @notice Will return the expected Apr of a strategy post a debt change.
     * @dev _delta is a signed integer so that it can also represent a debt
     * decrease.
     *
     * This should return the annual expected return at the current timestamp
     * represented as 1e18.
     *
     *      ie. 10% == 1e17
     *
     * _delta will be == 0 to get the current apr.
     *
     * This will potentially be called during non-view functions so gas
     * efficiency should be taken into account.
     *
     * @param _strategy The token to get the apr for.
     * @param _delta The difference in debt.
     * @return . The expected apr for the strategy represented as 1e18.
     */
    function aprAfterDebtChange(
        address _strategy,
        int256 _delta
    ) external view override returns (uint256) {
        uint256 currentStakedBalance = IERC20Minimal(STAKED_ASSET_TOKEN).balanceOf(_strategy);
        uint256 futureStakedBalance;

        if (_delta < 0) {
            uint256 debtDecrease = uint256(-_delta);
            if (debtDecrease > currentStakedBalance) {
                futureStakedBalance = 0;
            } else {
                futureStakedBalance = currentStakedBalance - debtDecrease;
            }
        } else {
            futureStakedBalance = currentStakedBalance + uint256(_delta);
        }

        if (futureStakedBalance == 0) {
            return 0;
        }

        // If utilities is set, use its boosted & grouped APR calculation
        if (address(cvxCrvUtilities) != address(0)) {
            uint256 depositPrice = getCvxCRVPrice();
            (address[] memory toks0, uint256[] memory r0, uint256[] memory g0) = cvxCrvUtilities.mainRewardRates();
            (address[] memory toks1, uint256[] memory r1, uint256[] memory g1) = cvxCrvUtilities.extraRewardRates();
            (uint256 group0a, uint256 group1a) = _sumAprGroups(toks0, r0, g0, depositPrice);
            (uint256 group0b, uint256 group1b) = _sumAprGroups(toks1, r1, g1, depositPrice);
            uint256 group0 = group0a + group0b;
            uint256 group1 = group1a + group1b;
            return group0 > group1 ? group0 : group1;
        }
        revert("CvxCrvUtilities not set");
    }

    /**
     * @notice Get the current price of cvxCRV in USD
     * @return price cvxCRV price in USD (scaled to 1e18)
     */
    function getCvxCRVPrice() public view returns (uint256 price) {
        if (address(priceOracle) != address(0)) {
            return priceOracle.getUSDPrice(CVXCRV);
        }
        // Fallback price if no oracle or oracle fails
        return 0.52e18; // $0.52 default price for cvxCRV
    }
}
