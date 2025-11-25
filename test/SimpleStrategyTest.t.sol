// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/StCVXCRVStrategy.sol";
import "../src/interfaces/IAuction.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleStrategyTest is Test {
    StCVXCRVStrategy public strategy;
    address public constant CVXCRV = 0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7;
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    
    function setUp() public {
        // Fork mainnet
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        
        // Deploy strategy
        strategy = new StCVXCRVStrategy(CVXCRV, "Test cvxCRV Strategy");
    }
    
    function testManualAuctionKicking() public {
        // Test that manual auction kicking works without reward token tracking

        // Set up a mock auction that returns correct want/receiver
        MockAuction mockAuction = new MockAuction(address(strategy));

        vm.startPrank(address(this)); // Use test contract as management for simplicity
        strategy.setAuction(address(mockAuction));
        vm.stopPrank();

        // Test that auction is set
        assertEq(strategy.auction(), address(mockAuction));
    }
    
    function testKickAuctionForToken() public {
        // Test kicking an auction for a specific token
        MockAuction mockAuction = new MockAuction(address(strategy));

        vm.startPrank(address(this)); // Use test contract as management for simplicity
        strategy.setAuction(address(mockAuction));
        strategy.setMinAmountToSell(CRV, 50e18); // Set minimum threshold
        vm.stopPrank();

        // Give strategy some tokens to auction
        deal(CRV, address(strategy), 100e18);

        // Kick auction as keeper
        vm.prank(address(this)); // Assuming test contract is keeper
        strategy.kickAuction(CRV);
    }
}

// Mock auction for testing
contract MockAuction is IAuction {
    address public constant CVXCRV = 0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7;
    address public immutable _receiver;

    constructor(address receiver_) {
        _receiver = receiver_;
    }

    function want() external pure returns (address) {
        return CVXCRV;
    }

    function receiver() external view returns (address) {
        return _receiver;
    }

    function kick(address) external pure returns (uint256) {
        return 1;
    }

    function kickable(address) external pure returns (uint256) {
        return type(uint256).max;
    }
}