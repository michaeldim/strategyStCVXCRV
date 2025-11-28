// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {CvxCrvCompounder} from "../src/CvxCrvCompounder.sol";
import {CvxCrvCompounderFactory} from "../src/CvxCrvCompounderFactory.sol";
import {ITokenizedStrategy} from "@tokenized-strategy/interfaces/ITokenizedStrategy.sol";

interface IAuctionFactory {
    function createNewAuction(
        address _want,
        address _receiver,
        address _governance
    ) external returns (address);
}

interface IVault {
    function add_strategy(address strategy) external;
}

/**
 * @title Deploy Convex cvxCRV Compounder
 * @notice Deployment script for CvxCrvCompounder factory and strategy with auction setup
 *
 * ============================================================================
 * PRE-DEPLOYMENT: Prepare Old Strategy for Migration
 * ============================================================================
 * Old Strategy: 0x5efa37f0be827d55529832b5961dc3c160b5c725
 *
 * 1. Set minAmountToSellMapping to 0 for crvUSD (allows selling any amount)
 *    oldStrategy.setMinAmountToSellMapping(CRVUSD, 0)
 *
 * 2. Call manualClaimRewards to sell any remaining crvUSD
 *    oldStrategy.manualClaimRewards(true)
 *
 * ============================================================================
 * DEPLOYMENT: New Strategy (11 transactions)
 * ============================================================================
 * 1. Deploy CvxCrvCompounderFactory
 * 2. Deploy CvxCrvCompounder via factory
 * 3. Deploy auction via AuctionFactory for crvUSD -> cvxCRV
 * 4. Accept management on strategy
 * 5. Set performance fee to 5%
 * 6. Set auction address on strategy
 * 7. Set minAmountToSell for crvUSD (50 crvUSD)
 * 8. Set minAmountToSell for CRV (100 CRV) - fallback if reward weight changes
 * 9. Set minAmountToSell for CVX (50 CVX) - fallback if reward weight changes
 * 10. Set reward weight to 10000 (100% crvUSD)
 * 11. Add strategy to vault (with 0 debt initially)
 *
 * ============================================================================
 * POST-DEPLOYMENT: Migration Steps
 * ============================================================================
 * 1. Gradually reduce debt on old strategy (or all at once)
 *    vault.update_debt(oldStrategy, newDebtAmount)
 *
 * 2. Report on old strategy to free funds
 *    oldStrategy.report()
 *
 * 3. Increase debt on new strategy
 *    vault.update_debt(newStrategy, newDebtAmount)
 *
 * 4. Old strategy will continue unlocking any locked profits
 *    - Keep reporting until fully drained
 *    - Profits continue streaming via profitMaxUnlockTime
 *
 * 5. Once old strategy is empty and profits unlocked:
 *    vault.revoke_strategy(oldStrategy)
 *
 * ============================================================================
 */
