// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IStrategyInterface is IStrategy {
    // TradeFactory setup functions
    function setTradeFactory(address _tradeFactory) external;
    function enableTradeFactoryRoute(address _from, address _to) external;

    // Settings and configuration functions
    function setMinAmountToSell(address _token, uint256 _minAmount) external;
    function setMinAmountsToSell(address[] calldata _tokens, uint256[] calldata _minAmounts) external;
    function setDepositLimit(uint256 _limit) external;
    function setIdleThreshold(uint256 _idleThreshold) external;

    // Health check configuration
    function setHealthCheck(bool _doHealthCheck) external;
    function setStrategyProfitLimitRatio(uint256 _profitLimitRatio) external;
    function setStrategyLossLimitRatio(uint256 _lossLimitRatio) external;

    // Wrapper configuration
    function setRewardWeight(uint256 _weight) external;

    // View functions for configuration and state
    function swapperConfig()
        external
        view
        returns (
            address _tradeFactory,
            uint256[] memory _minAmounts,
            address[] memory _tokens
        );

    function tradeFactoryInfo() external view returns (address _tradeFactory, address[] memory _tokens);

    function getHealthCheckConfig() external view returns (bool _enabled, uint256 _profitLimit, uint256 _lossLimit);

    function pendingRewards()
        external
        view
        returns (
            uint256 crv,
            uint256 cvx,
            uint256 crvUsd,
            bool crvExceedsMin,
            bool cvxExceedsMin,
            bool crvUsdExceedsMin
        );

    // Token getters
    function CRV() external view returns (address);
    function CVX() external view returns (address);
    function CRVUSD() external view returns (address);
    function CVXCRV() external view returns (address);
    function WRAPPER() external view returns (address);

    // State variables
    function tradeFactory() external view returns (address);
    function doHealthCheck() external view returns (bool);
    function idleThreshold() external view returns (uint256);
    function depositLimit() external view returns (uint256);
    function minAmountToSell(address _token) external view returns (uint256);

    // Additional functions used in tests
    function manualClaimRewards() external;
    function claimAndSellRewards(bool _sell) external;
}
