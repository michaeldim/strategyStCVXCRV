// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {StrategyAprOracle} from "../periphery/StrategyAprOracle.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {ConvexStkCvxCrvStrategy} from "../ConvexStkCvxCrvStrategy.sol";
import {IConvexBasicRewards} from "../interfaces/IConvexBasicRewards.sol";
import {IConvexToken} from "../interfaces/IConvexToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Comprehensive Oracle Tests
 * @notice Consolidated test file for Strategy APR Oracle functionality
 * @dev This file combines tests from multiple previous test files:
 *      - Oracle.t.sol
 *      - StrategyAprOracle.t.sol
 *      - Integration.t.sol (oracle-related portions)
 */

// ============================================================================================
// MOCKS AND TEST CONTRACTS
// ============================================================================================

/**
 * @notice Mock Price Oracle with configurable prices
 */
contract MockPriceOracle is IPriceOracle {
    mapping(address => uint256) public prices;

    // Default hard-coded prices for common tokens
    function getUSDPrice(address token) external view override returns (uint256) {
        // If a price is set in the prices mapping, return that
        if (prices[token] > 0) {
            return prices[token];
        }

        // Otherwise return hard-coded defaults for known tokens
        if (token == 0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7) {
            // CVXCRV
            return 0.52e18; // $0.52 for cvxCRV
        } else if (token == 0xD533a949740bb3306d119CC777fa900bA034cd52) {
            // CRV
            return 0.5e18; // $0.50 for CRV
        } else if (token == 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B) {
            // CVX
            return 3e18; // $3.00 for CVX
        } else if (token == 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490) {
            // 3CRV
            return 1.01e18; // $1.01 for 3CRV
        } else if (token == 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E) {
            // CRVUSD
            return 1e18; // $1.00 for CRVUSD
        }

        return 1e18; // Default $1 for any other token
    }

    // Function to configure a token price
    function setTokenPrice(address token, uint256 price) external {
        prices[token] = price;
    }
}

// Extended oracle for testing additional methods
contract TestStrategyAprOracle is StrategyAprOracle {
    constructor(address _priceOracle) StrategyAprOracle(_priceOracle) {}

    // Helper method to get underlying price directly from the price oracle
    function getUnderlyingPrice(address token) public view returns (uint256) {
        return priceOracle.getUSDPrice(token);
    }

    // Helper to calculate reward value per second
    function getRewardValuePerSecond() public view returns (uint256 totalValuePerSecond) {
        (address[] memory tokens, uint256[] memory rates, ) = cvxCrvUtilities.mainRewardRates();
        (address[] memory extraTokens, uint256[] memory extraRates, ) = cvxCrvUtilities.extraRewardRates();

        // Add value from main rewards
        for (uint i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            if (token == THREE_CRV) continue; // Skip 3CRV for test simplicity
            uint256 tokenPrice = priceOracle.getUSDPrice(token);
            totalValuePerSecond += (rates[i] * tokenPrice) / 1e18;
        }

        // Add value from extra rewards
        for (uint i = 0; i < extraTokens.length; i++) {
            address token = extraTokens[i];
            if (token == THREE_CRV) continue; // Skip 3CRV for test simplicity
            uint256 tokenPrice = priceOracle.getUSDPrice(token);
            totalValuePerSecond += (extraRates[i] * tokenPrice) / 1e18;
        }
    }

    // Helper to get reward tokens and rates
    function getRewardTokensAndRates()
        public
        view
        returns (address[] memory tokens, uint256[] memory rates, uint256[] memory groups)
    {
        (address[] memory mainTokens, uint256[] memory mainRates, uint256[] memory mainGroups) = cvxCrvUtilities
            .mainRewardRates();
        (address[] memory extraTokens, uint256[] memory extraRates, uint256[] memory extraGroups) = cvxCrvUtilities
            .extraRewardRates();

        // Combine main and extra tokens
        tokens = new address[](mainTokens.length + extraTokens.length);
        rates = new uint256[](mainRates.length + extraRates.length);
        groups = new uint256[](mainGroups.length + extraGroups.length);

        // Copy main tokens
        for (uint i = 0; i < mainTokens.length; i++) {
            tokens[i] = mainTokens[i];
            rates[i] = mainRates[i];
            groups[i] = mainGroups[i];
        }

        // Copy extra tokens
        for (uint i = 0; i < extraTokens.length; i++) {
            tokens[mainTokens.length + i] = extraTokens[i];
            rates[mainRates.length + i] = extraRates[i];
            groups[mainGroups.length + i] = extraGroups[i];
        }
    }
}

