// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {CvxCrvCompounder} from "./CvxCrvCompounder.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

/**
 * @title StrategyFactory
 * @notice Factory for deploying CvxCrvCompounder contracts
 * @dev This contract is streamlined to focus solely on production strategy deployment
 */
contract StrategyFactory {
    event NewStrategy(address indexed strategy, address indexed asset);

    address public immutable emergencyAdmin;
    address public immutable management;
    address public immutable performanceFeeRecipient;
    address public immutable keeper;

    /// @notice Track the deployments. asset => pool => strategy
    mapping(address => address) public deployments;

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

    function newStrategy(
        address _asset,
        string memory _name
    ) public returns (address) {
        // Ensure we don't already have a deployment for this asset
        require(deployments[_asset] == address(0), "Strategy already exists for this asset");

        // Update state variable first - record that we're creating a strategy for this asset
        // Set to a non-zero temporary address to prevent reentrancy
        deployments[_asset] = address(1);

        // Create the strategy
        IStrategyInterface _newStrategy = IStrategyInterface(
            address(
                new CvxCrvCompounder(
                    _asset,
                    _name
                )
            )
        );

        // Get the address
        address strategyAddress = address(_newStrategy);

        // Update with the real address
        deployments[_asset] = strategyAddress;

        // Configure the strategy (external calls)
        _newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        _newStrategy.setKeeper(keeper);
        _newStrategy.setPendingManagement(management);
        _newStrategy.setEmergencyAdmin(emergencyAdmin);

        // Emit event
        emit NewStrategy(strategyAddress, _asset);

        return strategyAddress;
    }
}
