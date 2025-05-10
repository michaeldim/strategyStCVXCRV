// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

/**
 * @title IPriceOracle
 * @notice Generic interface for price oracles
 */
interface IPriceOracle {
    /**
     * @notice Get the USD price of a token
     * @param token Address of the token
     * @return price Token price in USD (scaled to 1e18)
     */
    function getUSDPrice(address token) external view returns (uint256 price);
}
