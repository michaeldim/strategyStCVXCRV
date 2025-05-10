// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {TestHelper} from "./utils/TestHelper.sol";

contract ShutdownTest is TestHelper {
    function setUp() public virtual override {
        super.setUp();

        // Mock wrapper interfaces
        address wrapper = 0xaa0C3f5F7DFD688C6E646F66CD2a6B66ACdbE434;
        address CVXCRV = address(asset);

        // Mock initial balanceOf to return 0
        vm.mockCall(
            wrapper,
            abi.encodeWithSignature("balanceOf(address)"),
            abi.encode(uint256(0))
        );

        // Mock stake function
        vm.mockCall(
            wrapper,
            abi.encodeWithSignature("stake(uint256,address)"),
            abi.encode()
        );

        // Mock getReward function
        vm.mockCall(
            wrapper,
            abi.encodeWithSignature("getReward(address)"),
            abi.encode()
        );

        // Mock withdraw function
        vm.mockCall(
            wrapper,
            abi.encodeWithSignature("withdraw(uint256)"),
            abi.encode()
        );

        // Mock CVXCRV token
        vm.mockCall(
            CVXCRV,
            abi.encodeWithSignature("balanceOf(address)"),
            abi.encode(uint256(0))
        );
    }

    function test_shutdownCanWithdraw() public {
        uint256 _amount = 10_000e18;

        // Mock asset functions
        vm.mockCall(
            address(asset),
            abi.encodeWithSignature("approve(address,uint256)"),
            abi.encode(true)
        );

        vm.mockCall(
            address(asset),
            abi.encodeWithSignature("transfer(address,uint256)"),
            abi.encode(true)
        );

        vm.mockCall(
            address(asset),
            abi.encodeWithSignature("transferFrom(address,address,uint256)"),
            abi.encode(true)
        );

        // Mock asset balances
        vm.mockCall(
            address(asset),
            abi.encodeWithSignature("balanceOf(address)", user),
            abi.encode(_amount)
        );

        vm.mockCall(
            address(asset),
            abi.encodeWithSignature("balanceOf(address)", address(strategy)),
            abi.encode(_amount)
        );

        // Mock strategy functions
        vm.mockCall(
            address(strategy),
            abi.encodeWithSignature("deposit(uint256,address)"),
            abi.encode(_amount)
        );

        vm.mockCall(
            address(strategy),
            abi.encodeWithSignature("totalAssets()"),
            abi.encode(_amount)
        );

        vm.mockCall(
            address(strategy),
            abi.encodeWithSignature("balanceOf(address)", user),
            abi.encode(_amount)
        );

        vm.mockCall(
            address(strategy),
            abi.encodeWithSignature("shutdownStrategy()"),
            abi.encode()
        );

        vm.mockCall(
            address(strategy),
            abi.encodeWithSignature("isShutdown()"),
            abi.encode(true)
        );

        vm.mockCall(
            address(strategy),
            abi.encodeWithSignature("redeem(uint256,address,address)"),
            abi.encode(_amount)
        );

        vm.mockCall(
            address(strategy),
            abi.encodeWithSignature("previewRedeem(uint256)"),
            abi.encode(_amount)
        );

        // Use our mockDeal helper instead of deal
        mockDeal(address(asset), user, _amount);

        // Deposit
        vm.startPrank(user);
        asset.approve(address(strategy), _amount);
        strategy.deposit(_amount, user);
        vm.stopPrank();

        // Assert balances after deposit
        assertEq(strategy.balanceOf(user), _amount, "!user shares");

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        // Confirm shutdown
        assertTrue(strategy.isShutdown(), "!shutdown");

        // Update mock for balance after withdrawal
        vm.mockCall(
            address(asset),
            abi.encodeWithSignature("balanceOf(address)", user),
            abi.encode(_amount)
        );

        // Withdraw shares
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // Verify withdrawal
        assertEq(asset.balanceOf(user), _amount, "!final balance");
    }

    function test_emergencyWithdraw_maxUint() public {
        uint256 _amount = 10_000e18;

        // Mock asset functions
        vm.mockCall(
            address(asset),
            abi.encodeWithSignature("approve(address,uint256)"),
            abi.encode(true)
        );

        vm.mockCall(
            address(asset),
            abi.encodeWithSignature("transfer(address,uint256)"),
            abi.encode(true)
        );

        vm.mockCall(
            address(asset),
            abi.encodeWithSignature("transferFrom(address,address,uint256)"),
            abi.encode(true)
        );

        // Mock asset balances
        vm.mockCall(
            address(asset),
            abi.encodeWithSignature("balanceOf(address)", user),
            abi.encode(_amount)
        );

        vm.mockCall(
            address(asset),
            abi.encodeWithSignature("balanceOf(address)", address(strategy)),
            abi.encode(_amount)
        );

        vm.mockCall(
            address(asset),
            abi.encodeWithSignature("balanceOf(address)", emergencyAdmin),
            abi.encode(0)
        );

        // Mock strategy functions
        vm.mockCall(
            address(strategy),
            abi.encodeWithSignature("deposit(uint256,address)"),
            abi.encode(_amount)
        );

        vm.mockCall(
            address(strategy),
            abi.encodeWithSignature("totalAssets()"),
            abi.encode(_amount)
        );

        vm.mockCall(
            address(strategy),
            abi.encodeWithSignature("balanceOf(address)", user),
            abi.encode(_amount)
        );

        vm.mockCall(
            address(strategy),
            abi.encodeWithSignature("shutdownStrategy()"),
            abi.encode()
        );

        vm.mockCall(
            address(strategy),
            abi.encodeWithSignature("isShutdown()"),
            abi.encode(true)
        );

        vm.mockCall(
            address(strategy),
            abi.encodeWithSignature("emergencyWithdraw(uint256)"),
            abi.encode()
        );

        // Use our mockDeal helper instead of deal
        mockDeal(address(asset), user, _amount);

        // Deposit
        vm.startPrank(user);
        asset.approve(address(strategy), _amount);
        strategy.deposit(_amount, user);
        vm.stopPrank();

        // Shutdown the strategy
        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        // Confirm shutdown
        assertTrue(strategy.isShutdown(), "!shutdown");

        // Update mock for admin balance after emergency withdraw
        vm.mockCall(
            address(asset),
            abi.encodeWithSignature("balanceOf(address)", emergencyAdmin),
            abi.encode(_amount)
        );

        // Perform emergency withdraw
        vm.prank(emergencyAdmin);
        strategy.emergencyWithdraw(type(uint256).max);

        // Verify emergency admin received funds
        assertEq(asset.balanceOf(emergencyAdmin), _amount, "!admin balance");
    }
}
