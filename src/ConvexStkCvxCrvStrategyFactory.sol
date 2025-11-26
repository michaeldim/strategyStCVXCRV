// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {ConvexStkCvxCrvStrategy} from "./ConvexStkCvxCrvStrategy.sol";
import {ITokenizedStrategy} from "@tokenized-strategy/interfaces/ITokenizedStrategy.sol";

/**
 * @title ConvexStkCvxCrvStrategyFactory
 * @notice Factory for deploying ConvexStkCvxCrvStrategy contracts
 * @dev Deploys strategies with pre-configured management, keeper, and fee settings
 */
contract ConvexStkCvxCrvStrategyFactory {
    event NewStrategy(address indexed strategy, address indexed asset);

    address public immutable emergencyAdmin;
    address public immutable management;
    address public immutable performanceFeeRecipient;
    address public immutable keeper;

    /// @notice Track deployments: asset => strategy
    mapping(address => address) public deployments;

    constructor(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _emergencyAdmin
    ) {
        require(_management != address(0), "Management cannot be zero address");
        require(_performanceFeeRecipient != address(0), "Fee recipient cannot be zero address");
        require(_keeper != address(0), "Keeper cannot be zero address");
        require(_emergencyAdmin != address(0), "Emergency admin cannot be zero address");

        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
    }

    /**
     * @notice Deploy a new ConvexStkCvxCrvStrategy
     * @param _asset The asset token (cvxCRV)
     * @param _name Name for the strategy
     * @return strategyAddress Address of the deployed strategy
     */
    function newStrategy(address _asset, string memory _name) external returns (address strategyAddress) {
        // Ensure we don't already have a deployment for this asset
        require(deployments[_asset] == address(0), "Strategy already exists for this asset");

        // Prevent reentrancy by setting to non-zero
        deployments[_asset] = address(1);

        // Deploy strategy
        ConvexStkCvxCrvStrategy strategy = new ConvexStkCvxCrvStrategy(_asset, _name);
        strategyAddress = address(strategy);

        // Update deployment mapping
        deployments[_asset] = strategyAddress;

        // Configure via ITokenizedStrategy interface
        ITokenizedStrategy tokenized = ITokenizedStrategy(strategyAddress);
        tokenized.setPerformanceFeeRecipient(performanceFeeRecipient);
        tokenized.setKeeper(keeper);
        tokenized.setPendingManagement(management);
        tokenized.setEmergencyAdmin(emergencyAdmin);

        emit NewStrategy(strategyAddress, _asset);
    }

    /**
     * @notice Check if a strategy exists for an asset
     * @param _asset The asset to check
     * @return True if a strategy exists
     */
    function isDeployed(address _asset) external view returns (bool) {
        return deployments[_asset] != address(0) && deployments[_asset] != address(1);
    }
}
