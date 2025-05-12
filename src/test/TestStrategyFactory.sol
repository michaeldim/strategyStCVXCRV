// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";
import {TestStrategy} from "./TestStrategy.sol";

/**
 * @title TestStrategyFactory
 * @notice Factory contract specifically for deploying test strategies
 * @dev This contract is separated from the main StrategyFactory to reduce deployment costs
 */
contract TestStrategyFactory {
    event NewTestStrategy(address indexed strategy, address indexed asset);

    address public immutable emergencyAdmin;
    address public immutable management;
    address public immutable performanceFeeRecipient;
    address public immutable keeper;

    constructor(address _management, address _performanceFeeRecipient, address _keeper, address _emergencyAdmin) {
        require(_management != address(0), "Management cannot be zero address");
        require(_performanceFeeRecipient != address(0), "Fee recipient cannot be zero address");
        require(_keeper != address(0), "Keeper cannot be zero address");
        require(_emergencyAdmin != address(0), "Emergency admin cannot be zero address");

        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
    }

    function newTestStrategy(
        address _asset,
        string memory _name,
        address _cvxcrv,
        address _crv,
        address _cvx,
        address _crvUsd,
        address _wrapper,
        address, // Unused auction parameter (kept for compatibility)
        address _tradeFactoryAddress
    ) public returns (address) {
        // Create the strategy
        IStrategyInterface _newStrategy = IStrategyInterface(
            address(
                new TestStrategy(
                    _asset,
                    _name,
                    _cvxcrv,
                    _crv,
                    _cvx,
                    _crvUsd,
                    _wrapper,
                    address(0), // unused auction address
                    _tradeFactoryAddress
                )
            )
        );

        // Save the address
        address strategyAddress = address(_newStrategy);

        // For testing only, don't make external calls that might revert
        // Instead, we let the tests configure these separately
        // This avoids issues with mocks and permissions during test setup

        // Emit event
        emit NewTestStrategy(strategyAddress, _asset);

        return strategyAddress;
    }
}
