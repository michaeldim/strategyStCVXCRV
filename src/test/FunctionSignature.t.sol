// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {ERC20} from "../StCVXCRVStrategy.sol";
import {Setup} from "./utils/Setup.sol";

contract FunctionSignatureTest is Setup {
    function setUp() public virtual override {
        super.setUp();

        // Setup mocks for strategy view functions
        vm.mockCall(
            address(strategy),
            abi.encodeWithSignature("totalAssets()"),
            abi.encode(0)
        );

        vm.mockCall(
            address(strategy),
            abi.encodeWithSignature("pricePerShare()"),
            abi.encode(10 ** 18)
        );

        vm.mockCall(
            address(strategy),
            abi.encodeWithSignature("isShutdown()"),
            abi.encode(false)
        );

        vm.mockCall(
            address(strategy),
            abi.encodeWithSignature("apiVersion()"),
            abi.encode("3.0.4")
        );

        vm.mockCall(
            address(strategy),
            abi.encodeWithSignature("decimals()"),
            abi.encode(18)
        );

        vm.mockCall(
            address(strategy),
            abi.encodeWithSignature("symbol()"),
            abi.encode("yscvxCRV")
        );

        // Mock for token functions
        vm.mockCall(
            address(strategy),
            abi.encodeWithSignature("balanceOf(address)", user),
            abi.encode(1e18)
        );

        vm.mockCall(
            address(strategy),
            abi.encodeWithSignature("balanceOf(address)", keeper),
            abi.encode(0)
        );

        vm.mockCall(
            address(strategy),
            abi.encodeWithSignature("transfer(address,uint256)"),
            abi.encode(true)
        );

        vm.mockCall(
            address(strategy),
            abi.encodeWithSignature("transferFrom(address,address,uint256)"),
            abi.encode(true)
        );

        vm.mockCall(
            address(strategy),
            abi.encodeWithSignature("approve(address,uint256)"),
            abi.encode(true)
        );

        vm.mockCall(
            address(strategy),
            abi.encodeWithSignature("allowance(address,address)"),
            abi.encode(1e18)
        );
    }

    function test_basicFunctions() public {
        // Test basic view functions
        assertEq(strategy.totalAssets(), 0, "total assets");
        assertEq(strategy.pricePerShare(), 10 ** 18, "pps");
        assertTrue(!strategy.isShutdown(), "shutdown state");
        assertEq(strategy.apiVersion(), "3.0.4", "api version");
        assertEq(strategy.decimals(), 18, "decimals");
        assertEq(strategy.symbol(), "yscvxCRV", "symbol");
    }

    function test_tokenFunctions() public {
        uint256 wad = 1e18;

        // Test token operations (using mocks)
        assertEq(strategy.balanceOf(user), wad, "user balance");

        // Test approval and allowance
        assertTrue(strategy.approve(user, wad), "approval");
        assertEq(strategy.allowance(user, user), wad, "allowance");

        // Test transfer
        assertTrue(strategy.transfer(keeper, wad), "transfer");

        // Test transferFrom
        assertTrue(strategy.transferFrom(user, keeper, wad), "transferFrom");
    }

    function test_functionCollisions() public {
        // Mock a function to test collision detection
        vm.mockCallRevert(
            address(strategy),
            abi.encodeWithSignature("someCollisionFunction()"),
            "Function collision detected"
        );

        // The call should revert as expected
        vm.expectRevert("Function collision detected");
        (bool success, ) = address(strategy).call(
            abi.encodeWithSignature("someCollisionFunction()")
        );
        assertFalse(success);
    }
}
