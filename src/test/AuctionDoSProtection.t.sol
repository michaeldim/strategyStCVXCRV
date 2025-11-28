// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {CvxCrvCompounder} from "../CvxCrvCompounder.sol";
import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {ITokenizedStrategy} from "@tokenized-strategy/interfaces/ITokenizedStrategy.sol";
import {IFactory} from "@tokenized-strategy/interfaces/IFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICvxCrvStakingWrapper} from "../interfaces/ICvxCrvStakingWrapper.sol";

contract MockAuction {
    address public want;
    address public receiver;

    constructor(address _want, address _receiver) {
        want = _want;
        receiver = _receiver;
    }

    function kick(address _token) external view returns (uint256) {
        // Simulate real auction behavior - revert if nothing to kick
        uint256 balance = IERC20(_token).balanceOf(address(this));
        require(balance > 0, "nothing to kick");
        return balance;
    }

    function kickable(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function isActive(address) external pure returns (bool) {
        return false;
    }

    function available(address) external pure returns (uint256) {
        return 0;
    }
}

contract AuctionDoSProtectionTest is Test {
    CvxCrvCompounder internal _strategy;
    ITokenizedStrategy public strategy;
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
        _strategy = new CvxCrvCompounder(CVXCRV, "StCVXCRV Strategy");
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

        // Mock reward metadata
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

        // Setup auction (no registry verification needed - trust management)
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
        // kickable() returns 0 because tokenMinAmountToSell is not set
        (bool shouldTrigger, bytes memory data) = _strategy.auctionTrigger(CRV);
        assertFalse(shouldTrigger, "Should not trigger for dust without threshold");
        assertEq(data, bytes("not enough kickable"), "Should return correct error message");
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

        // Should not trigger - kickable() returns 0 when below threshold
        (bool shouldTrigger, bytes memory data) = _strategy.auctionTrigger(CRV);
        assertFalse(shouldTrigger, "Should not trigger below threshold");
        assertEq(data, bytes("not enough kickable"), "Should return correct error message");
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
        CvxCrvCompounder newStrategy = new CvxCrvCompounder(CVXCRV, "Test");

        (bool shouldTrigger, bytes memory data) = newStrategy.auctionTrigger(CRV);
        assertFalse(shouldTrigger, "Should not trigger without auction");
        assertEq(data, bytes("No auction set"), "Should return no auction error");
    }

    // ==================== Minimum Amount Tests ====================

    function test_setMinAmountToSell() public requiresFork {
        vm.prank(management);
        _strategy.setMinAmountToSell(CRV, 100e18);
        assertEq(_strategy.tokenMinAmountToSell(CRV), 100e18, "Min amount should be set");
    }

    // ==================== Manual Kick Tests ====================

    function test_kickAuction_permissionless() public requiresFork {
        // Set threshold
        vm.prank(management);
        _strategy.setMinAmountToSell(CRV, 100e18);

        deal(CRV, address(strategy), 150e18);

        // Keeper can kick when threshold is met
        vm.prank(keeper);
        _strategy.kickAuction(CRV);

        assertEq(IERC20(CRV).balanceOf(address(auction)), 150e18, "CRV should be sent to auction");
    }

    function test_kickAuction_cannotKickAsset() public requiresFork {
        vm.prank(keeper);
        vm.expectRevert(CvxCrvCompounder.CannotAuctionAsset.selector);
        _strategy.kickAuction(CVXCRV);
    }

    function test_kickAuction_withoutThreshold_stillTransfers() public requiresFork {
        // No threshold set - kickable() returns 0 for automation
        // But manual kickAuction() calls still work (permissionless)
        deal(CRV, address(strategy), 100e18);

        // kickAuction is permissionless - it will transfer tokens even without threshold
        // The protection is that auctionTrigger() returns false, so automation won't call it
        vm.prank(keeper);
        _strategy.kickAuction(CRV);

        // Tokens were transferred to auction
        assertEq(IERC20(CRV).balanceOf(address(auction)), 100e18, "CRV should be sent to auction");
    }

    function test_kickAuction_belowThreshold_stillTransfers() public requiresFork {
        // Set threshold
        vm.prank(management);
        _strategy.setMinAmountToSell(CRV, 100e18);

        // Balance below threshold - kickable() returns 0 for automation
        // But manual kickAuction() calls still work
        deal(CRV, address(strategy), 50e18);

        vm.prank(keeper);
        _strategy.kickAuction(CRV);

        // Tokens were transferred to auction (permissionless behavior)
        assertEq(IERC20(CRV).balanceOf(address(auction)), 50e18, "CRV should be sent to auction");
    }

    // ==================== Integration Tests ====================

    function test_fullDoSProtection_scenario() public requiresFork {
        // Setup thresholds for all reward tokens
        vm.startPrank(management);
        _strategy.setMinAmountToSell(CRV, 100e18);
        _strategy.setMinAmountToSell(CVX, 50e18);
        _strategy.setMinAmountToSell(CRVUSD, 100e18);
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
        // This is the key DoS protection - automation won't trigger for dust
        (bool shouldTriggerCRV, ) = _strategy.auctionTrigger(CRV);
        (bool shouldTriggerCVX, ) = _strategy.auctionTrigger(CVX);
        (bool shouldTriggerCRVUSD, ) = _strategy.auctionTrigger(CRVUSD);

        assertFalse(shouldTriggerCRV, "CRV dust should not trigger");
        assertFalse(shouldTriggerCVX, "CVX dust should not trigger");
        assertFalse(shouldTriggerCRVUSD, "crvUSD dust should not trigger");

        // Note: kickAuction() is permissionless and will transfer dust if called manually
        // The DoS protection is that auctionTrigger() returns false, preventing automation
        // from wasting gas on uneconomical auctions. Manual calls are still possible but
        // would cost the caller gas without benefit (no MEV profit from dust amounts).
    }

    function test_multipleRewardTokens_aboveThreshold() public requiresFork {
        // Setup thresholds
        vm.startPrank(management);
        _strategy.setMinAmountToSell(CRV, 100e18);
        _strategy.setMinAmountToSell(CVX, 50e18);
        vm.stopPrank();

        // Give strategy rewards above threshold
        deal(CRV, address(strategy), 200e18);
        deal(CVX, address(strategy), 100e18);

        // Both should trigger
        (bool shouldTriggerCRV, ) = _strategy.auctionTrigger(CRV);
        (bool shouldTriggerCVX, ) = _strategy.auctionTrigger(CVX);

        assertTrue(shouldTriggerCRV, "CRV should trigger");
        assertTrue(shouldTriggerCVX, "CVX should trigger");

        // Keeper can kick both auctions
        vm.startPrank(keeper);
        _strategy.kickAuction(CRV);
        _strategy.kickAuction(CVX);
        vm.stopPrank();

        // Both tokens sent to auction
        assertEq(IERC20(CRV).balanceOf(address(auction)), 200e18, "CRV should be auctioned");
        assertEq(IERC20(CVX).balanceOf(address(auction)), 100e18, "CVX should be auctioned");
    }

    // ==================== Auction Configuration Tests ====================

    function test_setAuction_allowsZeroAddress() public requiresFork {
        // Should be able to unset auction
        vm.prank(management);
        _strategy.setAuction(address(0));
        assertEq(_strategy.auction(), address(0), "Should unset auction");
    }
}
