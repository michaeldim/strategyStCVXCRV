// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {StCVXCRVStrategy} from "../StCVXCRVStrategy.sol";
import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {ITokenizedStrategy} from "@tokenized-strategy/interfaces/ITokenizedStrategy.sol";
import {IFactory} from "@tokenized-strategy/interfaces/IFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAuction} from "../interfaces/IAuction.sol";
import {ICvxCrvStakingWrapper} from "../interfaces/ICvxCrvStakingWrapper.sol";

contract MockAuction {
    address public want;
    address public receiver;

    constructor(address _want, address _receiver) {
        want = _want;
        receiver = _receiver;
    }

    function kick(address) external pure returns (uint256) {
        return 1;
    }
}

// Helper contract to test internal functions
contract StrategyHarness is StCVXCRVStrategy {
    constructor(address _asset, string memory _name) StCVXCRVStrategy(_asset, _name) {}

    // Expose internal function for testing
    function exposed_kickAuctionsIfNeeded() external {
        _kickAuctionsIfNeeded();
    }
}

contract AuctionDoSProtectionTest is Test {
    StCVXCRVStrategy internal _strategy;
    ITokenizedStrategy public strategy;
    StrategyHarness public harness;
    address public management;
    address public keeper;
    address public attacker;

    // Token addresses
    address constant CVXCRV = 0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7;
    address constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;

    MockAuction public auction;

    bool public isForkTest;

    function _reportAsManagement() internal returns (uint256 profit, uint256 loss) {
        vm.prank(management);
        return strategy.report();
    }

    // External function to attempt fork (for try/catch)
    function attemptFork(string memory rpcUrl) external returns (bool) {
        vm.createSelectFork(rpcUrl);
        return true;
    }

    function setUp() public {
        // Check if we're already on a fork (e.g., from --fork-url flag)
        if (block.chainid == 1) {
            // We're on mainnet fork
            isForkTest = true;
        } else {
            // Try to fork mainnet if ETH_RPC_URL is available
            string memory rpcUrl = vm.envOr("ETH_RPC_URL", string(""));

            if (bytes(rpcUrl).length == 0) {
                // No RPC URL available, skip tests
                isForkTest = false;
                return;
            }

            // Only try to fork if we have a valid RPC URL
            try this.attemptFork(rpcUrl) returns (bool success) {
                isForkTest = success;
            } catch {
                isForkTest = false;
                return;
            }
        }

        if (!isForkTest) {
            return;
        }

        management = makeAddr("management");
        keeper = makeAddr("keeper");
        attacker = makeAddr("attacker");

        // Deploy strategy as management (which automatically makes deployer the management)
        vm.startPrank(management);
        _strategy = new StCVXCRVStrategy(CVXCRV, "StCVXCRV Strategy");
        // Cast to ITokenizedStrategy as recommended by Yearn docs
        strategy = ITokenizedStrategy(address(_strategy));

        // Mock the factory protocol fee config so TokenizedStrategy.report() succeeds in tests.
        // FACTORY is immutable in TokenizedStrategy, so we use the known mainnet address
        address factory = 0x770D0d1Fb036483Ed4AbB6d53c1C88fb277D812F;
        vm.mockCall(
            factory,
            abi.encodeWithSelector(IFactory.protocol_fee_config.selector),
            abi.encode(uint16(0), address(0))
        );

        // Some TokenizedStrategy versions read the factory back for runtime asserts.
        vm.mockCall(address(strategy), abi.encodeWithSelector(bytes4(keccak256("FACTORY()"))), abi.encode(factory));

        // Get wrapper address from strategy
        address wrapper = address(_strategy.WRAPPER());

        // Mock reward calls on the wrapper to avoid reverting when the strategy harvests with no stake.
        vm.mockCall(wrapper, abi.encodeWithSelector(bytes4(keccak256("getReward(address)")), address(strategy)), "");

        // Mock balanceOf to return 0 (no staked balance)
        vm.mockCall(
            wrapper,
            abi.encodeWithSelector(bytes4(keccak256("balanceOf(address)")), address(strategy)),
            abi.encode(uint256(0))
        );

        // Mock reward metadata so auto-kicks operate deterministically in tests.
        vm.mockCall(
            wrapper,
            abi.encodeWithSelector(ICvxCrvStakingWrapper.rewardLength.selector),
            abi.encode(uint256(3))
        );
        vm.mockCall(
            wrapper,
            abi.encodeWithSelector(ICvxCrvStakingWrapper.rewards.selector, uint256(0)),
            abi.encode(CRV, uint8(0), uint128(0), uint128(0))
        );
        vm.mockCall(
            wrapper,
            abi.encodeWithSelector(ICvxCrvStakingWrapper.rewards.selector, uint256(1)),
            abi.encode(CVX, uint8(0), uint128(0), uint128(0))
        );
        vm.mockCall(
            wrapper,
            abi.encodeWithSelector(ICvxCrvStakingWrapper.rewards.selector, uint256(2)),
            abi.encode(CRVUSD, uint8(0), uint128(0), uint128(0))
        );

        // Setup auction
        auction = new MockAuction(CVXCRV, address(strategy));
        _strategy.setAuction(address(auction));

        // Add keeper
        strategy.setKeeper(keeper);

        // Verify strategy wrapper is set
        assertEq(address(_strategy.WRAPPER()), 0xaa0C3f5F7DFD688C6E646F66CD2a6B66ACdbE434, "Wrapper should be set");

        vm.stopPrank();
    }

    // Modifier to skip tests if not on a fork
    modifier requiresFork() {
        // Skip if no fork available OR if in CI environment
        string memory ciEnv = vm.envOr("CI", string(""));
        bool isCI = bytes(ciEnv).length > 0;

        if (!isForkTest || isCI) {
            vm.skip(true);
        }
        _;
    }

    // ==================== DoS Protection Tests ====================

    function test_auctionTrigger_preventsDustWithoutThreshold() public requiresFork {
        // Attacker sends 1 wei of CRV to strategy
        deal(CRV, attacker, 1);
        vm.prank(attacker);
        IERC20(CRV).transfer(address(strategy), 1);

        // auctionTrigger should return false when minAmount is 0
        (bool shouldTrigger, bytes memory data) = _strategy.auctionTrigger(CRV);
        assertFalse(shouldTrigger, "Should not trigger for dust without threshold");
        assertEq(data, bytes("Min amount not set"), "Should return correct error message");
    }

    function test_auctionTrigger_triggersWithThresholdMet() public requiresFork {
        // Set threshold
        vm.prank(management);
        _strategy.setMinAmountToSell(CRV, 100e18);

        // Give strategy enough CRV
        deal(CRV, address(strategy), 150e18);

        // Should trigger
        (bool shouldTrigger, bytes memory data) = _strategy.auctionTrigger(CRV);
        assertTrue(shouldTrigger, "Should trigger when threshold met");

        // The data should be abi.encodeCall(strategy.kickAuction, (CRV))
        // Verify it contains the correct function selector
        bytes4 expectedSelector = _strategy.kickAuction.selector;
        bytes4 actualSelector = bytes4(data);
        assertEq(actualSelector, expectedSelector, "Should encode kickAuction selector");
    }

    function test_auctionTrigger_doesNotTriggerBelowThreshold() public requiresFork {
        // Set threshold
        vm.prank(management);
        _strategy.setMinAmountToSell(CRV, 100e18);

        // Give strategy less than threshold
        deal(CRV, address(strategy), 50e18);

        // Should not trigger
        (bool shouldTrigger, bytes memory data) = _strategy.auctionTrigger(CRV);
        assertFalse(shouldTrigger, "Should not trigger below threshold");
        assertEq(data, bytes("Not enough kickable"), "Should return correct error message");
    }

    function test_auctionTrigger_preventsAuctioningAsset() public requiresFork {
        // Try to auction the strategy's asset
        (bool shouldTrigger, bytes memory data) = _strategy.auctionTrigger(CVXCRV);
        assertFalse(shouldTrigger, "Should not auction strategy asset");
        assertEq(data, bytes("Invalid token"), "Should return invalid token error");
    }

    function test_auctionTrigger_noAuctionSet() public requiresFork {
        // Deploy new strategy without auction
        vm.prank(management);
        StCVXCRVStrategy newStrategy = new StCVXCRVStrategy(CVXCRV, "Test");

        (bool shouldTrigger, bytes memory data) = newStrategy.auctionTrigger(CRV);
        assertFalse(shouldTrigger, "Should not trigger without auction");
        assertEq(data, bytes("No auction set"), "Should return no auction error");
    }

    // ==================== Auto Kick Tests ====================

    function test_autoKickAuctions_defaultDisabled() public requiresFork {
        assertFalse(_strategy.autoKickAuctions(), "Auto kick should be disabled by default");
    }

    function test_autoKickAuctions_onlyKicksWithThreshold() public requiresFork {
        // Enable auto kick
        vm.startPrank(management);
        _strategy.setAutoKickAuctions(true);
        _strategy.setMinAmountToSell(CRV, 100e18);
        vm.stopPrank();

        // Give strategy CRV below threshold
        deal(CRV, address(strategy), 50e18);

        // Verify auctionTrigger correctly returns false for below threshold
        (bool shouldTrigger, bytes memory data) = _strategy.auctionTrigger(CRV);
        assertFalse(shouldTrigger, "Should not trigger below threshold");
        assertEq(data, bytes("Not enough kickable"), "Should return correct message");

        // Verify CRV remains in strategy
        assertEq(IERC20(CRV).balanceOf(address(strategy)), 50e18, "CRV should remain in strategy");
    }

    function test_kickAuctionsIfNeeded_directly() public requiresFork {
        // Deploy harness to test internal function
        vm.prank(management);
        harness = new StrategyHarness(CVXCRV, "Test Harness");

        // Setup mock auction
        MockAuction trackableAuction = new MockAuction(CVXCRV, address(harness));

        // Configure harness
        vm.startPrank(management);
        harness.setAuction(address(trackableAuction));
        harness.setMinAmountToSell(CRV, 100e18);
        harness.setMinAmountToSell(CVX, 50e18);
        vm.stopPrank();

        // Mock the wrapper rewards for harness
        vm.mockCall(
            address(harness.WRAPPER()),
            abi.encodeWithSelector(ICvxCrvStakingWrapper.rewardLength.selector),
            abi.encode(uint256(2))
        );
        vm.mockCall(
            address(harness.WRAPPER()),
            abi.encodeWithSelector(ICvxCrvStakingWrapper.rewards.selector, uint256(0)),
            abi.encode(CRV, uint8(0), uint128(0), uint128(0))
        );
        vm.mockCall(
            address(harness.WRAPPER()),
            abi.encodeWithSelector(ICvxCrvStakingWrapper.rewards.selector, uint256(1)),
            abi.encode(CVX, uint8(0), uint128(0), uint128(0))
        );

        // Give harness tokens above threshold
        deal(CRV, address(harness), 150e18);
        deal(CVX, address(harness), 100e18);

        // Call the internal function directly
        harness.exposed_kickAuctionsIfNeeded();

        // Check tokens were sent to auction
        assertEq(IERC20(CRV).balanceOf(address(trackableAuction)), 150e18, "CRV should be sent to auction");
        assertEq(IERC20(CVX).balanceOf(address(trackableAuction)), 100e18, "CVX should be sent to auction");
        assertEq(IERC20(CRV).balanceOf(address(harness)), 0, "Harness should have no CRV");
        assertEq(IERC20(CVX).balanceOf(address(harness)), 0, "Harness should have no CVX");
    }

    function test_autoKickAuctions_kicksWhenEnabled() public requiresFork {
        // Setup mock auction that we can track
        MockAuction trackableAuction = new MockAuction(CVXCRV, address(strategy));

        // Enable auto kick and set threshold
        vm.startPrank(management);
        _strategy.setAuction(address(trackableAuction));
        _strategy.setAutoKickAuctions(true);
        _strategy.setMinAmountToSell(CRV, 100e18);
        vm.stopPrank();

        // Give strategy enough CRV
        deal(CRV, address(strategy), 150e18);

        // Test that autoKickAuctions is enabled
        assertTrue(_strategy.autoKickAuctions(), "Auto kick should be enabled");
        assertEq(_strategy.auction(), address(trackableAuction), "Auction should be set");

        // Verify the auction trigger would fire
        (bool shouldTrigger, ) = _strategy.auctionTrigger(CRV);
        assertTrue(shouldTrigger, "Should trigger above threshold");

        // Manually kick the auction
        vm.prank(keeper);
        _strategy.kickAuction(CRV);

        // CRV should be sent to auction
        assertEq(IERC20(CRV).balanceOf(address(trackableAuction)), 150e18, "CRV should be sent to auction");
        assertEq(IERC20(CRV).balanceOf(address(strategy)), 0, "Strategy should have no CRV");
    }

    // ==================== Minimum Amount Tests ====================

    function test_setMinAmountToSell() public requiresFork {
        vm.prank(management);
        _strategy.setMinAmountToSell(CRV, 100e18);
        assertEq(_strategy.minAmountToSell(CRV), 100e18, "Min amount should be set");
    }

    function test_setAutoKickAuctions() public requiresFork {
        vm.prank(management);
        _strategy.setAutoKickAuctions(true);
        assertTrue(_strategy.autoKickAuctions(), "Auto kick should be enabled");
    }

    // ==================== Manual Kick Tests ====================

    function test_kickAuction() public requiresFork {
        deal(CRV, address(strategy), 100e18);

        // Keeper can kick
        vm.prank(keeper);
        _strategy.kickAuction(CRV);

        assertEq(IERC20(CRV).balanceOf(address(auction)), 100e18, "CRV should be sent to auction");
    }

    function test_kickAuction_cannotKickAsset() public requiresFork {
        vm.prank(keeper);
        vm.expectRevert("Cannot auction strategy asset");
        _strategy.kickAuction(CVXCRV);
    }

    function test_kickAuction_requiresBalance() public requiresFork {
        vm.prank(keeper);
        vm.expectRevert("No tokens to auction");
        _strategy.kickAuction(CRV);
    }

    // ==================== Integration Tests ====================

    function test_fullDoSProtection_scenario() public requiresFork {
        // Setup thresholds for all reward tokens
        vm.startPrank(management);
        _strategy.setMinAmountToSell(CRV, 100e18);
        _strategy.setMinAmountToSell(CVX, 50e18);
        _strategy.setMinAmountToSell(CRVUSD, 100e18);
        _strategy.setAutoKickAuctions(true);
        vm.stopPrank();

        // Attacker tries to grief with dust amounts
        deal(CRV, attacker, 1);
        deal(CVX, attacker, 1);
        deal(CRVUSD, attacker, 1);

        vm.startPrank(attacker);
        IERC20(CRV).transfer(address(strategy), 1);
        IERC20(CVX).transfer(address(strategy), 1);
        IERC20(CRVUSD).transfer(address(strategy), 1);
        vm.stopPrank();

        // Check auction triggers return false for all dust
        (bool shouldTriggerCRV, ) = _strategy.auctionTrigger(CRV);
        (bool shouldTriggerCVX, ) = _strategy.auctionTrigger(CVX);
        (bool shouldTriggerCRVUSD, ) = _strategy.auctionTrigger(CRVUSD);

        assertFalse(shouldTriggerCRV, "CRV dust should not trigger");
        assertFalse(shouldTriggerCVX, "CVX dust should not trigger");
        assertFalse(shouldTriggerCRVUSD, "crvUSD dust should not trigger");

        // Dust remains in strategy (not sent to auction)
        assertEq(IERC20(CRV).balanceOf(address(strategy)), 1, "CRV dust should remain");
        assertEq(IERC20(CVX).balanceOf(address(strategy)), 1, "CVX dust should remain");
        assertEq(IERC20(CRVUSD).balanceOf(address(strategy)), 1, "crvUSD dust should remain");
    }

    function test_multipleRewardTokens_aboveThreshold() public requiresFork {
        // Setup thresholds
        vm.startPrank(management);
        _strategy.setMinAmountToSell(CRV, 100e18);
        _strategy.setMinAmountToSell(CVX, 50e18);
        _strategy.setAutoKickAuctions(true);
        vm.stopPrank();

        // Give strategy rewards above threshold
        deal(CRV, address(strategy), 200e18);
        deal(CVX, address(strategy), 100e18);

        // Both should trigger
        (bool shouldTriggerCRV, ) = _strategy.auctionTrigger(CRV);
        (bool shouldTriggerCVX, ) = _strategy.auctionTrigger(CVX);

        assertTrue(shouldTriggerCRV, "CRV should trigger");
        assertTrue(shouldTriggerCVX, "CVX should trigger");

        // Manually kick both auctions
        vm.startPrank(keeper);
        _strategy.kickAuction(CRV);
        _strategy.kickAuction(CVX);
        vm.stopPrank();

        // Both tokens sent to auction
        assertEq(IERC20(CRV).balanceOf(address(auction)), 200e18, "CRV should be auctioned");
        assertEq(IERC20(CVX).balanceOf(address(auction)), 100e18, "CVX should be auctioned");
    }
}
