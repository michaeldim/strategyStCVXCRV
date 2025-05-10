// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IStrategyInterface is IStrategy {
    // Auction and TradeFactory setup functions
    function setAuction(address _auction) external;
    function setTradeFactory(address _tradeFactory) external;
    function enableAuctionRoute(address _from, address _to) external;
    function enableTradeFactoryRoute(address _from, address _to) external;

    // Settings and configuration functions
    function setUseTradeFactory(bool _useTradeFactory) external;
    function setUseAuction(bool _useAuction) external;
    function setMinAmountToSell(address _token, uint256 _minAmount) external;
    function setMinAmountsToSell(address[] calldata _tokens, uint256[] calldata _minAmounts) external;

    // Health check configuration
    function setHealthCheck(bool _doHealthCheck) external;
    function setStrategyProfitLimitRatio(uint256 _profitLimitRatio) external;
    function setStrategyLossLimitRatio(uint256 _lossLimitRatio) external;

    // Wrapper configuration
    function setRewardWeight(uint256 _weight) external;
}
