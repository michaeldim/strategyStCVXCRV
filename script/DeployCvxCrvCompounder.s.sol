// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {CvxCrvCompounderFactory} from "../src/CvxCrvCompounderFactory.sol";

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
 * DEPLOYMENT PHASE 1: Deployer (3 transactions)
 * ============================================================================
 * 1. Deploy CvxCrvCompounderFactory
 * 2. Deploy CvxCrvCompounder via factory
 * 3. Deploy auction via AuctionFactory for crvUSD -> cvxCRV
 *
 * ============================================================================
 * DEPLOYMENT PHASE 2: Management (8 transactions) - run by MANAGEMENT
 * ============================================================================
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
    address constant KEEPER = 0x52605BbF54845f520a3E94792d019f62407db2f8; // Yearn V3 Keeper (permissionless)
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

        vm.stopBroadcast();

        // === PHASE 1 COMPLETE ===
        console.log("\n========================================");
        console.log("PHASE 1 COMPLETE - Contracts Deployed!");
        console.log("========================================");
        console.log("Factory:", address(factory));
        console.log("Strategy:", strategyAddress);
        console.log("Auction:", auction);
        console.log("\n========================================");
        console.log("PHASE 2 - Management must run these txs:");
        console.log("========================================");
        console.log("From address:", MANAGEMENT);
        console.log("");
        console.log("4. strategy.acceptManagement()");
        console.log("5. strategy.setPerformanceFee(500)");
        console.log("6. strategy.setAuction(", auction, ")");
        console.log("7. strategy.setMinAmountToSell(CRVUSD, 50e18)");
        console.log("8. strategy.setMinAmountToSell(CRV, 100e18)");
        console.log("9. strategy.setMinAmountToSell(CVX, 50e18)");
        console.log("10. strategy.setRewardWeight(10000)");
        console.log("11. vault.add_strategy(", strategyAddress, ")");
        console.log("");

        // === CONFIGURATION SUMMARY ===
        console.log("Configuration (to be set in Phase 2):");
        console.log("  Asset (cvxCRV):", CVXCRV);
        console.log("  Management:", MANAGEMENT);
        console.log("  Keeper:", KEEPER);
        console.log("  Performance Fee: 5% (500 bps)");
        console.log("  Reward Weight: 10000 (100% crvUSD)");
        console.log("  Min crvUSD to Sell: 50 crvUSD");
        console.log("  Min CRV to Sell: 100 CRV (fallback)");
        console.log("  Min CVX to Sell: 50 CVX (fallback)");
        console.log("\nVault:", VAULT);
        console.log("\n========================================");
        console.log("Phase 1: 3 txs (deployer)");
        console.log("Phase 2: 8 txs (management)");
        console.log("========================================");
    }
}
