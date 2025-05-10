

// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {Strategy, ERC20} from "./Strategy.sol";
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";
import {TestStrategy} from "./test/TestStrategy.sol";

contract StrategyFactory {
    event NewStrategy(address indexed strategy, address indexed asset);
    event NewTestStrategy(address indexed strategy, address indexed asset);

    address public immutable emergencyAdmin;
    address public management;
    address public performanceFeeRecipient;
    address public keeper;

    /// @notice Track the deployments. asset => pool => strategy
    mapping(address => address) public deployments;

    constructor(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _emergencyAdmin
    ) {
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
    }

    function newStrategy(
        address _asset,
        string memory _name,
        address _cvxcrv,
        address _crv,
        address _cvx,
        address _crvUsd,
        address _wrapper,
        address _auctionLogic,
        address _tradeFactoryAddress
    ) public returns (address) {
        IStrategyInterface _newStrategy = IStrategyInterface(
            address(new Strategy(_asset, _name, _cvxcrv, _crv, _cvx, _crvUsd, _wrapper, _auctionLogic, _tradeFactoryAddress))
        );
        _newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        _newStrategy.setKeeper(keeper);
        _newStrategy.setPendingManagement(management);
        _newStrategy.setEmergencyAdmin(emergencyAdmin);
        emit NewStrategy(address(_newStrategy), _asset);
        deployments[_asset] = address(_newStrategy);
        return address(_newStrategy);
    }

    function newTestStrategy(
        address _asset,
        string memory _name,
        address _cvxcrv,
        address _crv,
        address _cvx,
        address _crvUsd,
        address _wrapper,
        address _auctionLogic,
        address _tradeFactoryAddress
    ) public returns (address) {
        IStrategyInterface _newStrategy = IStrategyInterface(
            address(new TestStrategy(_asset, _name, _cvxcrv, _crv, _cvx, _crvUsd, _wrapper, _auctionLogic, _tradeFactoryAddress))
        );
        _newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        _newStrategy.setKeeper(keeper);
        _newStrategy.setPendingManagement(management);
        _newStrategy.setEmergencyAdmin(emergencyAdmin);
        emit NewTestStrategy(address(_newStrategy), _asset);
        return address(_newStrategy);
    }
}