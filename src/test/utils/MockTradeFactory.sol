// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockTradeFactory {
    mapping(address => mapping(address => bool)) public routes;

    event RouteEnabled(address fromToken, address toToken);

    function enable(address fromToken, address toToken) external returns (bool) {
        routes[fromToken][toToken] = true;
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
}
