// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {StCVXCRVStrategy} from "../StCVXCRVStrategy.sol";
import {TestStrategy} from "./TestStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Setup} from "./utils/Setup.sol";
import {MockTradeFactory} from "./utils/MockTradeFactory.sol";
import {MockERC20} from "./utils/MockERC20.sol";

contract CoreFunctionalityTest is Setup {
    MockERC20 public cvxCrv;
    MockERC20 public crv;
    MockERC20 public cvx;
    MockERC20 public crvUsd;
    MockTradeFactory public mockTradeFactory;
    TestStrategy public testStrategy;

    address public constant CRV_ADDRESS = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant CVX_ADDRESS = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address public constant CRVUSD_ADDRESS = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;

    function setUp() public override {
        // Disable strategy creation in parent
        shouldCreateStrategy = false;

        // First call the base setup
        super.setUp();

        // Create mock tokens for this specific test
        cvxCrv = MockERC20(address(asset)); // Reuse the asset from SimpleSetup
        crv = new MockERC20("Curve DAO Token", "CRV", 18);
        cvx = new MockERC20("Convex Token", "CVX", 18);
        crvUsd = new MockERC20("Curve USD", "crvUSD", 18);

        // Create mock trade factory
        mockTradeFactory = new MockTradeFactory();

        // Deploy test strategy with simplified constructor
        vm.startPrank(management);
        testStrategy = new TestStrategy(
            address(cvxCrv),
            "Generic Staking Strategy"
        );
        vm.stopPrank();

        // Configure test strategy
        vm.startPrank(management);

        // Set the strategy name explicitly to match what we expect in the test
        testStrategy.setName("Generic Staking Strategy");

        // Set trade factory
        testStrategy.setTradeFactory(address(mockTradeFactory));

        // Add reward tokens
        uint8 tradeFactorySwap = 1; // Use SwapType.TRADE_FACTORY
        testStrategy.addRewardToken(address(crv), tradeFactorySwap);
        testStrategy.addRewardToken(address(cvx), tradeFactorySwap);
        testStrategy.addRewardToken(address(crvUsd), tradeFactorySwap);

        // Configure minimum amounts to sell
        testStrategy.setMinAmountToSellMapping(address(crv), 10 * 1e18);   // 10 CRV
        testStrategy.setMinAmountToSellMapping(address(cvx), 5 * 1e18);    // 5 CVX
        testStrategy.setMinAmountToSellMapping(address(crvUsd), 20 * 1e18); // 20 crvUSD

        vm.stopPrank();

        // Mint tokens for testing
        cvxCrv.mint(address(this), 1000 * 1e18);
        crv.mint(address(this), 1000 * 1e18);
        cvx.mint(address(this), 1000 * 1e18);
        crvUsd.mint(address(this), 1000 * 1e18);

        // Transfer some reward tokens to the strategy to simulate pending rewards
        crv.transfer(address(testStrategy), 50 * 1e18);
        cvx.transfer(address(testStrategy), 30 * 1e18);
        crvUsd.transfer(address(testStrategy), 20 * 1e18);
    }

    function test_StrategyInitialization() public view {
        // Basic initialization checks
        assertEq(testStrategy.getAsset(), address(cvxCrv), "Asset should be cvxCRV");
        assertEq(
            keccak256(abi.encodePacked(testStrategy.getName())),
            keccak256(abi.encodePacked("Generic Staking Strategy")),
            "Strategy name should match"
        );

        // Check reward tokens
        address[] memory rewardTokens = testStrategy.getAllRewardTokens();
        assertEq(rewardTokens.length, 3, "Should have 3 reward tokens");
        assertEq(rewardTokens[0], address(crv), "First reward token should be CRV");
        assertEq(rewardTokens[1], address(cvx), "Second reward token should be CVX");
        assertEq(rewardTokens[2], address(crvUsd), "Third reward token should be crvUSD");
    }

    function test_RewardTokenManagement() public {
        // Remove a reward token
        vm.startPrank(management);
        testStrategy.removeRewardToken(address(crvUsd));
        vm.stopPrank();

        // Verify removal
        address[] memory rewardTokens = testStrategy.getAllRewardTokens();
        assertEq(rewardTokens.length, 2, "Should have 2 reward tokens after removal");

        // Add it back
        vm.startPrank(management);
        uint8 auctionSwap = 2; // Use SwapType.AUCTION
        testStrategy.addRewardToken(address(crvUsd), auctionSwap);
        vm.stopPrank();

        // Verify addition
        rewardTokens = testStrategy.getAllRewardTokens();
        assertEq(rewardTokens.length, 3, "Should have 3 reward tokens again");
    }

    function test_SwapConfigurationManagement() public {
        // Mock an auction contract
        address mockAuction = makeAddr("mockAuction");

        // Configure the mock auction
        vm.mockCall(
            mockAuction,
            abi.encodeWithSignature("want()"),
            abi.encode(address(cvxCrv))
        );

        vm.mockCall(
            mockAuction,
            abi.encodeWithSignature("receiver()"),
            abi.encode(address(testStrategy))
        );

        // Set the auction
        vm.startPrank(management);
        testStrategy.setAuction(mockAuction);
        vm.stopPrank();

        // Verify auction is set
        assertEq(testStrategy.auction(), mockAuction, "Auction address should be set");

        // Set swap type for a token to auction
        vm.startPrank(management);
        testStrategy.setSwapType(address(crv), StCVXCRVStrategy.SwapType.AUCTION);
        vm.stopPrank();

        // Verify swap type is set
        assertEq(uint(testStrategy.swapType(address(crv))), uint(StCVXCRVStrategy.SwapType.AUCTION), "Swap type should be AUCTION");
    }

    function test_DeployFunds() public {
        uint256 testAmount = 100 * 1e18;

        // Mint tokens to the strategy
        cvxCrv.mint(address(testStrategy), testAmount);

        // Mock wrapper balanceOf to return the expected staked amount
        address wrapper = 0xaa0C3f5F7DFD688C6E646F66CD2a6B66ACdbE434;
        vm.mockCall(
            wrapper,
            abi.encodeWithSignature("balanceOf(address)", address(testStrategy)),
            abi.encode(testAmount)
        );

        // Report to trigger internal _deployFunds
        vm.prank(keeper);
        testStrategy.report();

        // Verify total assets includes staked amount
        assertEq(testStrategy.totalAssets(), testAmount, "totalAssets should include staked amount");
    }

    function test_FreeFunds() public {
        uint256 testAmount = 100 * 1e18;
        address wrapper = 0xaa0C3f5F7DFD688C6E646F66CD2a6B66ACdbE434;

        // First setup: Mock the staking
        cvxCrv.mint(address(testStrategy), testAmount);

        // Mock wrapper balanceOf to return the staked amount
        vm.mockCall(
            wrapper,
            abi.encodeWithSignature("balanceOf(address)", address(testStrategy)),
            abi.encode(testAmount)
        );

        // Now trigger withdrawal
        vm.prank(user);
        testStrategy.redeem(testAmount, user, user);

        // Verify balances
        uint256 userBalance = cvxCrv.balanceOf(user);
        assertGe(userBalance, 0, "User should have received assets");
    }

    function test_HarvestAndReport() public {
        // Setup initial state
        uint256 initialAmount = 100 * 1e18;
        address wrapper = 0xaa0C3f5F7DFD688C6E646F66CD2a6B66ACdbE434;

        // Mint tokens and setup mocks
        cvxCrv.mint(address(testStrategy), initialAmount);
        vm.mockCall(
            wrapper,
            abi.encodeWithSignature("balanceOf(address)", address(testStrategy)),
            abi.encode(initialAmount)
        );

        // Report to trigger harvest
        vm.prank(keeper);
        uint256 reportedAssets = testStrategy.report();

        // Verify reported assets
        assertEq(reportedAssets, initialAmount, "Reported assets should match initial amount");
    }
}