contract DeployCvxCrvCompounder is Script {
    // === TOKEN ADDRESSES ===
    address constant CVXCRV = 0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7;
    address constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

    // === EXTERNAL CONTRACTS ===
    address constant AUCTION_FACTORY = 0xd8e03D6D24d43c46c0f7f61327E391316E4f3c15;
    address constant VAULT = 0x95f19B19aff698169a1A0BBC28a2e47B14CB9a86;

    // === CONFIGURATION ===
    address constant KEEPER = 0xa88e98bBD2Af6DDD642407cB5455f956f0C553F0; // Exodus wallet
    address constant MANAGEMENT = 0x7bdfE11c4981Dd4c33E1aa62457B8773253791b3; // ycvxcrv.eth
    address constant PERFORMANCE_FEE_RECIPIENT = 0x7bdfE11c4981Dd4c33E1aa62457B8773253791b3;
    address constant EMERGENCY_ADMIN = 0x7bdfE11c4981Dd4c33E1aa62457B8773253791b3;

    string constant STRATEGY_NAME = "Convex cvxCRV Compounder";
    uint16 constant PERFORMANCE_FEE = 500; // 5% in basis points
    uint256 constant MIN_CRVUSD_TO_SELL = 50e18; // 50 crvUSD
    uint256 constant MIN_CRV_TO_SELL = 100e18; // 100 CRV (fallback if reward weight changes)
    uint256 constant MIN_CVX_TO_SELL = 50e18; // 50 CVX (fallback if reward weight changes)
    uint256 constant REWARD_WEIGHT = 10000; // 10000 = 100% crvUSD rewards (0 = 100% CRV+CVX)

    function run() external {
        // Determine deployer
        address deployer;
        string memory privateKeyStr = vm.envOr("PRIVATE_KEY", string(""));
        bool usingLedger = bytes(privateKeyStr).length == 0;

        if (usingLedger) {
            deployer = msg.sender;
            console.log("\n========================================");
            console.log("Deploying Convex cvxCRV Compounder");
            console.log("Using LEDGER");
            console.log("Deployer:", deployer);
            console.log("========================================\n");
            vm.startBroadcast();
        } else {
            uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
            deployer = vm.addr(deployerPrivateKey);
            console.log("\n========================================");
            console.log("Deploying Convex cvxCRV Compounder");
            console.log("Using PRIVATE KEY");
            console.log("Deployer:", deployer);
            console.log("========================================\n");
            vm.startBroadcast(deployerPrivateKey);
        }

        // === TRANSACTION 1: Deploy Strategy Factory ===
        console.log("[TX 1] Deploying CvxCrvCompounderFactory...");
        CvxCrvCompounderFactory factory = new CvxCrvCompounderFactory(
            MANAGEMENT,
            PERFORMANCE_FEE_RECIPIENT,
            KEEPER,
            EMERGENCY_ADMIN
        );
        console.log("   -> Factory deployed at:", address(factory));

        // === TRANSACTION 2: Deploy Strategy via Factory ===
        console.log("\n[TX 2] Deploying strategy via factory...");
        address strategyAddress = factory.newStrategy(CVXCRV, STRATEGY_NAME);
        console.log("   -> Strategy deployed at:", strategyAddress);

        CvxCrvCompounder strategy = CvxCrvCompounder(strategyAddress);
        ITokenizedStrategy tokenizedStrategy = ITokenizedStrategy(strategyAddress);

        // === TRANSACTION 3: Deploy Auction via Factory ===
        console.log("\n[TX 3] Deploying Auction via AuctionFactory...");
        console.log("   -> Want (cvxCRV):", CVXCRV);
        console.log("   -> Receiver (strategy):", strategyAddress);
        console.log("   -> Governance:", MANAGEMENT);

        address auction = IAuctionFactory(AUCTION_FACTORY).createNewAuction(
            CVXCRV, // want - token received from auction
            strategyAddress, // receiver - strategy receives the cvxCRV
            MANAGEMENT // governance - management controls the auction
        );
        console.log("   -> Auction deployed at:", auction);

        // === TRANSACTION 4: Accept Management ===
        console.log("\n[TX 4] Accepting management...");
        tokenizedStrategy.acceptManagement();
        console.log("   -> Management accepted");

        // === TRANSACTION 5: Set Performance Fee to 5% ===
        console.log("\n[TX 5] Setting performance fee to 5%...");
        tokenizedStrategy.setPerformanceFee(PERFORMANCE_FEE);
        console.log("   -> Performance fee set to:", PERFORMANCE_FEE, "bps (5%)");

        // === TRANSACTION 6: Set Auction on Strategy ===
        console.log("\n[TX 6] Setting auction on strategy...");
        strategy.setAuction(auction);
        console.log("   -> Auction set to:", auction);

        // === TRANSACTION 7: Set minAmountToSell for crvUSD ===
        console.log("\n[TX 7] Setting minAmountToSell for crvUSD...");
        strategy.setMinAmountToSell(CRVUSD, MIN_CRVUSD_TO_SELL);
        console.log("   -> Min crvUSD to sell:", MIN_CRVUSD_TO_SELL / 1e18, "crvUSD");

        // === TRANSACTION 8: Set minAmountToSell for CRV (fallback) ===
        console.log("\n[TX 8] Setting minAmountToSell for CRV...");
        strategy.setMinAmountToSell(CRV, MIN_CRV_TO_SELL);
        console.log("   -> Min CRV to sell:", MIN_CRV_TO_SELL / 1e18, "CRV");

        // === TRANSACTION 9: Set minAmountToSell for CVX (fallback) ===
        console.log("\n[TX 9] Setting minAmountToSell for CVX...");
        strategy.setMinAmountToSell(CVX, MIN_CVX_TO_SELL);
        console.log("   -> Min CVX to sell:", MIN_CVX_TO_SELL / 1e18, "CVX");

        // === TRANSACTION 10: Set Reward Weight (100% crvUSD) ===
        console.log("\n[TX 10] Setting reward weight for 100% crvUSD...");
        strategy.setRewardWeight(REWARD_WEIGHT);
        console.log("   -> Reward weight set to: 10000 (100% crvUSD)");

        // === TRANSACTION 11: Add Strategy to Vault ===
        console.log("\n[TX 11] Adding strategy to vault...");
        console.log("   -> Vault:", VAULT);
        IVault(VAULT).add_strategy(strategyAddress);
        console.log("   -> Strategy added to vault");

        vm.stopBroadcast();

        // === DEPLOYMENT SUMMARY ===
        console.log("\n========================================");
        console.log("DEPLOYMENT COMPLETE!");
        console.log("========================================");
        console.log("Factory:", address(factory));
        console.log("Strategy:", strategyAddress);
        console.log("Auction:", auction);
        console.log("\nConfiguration:");
        console.log("  Asset (cvxCRV):", CVXCRV);
        console.log("  Management:", MANAGEMENT);
        console.log("  Keeper:", KEEPER);
        console.log("  Performance Fee: 5% (500 bps)");
        console.log("  Reward Weight: 10000 (100% crvUSD)");
        console.log("  Min crvUSD to Sell: 50 crvUSD");
        console.log("  Min CRV to Sell: 100 CRV (fallback)");
        console.log("  Min CVX to Sell: 50 CVX (fallback)");
        console.log("\nAuction Configuration:");
        console.log("  Selling: crvUSD");
        console.log("  Receiving: cvxCRV");
        console.log("  Factory:", AUCTION_FACTORY);
        console.log("\nVault:", VAULT);
        console.log("\n========================================");
        console.log("Total transactions: 11");
        console.log("========================================");
        console.log("\nNEXT STEPS (MIGRATION):");
        console.log("========================================");
        console.log("1. Verify contracts on Etherscan");
        console.log("");
        console.log("2. Migrate debt from old strategy:");
        console.log("   Old Strategy: 0x5efa37f0be827d55529832b5961dc3c160b5c725");
        console.log("   a) vault.update_debt(oldStrategy, 0)");
        console.log("   b) oldStrategy.report()");
        console.log("   c) vault.update_debt(newStrategy, amount)");
        console.log("");
        console.log("3. Wait for old strategy profits to unlock");
        console.log("   - Continue reporting on old strategy");
        console.log("   - Check fullProfitUnlockDate()");
        console.log("");
        console.log("4. Once fully migrated:");
        console.log("   vault.revoke_strategy(oldStrategy)");
        console.log("");
        console.log("5. (Optional) Configure auction parameters");
        console.log("6. (Optional) Set up CommonReportTrigger");
        console.log("========================================");
    }
}
