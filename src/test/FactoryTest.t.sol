// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {TestHelper} from "./utils/TestHelper.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";
import {StCVXCRVStrategy} from "../StCVXCRVStrategy.sol";
import {TestStrategy} from "./TestStrategy.sol";

/**
 * @title Factory Test
 * @notice Simple test to check if our factory setup is working
 */
contract FactoryTest is TestHelper {
    function setUp() public override {
        // Disable automatic strategy creation
        shouldCreateStrategy = false;

        // Call the parent setUp
        super.setUp();
    }

    function test_factoriesExist() public view {
        // Verify that testStrategyFactory exists
        assertTrue(address(testStrategyFactory) != address(0), "testStrategyFactory should not be zero address");

        // Verify that strategyFactory exists
        assertTrue(address(strategyFactory) != address(0), "strategyFactory should not be zero address");

        // Check if they are different
        assertTrue(address(testStrategyFactory) != address(strategyFactory), "strategyFactory and testStrategyFactory should be different");
    }

    function test_createTestStrategy() public {
        // Create a minimal wrapper address to avoid revert
        address wrapper = address(0x123456);
        address CRV = address(0x1);
        address CVX = address(0x2);
        address CRVUSD = address(0x3);

        // Mock necessary wrapper functions
        vm.mockCall(wrapper, abi.encodeWithSignature("balanceOf(address)"), abi.encode(uint256(0)));
        vm.mockCall(wrapper, abi.encodeWithSignature("stake(uint256,address)"), abi.encode());
        vm.mockCall(wrapper, abi.encodeWithSignature("withdraw(uint256)"), abi.encode());
        vm.mockCall(wrapper, abi.encodeWithSignature("getReward(address)"), abi.encode());

        // Create a test strategy
        address strategyAddress = testStrategyFactory.newTestStrategy(
            address(asset),
            "Test Strategy",
            address(asset), // CVXCRV same as asset
            CRV,
            CVX,
            CRVUSD,
            wrapper,
            address(0), // Unused auction parameter
            address(0)  // Trade factory address
        );

        // Verify strategy was created
        assertTrue(strategyAddress != address(0), "Strategy should be created successfully");

        // Verify it's a TestStrategy
        assertTrue(
            TestStrategy(strategyAddress).isMock() == true,
            "Should be a TestStrategy"
        );
    }
}
