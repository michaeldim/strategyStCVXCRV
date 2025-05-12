// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";

/**
 * @title Basic Test
 * @notice A minimal test to verify testing framework is working
 */
contract BasicTest is Test {
    function test_Basic() public pure {
        console.log("Basic test is running!");
        assertTrue(true, "This should always pass");
    }
}