// ============================================================================================
// COMPREHENSIVE ORACLE TESTS
// ============================================================================================

contract OracleTests is Test {
    // Set up common constants
    address public constant STRATEGY = 0x0000000000000000000000000000000000000001; // Mock strategy address
    address public mockStrategy; // Mock strategy for APR calculations

    // Token constants
    address public CVXCRV;
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address public constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address public constant THREE_CRV = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
    address public constant STAKED_CVXCRV = 0xaa0C3f5F7DFD688C6E646F66CD2a6B66ACdbE434;

    // Convex reward contracts
    address public constant CRV_REWARDS = 0x3Fe65692bfCD0e6CF84cB1E7d24108E434A7587e;
    address public constant THREE_CRV_REWARDS = 0x7091dbb7fcbA54569eF1387Ac89Eb2a5C9F6d2EA;
    address public constant EXTRA_CVX_REWARDS = 0x449f2fd99174e1785CF2A1c79E665Fec3dD1DdC6;

    // Test contracts
    TestStrategyAprOracle public aprOracle;
    MockPriceOracle public mockOracle;

    function setUp() public {
        // Initialize default CVXCRV for testing
        CVXCRV = address(0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7);

        // Set up a mock strategy address
        mockStrategy = address(0x1234567890123456789012345678901234567890);

        // Mock CvxCrvUtilities.apr to return a fixed value for testing
        address cvxCrvUtilities = address(0xadd2F542f9FF06405Fabf8CaE4A74bD0FE29c673); // default in StrategyAprOracle

        // Mock the apr function
        vm.mockCall(
            cvxCrvUtilities,
            abi.encodeWithSelector(bytes4(keccak256("apr(uint256,uint256,uint256)"))),
            abi.encode(17.5e16) // 17.5% APR for tests
        );

        // Mock mainRewardRates function
        address[] memory tokens = new address[](1);
        tokens[0] = CRV; // CRV token
        uint256[] memory rates = new uint256[](1);
        rates[0] = 1e18; // 1 token per second
        uint256[] memory groups = new uint256[](1);
        groups[0] = 0; // Group 0

        vm.mockCall(
            cvxCrvUtilities,
            abi.encodeWithSelector(bytes4(keccak256("mainRewardRates()"))),
            abi.encode(tokens, rates, groups)
        );

        // Mock extraRewardRates function
        address[] memory extraTokens = new address[](1);
        extraTokens[0] = CVX; // CVX token
        uint256[] memory extraRates = new uint256[](1);
        extraRates[0] = 0.3e18; // 0.3 token per second
        uint256[] memory extraGroups = new uint256[](1);
        extraGroups[0] = 1; // Group 1

        vm.mockCall(
            cvxCrvUtilities,
            abi.encodeWithSelector(bytes4(keccak256("extraRewardRates()"))),
            abi.encode(extraTokens, extraRates, extraGroups)
        );

        // Create and setup mock price oracle
        mockOracle = new MockPriceOracle();
        mockOracle.setTokenPrice(CVXCRV, 0.52e18); // $0.52 for cvxCRV
        mockOracle.setTokenPrice(CRV, 0.5e18); // $0.50 for CRV
        mockOracle.setTokenPrice(CVX, 3e18); // $3.00 for CVX
        mockOracle.setTokenPrice(THREE_CRV, 1.01e18); // $1.01 for 3CRV
        mockOracle.setTokenPrice(CRVUSD, 1e18); // $1.00 for CRVUSD

        // Create APR Oracle with mock price oracle
        aprOracle = new TestStrategyAprOracle(address(mockOracle));

        // Mock the balanceOf call for STAKED_CVXCRV
        vm.mockCall(
            STAKED_CVXCRV,
            abi.encodeWithSelector(bytes4(keccak256("balanceOf(address)"))),
            abi.encode(1e24) // 1 million tokens staked
        );
    }

    // ============================================================================================
    // BASIC APR TESTS
    // ============================================================================================

    function test_getApr() public view {
        // Test basic APR calculation
        uint256 apr = aprOracle.aprAfterDebtChange(address(mockStrategy), 0);

        // Should return the mocked value from CvxCrvUtilities
        assertEq(apr, 17.5e16, "APR should match the mocked value");
    }

    function test_getAprWithDefaultPrices() public {
        // Create price oracle with hardcoded prices
        MockPriceOracle fallbackOracle = new MockPriceOracle();

        // Create a new oracle instance with a price oracle
        TestStrategyAprOracle defaultPriceOracle = new TestStrategyAprOracle(address(fallbackOracle));

        // Mock the CvxCrvUtilities again for this new oracle instance
        address cvxCrvUtilities = address(0xadd2F542f9FF06405Fabf8CaE4A74bD0FE29c673);
        vm.mockCall(
            cvxCrvUtilities,
            abi.encodeWithSelector(bytes4(keccak256("apr(uint256,uint256,uint256)"))),
            abi.encode(17.5e16) // 17.5% APR for tests
        );

        // Mock the mainRewardRates function for this test
        address[] memory tokens = new address[](1);
        tokens[0] = CRV; // CRV token
        uint256[] memory rates = new uint256[](1);
        rates[0] = 1e18; // 1 token per second
        uint256[] memory groups = new uint256[](1);
        groups[0] = 0; // Group 0

        vm.mockCall(
            cvxCrvUtilities,
            abi.encodeWithSelector(bytes4(keccak256("mainRewardRates()"))),
            abi.encode(tokens, rates, groups)
        );

        // Mock extraRewardRates function
        address[] memory extraTokens = new address[](0);
        uint256[] memory extraRates = new uint256[](0);
        uint256[] memory extraGroups = new uint256[](0);

        vm.mockCall(
            cvxCrvUtilities,
            abi.encodeWithSelector(bytes4(keccak256("extraRewardRates()"))),
            abi.encode(extraTokens, extraRates, extraGroups)
        );

        // Mock the balanceOf call for STAKED_CVXCRV
        vm.mockCall(
            STAKED_CVXCRV,
            abi.encodeWithSelector(bytes4(keccak256("balanceOf(address)"))),
            abi.encode(1e24) // 1 million tokens staked
        );

        // Get APR with default prices
        uint256 apr = defaultPriceOracle.aprAfterDebtChange(address(STRATEGY), 0);

        // Should return 17.5% as mocked
        assertEq(apr, 17.5e16, "APR should match the mocked value even with default prices");
    }

    // ============================================================================================
    // TOKEN PRICE TESTS
    // ============================================================================================

    function test_tokenPrices() public view {
        // Test token price retrieval through the oracle
        uint256 crvPrice = aprOracle.getUnderlyingPrice(CRV);
        uint256 cvxPrice = aprOracle.getUnderlyingPrice(CVX);
        uint256 cvxcrvPrice = aprOracle.getUnderlyingPrice(CVXCRV);

        // Verify token prices match mocked values
        assertEq(crvPrice, 0.5e18, "CRV price should be $0.50");
        assertEq(cvxPrice, 3e18, "CVX price should be $3.00");
        assertEq(cvxcrvPrice, 0.52e18, "cvxCRV price should be $0.52");
    }

    function test_customTokenPrices() public {
        // Update token prices in the mock oracle
        mockOracle.setTokenPrice(CRV, 0.75e18); // $0.75 for CRV
        mockOracle.setTokenPrice(CVX, 4.5e18); // $4.50 for CVX

        // Test token price retrieval with updated prices
        uint256 crvPrice = aprOracle.getUnderlyingPrice(CRV);
        uint256 cvxPrice = aprOracle.getUnderlyingPrice(CVX);

        // Verify token prices match new values
        assertEq(crvPrice, 0.75e18, "CRV price should be updated to $0.75");
        assertEq(cvxPrice, 4.5e18, "CVX price should be updated to $4.50");
    }

    // ============================================================================================
    // REWARD RATE TESTS
    // ============================================================================================

    function test_getRewardTokensAndRates() public view {
        // Get reward tokens and rates from the oracle
        (address[] memory rewardTokens, uint256[] memory rewardRates, uint256[] memory rewardGroups) = aprOracle
            .getRewardTokensAndRates();

        // Verify returned arrays match what we expect
        assertEq(rewardTokens.length, 2, "Should have 2 reward tokens (CRV and CVX)");
        assertEq(rewardRates.length, 2, "Should have 2 reward rates");
        assertEq(rewardGroups.length, 2, "Should have 2 reward groups");

        // Verify specific tokens and rates
        assertEq(rewardTokens[0], CRV, "First reward token should be CRV");
        assertEq(rewardTokens[1], CVX, "Second reward token should be CVX");
        assertEq(rewardRates[0], 1e18, "CRV reward rate should be 1e18");
        assertEq(rewardRates[1], 0.3e18, "CVX reward rate should be 0.3e18");
        assertEq(rewardGroups[0], 0, "CRV should be in group 0");
        assertEq(rewardGroups[1], 1, "CVX should be in group 1");
    }

    // ============================================================================================
    // USD VALUE TESTS
    // ============================================================================================

    function test_getRewardValuePerSecond() public view {
        // Get reward value per second
        uint256 rewardValue = aprOracle.getRewardValuePerSecond();

        // Calculate expected value:
        // CRV: 1e18 * $0.50 = 0.5e18
        // CVX: 0.3e18 * $3.00 = 0.9e18
        // Total: 1.4e18 ($1.40 per second)
        uint256 expectedValue = 1.4e18;

        // Verify reward value
        assertEq(rewardValue, expectedValue, "Reward value should be $1.40 per second");
    }

    function test_getRewardValuePerSecondWithUpdatedPrices() public {
        // Update token prices
        mockOracle.setTokenPrice(CRV, 1e18); // $1.00 for CRV
        mockOracle.setTokenPrice(CVX, 5e18); // $5.00 for CVX

        // Get reward value per second with updated prices
        uint256 rewardValue = aprOracle.getRewardValuePerSecond();

        // Calculate expected value:
        // CRV: 1e18 * $1.00 = 1e18
        // CVX: 0.3e18 * $5.00 = 1.5e18
        // Total: 2.5e18 ($2.50 per second)
        uint256 expectedValue = 2.5e18;

        // Verify reward value with updated prices
        assertEq(rewardValue, expectedValue, "Reward value should be $2.50 per second with updated prices");
    }

    // ============================================================================================
    // INTEGRATION TESTS
    // ============================================================================================

    function test_aprOracleIntegration() public {
        // Set specific token balances for a more realistic test
        vm.mockCall(
            STAKED_CVXCRV,
            abi.encodeWithSelector(bytes4(keccak256("totalSupply()"))),
            abi.encode(10e24) // 10 million tokens total supply
        );

        // Allow small deviation - check that we're close to our expected mock value
        uint256 calculatedApr = aprOracle.aprAfterDebtChange(address(STRATEGY), 0);
        assertTrue(calculatedApr >= 17e16 && calculatedApr <= 18e16, "APR should match our mocked value around 17.5%");
    }
}
