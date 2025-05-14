// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IStrategyInterface is IStrategy {
    // Auction and trading setup
    enum SwapType {
        NULL,
        TRADE_FACTORY,
        AUCTION
    }

    // TradeFactory setup functions
    function setTradeFactory(address _tradeFactory) external;
    function enableTradeFactoryRoute(address _from, address _to) external;

    // Auction setup functions
    function setAuction(address _auction) external;
    function kickAuction(address _token) external returns (address);
    function setSwapType(address _token, SwapType _swapType) external;

    // Settings and configuration functions
    function setMinAmountToSellMapping(address _token, uint256 _minAmount) external;

    // Wrapper configuration
    function setRewardWeight(uint256 _weight) external;

    // View functions
    function getAllRewardTokens() external view returns (address[] memory);

    // State variables
    function WRAPPER() external view returns (address);
    function auction() external view returns (address);
    function swapType(address _token) external view returns (SwapType);
    function minAmountToSellMapping(address _token) external view returns (uint256);

    // Reward token management
    function addRewardToken(address _token, uint8 _swapType) external;
    function removeRewardToken(address _token) external;

    // Operational functions
    function manualClaimRewards(bool sell) external;
}
