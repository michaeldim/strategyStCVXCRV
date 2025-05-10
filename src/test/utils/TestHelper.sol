// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup} from "./Setup.sol";

contract TestHelper is Setup {
    /**
     * @notice Mock the balanceOf function for an ERC20 token to return a specific amount for a specific address
     * @dev This replaces the need for stdStorage.deal which is causing test failures
     * @param token The token address to mock
     * @param account The account to set balance for
     * @param amount The balance amount to set
     */
    function mockDeal(address token, address account, uint256 amount) internal {
        vm.mockCall(
            token,
            abi.encodeWithSignature("balanceOf(address)", account),
            abi.encode(amount)
        );

        // Also mock the transferFrom function to allow transfers
        vm.mockCall(
            token,
            abi.encodeWithSignature("transferFrom(address,address,uint256)"),
            abi.encode(true)
        );
    }
}
