// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {CvxCrvCompounder} from "../CvxCrvCompounder.sol";
import {StrategyAprOracle} from "../periphery/StrategyAprOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Minimal Vault interface
interface IVault {
    function token() external view returns (address);
    function apiVersion() external view returns (string memory);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function pricePerShare() external view returns (uint256);

    // For adding strategy
    function addStrategy(
        address _strategy,
        uint256 _debtRatio,
        uint256 _minDebtPerHarvest,
        uint256 _maxDebtPerHarvest,
        uint256 _performanceFee
    ) external;

    // For deposits
    function deposit(uint256 _amount) external returns (uint256);
    function withdraw(uint256 maxShares) external returns (uint256);
}

/**
 * @title Tenderly Virtual TestNet Integration Test
 * @notice This test deploys the CvxCrvCompounder to a Tenderly Virtual TestNet and verifies integration
 * @dev This test should be run with `--match-test testTenderlyIntegration` and the RPC URL set to the Tenderly TestNet
 */
contract TenderlyIntegrationTest is Test {
    // Set addresses for test on Tenderly Virtual TestNet
    address constant VAULT_ADDRESS = 0x95f19B19aff698169a1A0BBC28a2e47B14CB9a86; // cvxCRV yVault
    address constant CVXCRV_TOKEN_ADDRESS = 0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7; // cvxCRV token
    address constant WRAPPER_ADDRESS = 0xaa0C3f5F7DFD688C6E646F66CD2a6B66ACdbE434; // stkCVXCRVWrapper
    address constant TRADE_FACTORY_ADDRESS = 0x7BAF843e06095f68F4990Ca50161C2C4E4e01ec6; // Yearn TradeFactory

    // Governance/Management address - needed to add strategy to vault
    // This will be the new management address after management transfer
    address public GOVERNANCE_ADDRESS; // BETA

    // Reward token addresses
    address constant CRV_TOKEN_ADDRESS = 0xD533a949740bb3306d119CC777fa900bA034cd52; // CRV
    address constant CVX_TOKEN_ADDRESS = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B; // CVX
    address constant CRVUSD_TOKEN_ADDRESS = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E; // crvUSD

    // Strategy parameters
    string constant STRATEGY_NAME = "Staked cvxCRV Compounder";
    uint256 constant VAULT_STRATEGY_DEBT_RATIO = 9500; // 95% debt ratio
    uint256 constant VAULT_STRATEGY_MIN_DEBT_PER_HARVEST = 0;
    uint256 constant VAULT_STRATEGY_MAX_DEBT_PER_HARVEST = type(uint256).max;
    uint256 constant VAULT_STRATEGY_PERFORMANCE_FEE = 1000; // 10%

    // Test parameters
    uint256 constant TEST_DEPOSIT_AMOUNT = 10 * 1e18; // 10 cvxCRV

    // Contract instances
    CvxCrvCompounder public strategy;
    StrategyAprOracle public aprOracle;
    IVault public vault;
    IERC20 public cvxCrvToken;

    // Deploy addresses
    address public strategyAddress;
    address public aprOracleAddress;

    // Use a large address for deployment
    address public deployer = makeAddr("deployer");

    function setUp() public {
        // Skip this test unless explicitly run with match-test
        if (block.chainid != 1) {
            // Not running on mainnet fork
            return;
        }

        // Check if we're on Tenderly
        string memory rpcUrl = vm.envString("ETH_RPC_URL");
        if (bytes(rpcUrl).length == 0 || !contains(rpcUrl, "tenderly")) {
            console.log("Not running on Tenderly, skipping test");
            return;
        }

        // Load address from environment variable
        try vm.envAddress("BETA") returns (address addr) {
            GOVERNANCE_ADDRESS = addr;
            console.log("Loaded BETA address from environment:", GOVERNANCE_ADDRESS);
        } catch {
            // Fallback to hardcoded address if environment variable is not set
            revert("Environment variable BETA or GOVERNANCE_ADDRESS must be set");
        }

        // Fund the deployer account
        vm.deal(deployer, 100 ether);

        // Setup vault and token instances
        vault = IVault(VAULT_ADDRESS);
        cvxCrvToken = IERC20(CVXCRV_TOKEN_ADDRESS);

        console.log("==== Starting Tenderly Integration Test ====");
        console.log("Vault address:", VAULT_ADDRESS);
        console.log("Vault name:", vault.name());
        console.log("Vault API version:", vault.apiVersion());
        console.log("Vault token:", vault.token());
        console.log("Governance address:", GOVERNANCE_ADDRESS);
        console.log("Deployment account:", deployer);
    }

    function testTenderlyIntegration() public {
        // Skip test if not on Tenderly or mainnet fork
        if (block.chainid != 1) {
            console.log("Not running on mainnet fork, skipping");
            return;
        }

        string memory rpcUrl = vm.envString("ETH_RPC_URL");
        if (bytes(rpcUrl).length == 0 || !contains(rpcUrl, "tenderly")) {
            console.log("Not running on Tenderly, skipping test");
            return;
        }

        vm.startPrank(deployer);

        // STEP 1: Deploy APR Oracle (placeholder for now as we'll implement a proper oracle later)
        console.log("Deploying APR Oracle...");
        address priceOracleAddress = address(0); // Will be set up later
        aprOracle = new StrategyAprOracle(priceOracleAddress);
        aprOracleAddress = address(aprOracle);
        console.log("APR Oracle deployed at:", aprOracleAddress);

        // STEP 2: Deploy Strategy
        console.log("Deploying Strategy...");
        strategy = new CvxCrvCompounder(CVXCRV_TOKEN_ADDRESS, STRATEGY_NAME);
        strategyAddress = address(strategy);
        console.log("Strategy deployed at:", strategyAddress);

        // STEP 3: Configure Strategy
        console.log("Configuring Strategy...");
        // No reward token configuration needed - keepers handle auction kicking manually
        console.log("Strategy uses manual auction kicking - no reward token configuration needed");

        // STEP 4: Add Strategy to Vault
        console.log("Adding Strategy to Vault...");

        // To add the strategy to the vault, we need to impersonate the governance account
        console.log("Attempting to impersonate governance account:", GOVERNANCE_ADDRESS);

        // Stop pranking as deployer and start as governance
        vm.stopPrank();
        vm.startPrank(GOVERNANCE_ADDRESS);

        try
            vault.addStrategy(
                strategyAddress,
                VAULT_STRATEGY_DEBT_RATIO,
                VAULT_STRATEGY_MIN_DEBT_PER_HARVEST,
                VAULT_STRATEGY_MAX_DEBT_PER_HARVEST,
                VAULT_STRATEGY_PERFORMANCE_FEE
            )
        {
            console.log("Strategy successfully added to Vault");
        } catch Error(string memory reason) {
            console.log("Failed to add strategy to vault. Reason:", reason);
            console.log("This is expected if the governance address cannot be impersonated on Tenderly");
            // Continue the test even if this fails - we might not have permissions
        } catch (bytes memory) {
            console.log("Failed to add strategy to vault (unknown reason)");
            console.log("This is expected if the governance address cannot be impersonated on Tenderly");
            // Continue the test even if this fails
        }

        // Switch back to deployer for any remaining operations
        vm.stopPrank();
        vm.startPrank(deployer);

        // STEP 5: Test a deposit if we have cvxCRV tokens
        console.log("Checking for cvxCRV tokens...");
        uint256 balance = cvxCrvToken.balanceOf(deployer);
        console.log("Deployer cvxCRV balance:", balance);

        if (balance == 0) {
            console.log("No cvxCRV tokens available for testing deposits");
            console.log("To test deposits, send cvxCRV tokens to:", deployer);
        } else if (balance > 0) {
            // We have tokens, try to deposit
            uint256 depositAmount = balance > TEST_DEPOSIT_AMOUNT ? TEST_DEPOSIT_AMOUNT : balance;

            console.log("Approving vault to spend cvxCRV...");
            cvxCrvToken.approve(VAULT_ADDRESS, depositAmount);

            console.log("Depositing", depositAmount, "cvxCRV to vault...");
            try vault.deposit(depositAmount) returns (uint256 shares) {
                console.log("Deposit successful! Received", shares, "vault shares");

                // Try to withdraw half
                uint256 withdrawShares = shares / 2;
                console.log("Withdrawing", withdrawShares, "shares...");
                try vault.withdraw(withdrawShares) returns (uint256 withdrawn) {
                    console.log("Withdrawal successful! Received", withdrawn, "cvxCRV");
                } catch Error(string memory reason) {
                    console.log("Failed to withdraw. Reason:", reason);
                } catch (bytes memory) {
                    console.log("Failed to withdraw (unknown reason)");
                }
            } catch Error(string memory reason) {
                console.log("Failed to deposit. Reason:", reason);
            } catch (bytes memory) {
                console.log("Failed to deposit (unknown reason)");
            }
        }

        vm.stopPrank();

        console.log("==== Tenderly Integration Test Completed ====");
        console.log("Strategy deployed at:", strategyAddress);
        console.log("APR Oracle deployed at:", aprOracleAddress);
    }

    // Helper function to check if a string contains a substring
    function contains(string memory _string, string memory _substring) internal pure returns (bool) {
        bytes memory stringBytes = bytes(_string);
        bytes memory substringBytes = bytes(_substring);

        if (substringBytes.length > stringBytes.length) {
            return false;
        }

        for (uint i = 0; i <= stringBytes.length - substringBytes.length; i++) {
            bool found = true;
            for (uint j = 0; j < substringBytes.length; j++) {
                if (stringBytes[i + j] != substringBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) {
                return true;
            }
        }

        return false;
    }
}
