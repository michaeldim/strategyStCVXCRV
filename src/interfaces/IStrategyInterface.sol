// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IStrategyInterface is IStrategy {
    // TradeFactory setup functions
    function setTradeFactory(address _tradeFactory) external;
    function enableTradeFactoryRoute(address _from, address _to) external;

    // Settings and configuration functions
    function setMinAmountToSellMapping(address _token, uint256 _minAmount) external;
    function setMinAmountsToSellMapping(address[] calldata _tokens, uint256[] calldata _minAmounts) external;
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

    function getAllRewardTokens() external view returns (address[] memory);

    // State variables
    function WRAPPER() external view returns (address);
    function tradeFactory() external view returns (address);
    function idleThreshold() external view returns (uint256);
    function depositLimit() external view returns (uint256);
    function minAmountToSellMapping(address _token) external view returns (uint256);

    // Reward token management
    function addRewardToken(address _token, uint8 _swapType) external;
    function removeRewardToken(address _token) external;

    // Additional functions used in tests
    function manualClaimRewards() external;
    function claimAndSellRewards(bool _sell) external;
}
