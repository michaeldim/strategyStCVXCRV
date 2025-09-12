// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockTradeFactory {
    mapping(address => mapping(address => bool)) public routes;
    bool private _enableCalled;
    address[] public enabledFromTokens;
    address[] public enabledToTokens;

    event RouteEnabled(address fromToken, address toToken);

    function enable(address fromToken, address toToken) external returns (bool) {
        routes[fromToken][toToken] = true;
        _enableCalled = true;
        enabledFromTokens.push(fromToken);
        enabledToTokens.push(toToken);
        emit RouteEnabled(fromToken, toToken);
        return true;
    }

    function disable(address fromToken, address toToken) external returns (bool) {
        routes[fromToken][toToken] = false;
        return true;
    }

    function isEnabled(address fromToken, address toToken) external view returns (bool) {
        return routes[fromToken][toToken];
    }

    // Test helper functions
    function enableCalled() external view returns (bool) {
        return _enableCalled;
    }

    function mockEnableCalled(bool value) external {
        _enableCalled = value;
    }

    function getEnabledTokenPairs() external view returns (address[] memory, address[] memory) {
        return (enabledFromTokens, enabledToTokens);
    }
}
