// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StCVXCRVStrategy} from "../StCVXCRVStrategy.sol"; // Updated import
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICvxCrvStakingWrapper} from "../interfaces/ICvxCrvStakingWrapper.sol"; // Corrected path
import {ITokenizedStrategy} from "../../lib/tokenized-strategy/src/interfaces/ITokenizedStrategy.sol";
import {MockAuction} from "./utils/MockAuction.sol";
import {MockERC20} from "./utils/MockERC20.sol";

/**
 * @notice A modified version of the Strategy that exposes the _harvestAndReport
 * function without relying on TokenizedStrategy for isShutdown checks
 */
contract ForkedFixedStrategy is StCVXCRVStrategy {
    bool public mockIsShutdown = false;
    uint256 public constant INITIAL_DEPOSIT = 100e18;

    // Reference to auction interface for harvesting
    MockAuction public AUCTION;

    constructor(
        address _asset,
        string memory _name,
        address _cvxcrv,
        address _crv,
        address _cvx,
        address _crvUsd,
        address _wrapperAddress,
        address _providedAuctionAddress,
        address _tradeFactoryAddress
    )
        StCVXCRVStrategy(
            _asset,
            _name,
            _cvxcrv,
            _crv,
            _cvx,
            _crvUsd,
            _wrapperAddress,
            _providedAuctionAddress,
            _tradeFactoryAddress
        )
    {
        // Store auction reference
        AUCTION = MockAuction(_providedAuctionAddress);
    }

    // Add CVX to strategyRewardTokens for the test
    function fixRewardTokens() external {
        // Make sure CVX is in the reward tokens list, Strategy constructor only adds CRV and CRVUSD
        strategyRewardTokens.push(CVX);
    }

    function setMockShutdown(bool _isShutdown) external {
        mockIsShutdown = _isShutdown;
    }

    /// @notice Expose harvest for tests
    function testHarvest() external returns (uint256) {
        return _fixedHarvestAndReport();
    }

    /// @notice Implementation for fixed harvest for testing
    function _fixedHarvestAndReport() internal returns (uint256) {
        if (mockIsShutdown) {
            return 0;
        }

        uint256 totalAssets = IERC20(asset).balanceOf(address(this));

        // Claim rewards from the staking wrapper
        WRAPPER.getReward(address(this));

        // Process each reward token (CRV, CVX, etc.)
        for (uint256 i = 0; i < strategyRewardTokens.length; i++) {
            address token = strategyRewardTokens[i];
            uint256 tokenBalance = IERC20(token).balanceOf(address(this));

            if (tokenBalance > 0) {
                // Swap the reward token for more asset (cvxCRV) through the auction
                IERC20(token).approve(address(AUCTION), tokenBalance);
                AUCTION.initiateTrade(
                    tokenBalance,
                    token,
                    address(asset),
                    address(this)
                );
            }
        }

        // Stake any newly acquired asset into the wrapper
        uint256 newAssets = IERC20(asset).balanceOf(address(this)) -
            totalAssets;

        if (newAssets > 0) {
            IERC20(asset).approve(address(WRAPPER), newAssets);
            WRAPPER.stake(newAssets, address(this));
        }

        return newAssets;
    }
}

contract ForkedTest is Test {
    ForkedFixedStrategy public strategy;

    // Mainnet addresses
    address constant CVXCRV = 0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7;
    address constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address constant WRAPPER = 0xaa0C3f5F7DFD688C6E646F66CD2a6B66ACdbE434; // Updated to Convex docs address

    address public management;
    address public keeper;

    function setUp() public {
        // Fork Ethereum mainnet with environment variable or default Alchemy URL
        string memory rpcUrl = vm.envOr(
            "ETH_RPC_URL",
            string("https://eth-mainnet.alchemyapi.io/v2/demo")
        );
        vm.createSelectFork(rpcUrl);
        console.log("=== Mainnet Forked Test ===");

        management = makeAddr("management");
        keeper = makeAddr("keeper");

        // Create mock auction
        MockAuction mockAuction = new MockAuction(CVXCRV); // Pass CVXCRV to constructor
        console.log("Mock auction deployed at:", address(mockAuction));

        // Enable tokens for auction
        mockAuction.enable(CRV);
        mockAuction.enable(CVX);
        mockAuction.enable(CRVUSD);

        // Create TestStrategy
        console.log("Creating TestStrategy with real token addresses...");
        vm.prank(management); // Prank as management before deploying TestStrategy
        strategy = new ForkedFixedStrategy(
            CVXCRV, // asset
            "Test Strategy", // name
            CVXCRV, // cvxcrv
            CRV, // crv
            CVX, // cvx
            CRVUSD, // crvUsd
            WRAPPER, // real wrapper address
            address(mockAuction), // mock auction
            address(0) // tradeFactory
        );

        console.log("Strategy deployed at:", address(strategy));

        // Set useAuction and useTradeFactory to false to simplify test
        vm.prank(management);
        strategy.setUseAuction(false);

        vm.prank(management);
        strategy.setUseTradeFactory(false);
    }

    function testForkedHarvest() public {
        console.log("Testing harvest on forked mainnet...");

        uint256 depositAmount = 1 * 10 ** 18; // 1 CVXCRV

        // Deal CVXCRV to the keeper
        deal(CVXCRV, keeper, depositAmount);

        // Keeper approves strategy to spend CVXCRV
        vm.startPrank(keeper);
        IERC20(CVXCRV).approve(address(strategy), depositAmount);

        // Keeper deposits CVXCRV into the strategy
        // strategy.deposit(depositAmount, keeper); // Old call
        ITokenizedStrategy(address(strategy)).deposit(depositAmount, keeper); // New call with explicit cast
        vm.stopPrank();

        // Now, try to execute the harvest
        vm.prank(keeper);
        try strategy.testHarvest() returns (uint256 profit) {
            // Corrected: expects a single uint256
            console.log("Harvest successful! Profit:");
            console.logUint(profit);
        } catch Error(string memory reason) {
            console.log("Error:", reason);
            revert(reason);
        } catch (bytes memory reason) {
            console.log("Unknown error:");
            console.logBytes(reason);
            revert("Unknown error");
        }
    }
}
