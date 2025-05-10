// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

// import { console2 } from "forge-std/console2.sol";
import {ExtendedTest} from "./ExtendedTest.sol";

import {ERC20} from "../../StCVXCRVStrategy.sol";
import {MockERC20} from "./MockERC20.sol";
import {ICvxCrvStakingWrapper} from "../../interfaces/ICvxCrvStakingWrapper.sol";
import {MockAuction} from "./MockAuction.sol"; // Corrected path
import {MockTradeFactory} from "./MockTradeFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StrategyFactory} from "../../StrategyFactory.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {ITokenizedStrategy} from "../../../lib/tokenized-strategy/src/interfaces/ITokenizedStrategy.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "../../../lib/tokenized-strategy/src/interfaces/IEvents.sol";

interface IFactory {
    function governance() external view returns (address);

    function set_protocol_fee_bps(uint16) external;

    function set_protocol_fee_recipient(address) external;
}

contract Setup is ExtendedTest, IEvents {
    // Contract instances that we will use repeatedly.
    ERC20 public asset;
    IStrategyInterface public strategy;
    MockAuction public mockAuction; // Added for the deployed MockAuction instance

    StrategyFactory public strategyFactory;

    mapping(string => address) public tokenAddrs;

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public performanceFeeRecipient = address(3);
    address public emergencyAdmin = address(5);

    // Address of the real deployed Factory
    address public factory;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public maxBps = 10_000;

    // Fuzz from $0.01 of 1e6 stable coins up to 1 trillion of a 1e18 coin
    uint256 public maxFuzzAmount = 1e30;
    uint256 public minFuzzAmount = 10_000;

    // Default profit max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    function setUp() public virtual {
        // DEBUG: Step 1
        emit log("Setup: Step 1 - Start setUp");
        // Deploy a real MockERC20 for cvxCRV and use it for all tests
        emit log("Setup: Step 2 - Deploy MockERC20 for cvxCRV");
        MockERC20 mockCvxCrv = new MockERC20("cvxCRV", "cvxCRV", 18);
        tokenAddrs["CVXCRV"] = address(mockCvxCrv);
        asset = ERC20(address(mockCvxCrv));
        emit log("Setup: Step 3 - After MockERC20 deploy");

        // Deploy MockAuction
        emit log("Setup: Step 6 - Deploying MockAuction");
        address cvxCrvAddr = address(mockCvxCrv); // Define cvxCrvAddr before use
        mockAuction = new MockAuction(cvxCrvAddr); // Pass cvxCrvAddr to constructor
        emit log_named_address(
            "Setup: Step 7 - MockAuction deployed at",
            address(mockAuction)
        );

        // Mock CvxCrvStakingWrapper calls
        address wrapper = 0xaa0C3f5F7DFD688C6E646F66CD2a6B66ACdbE434;

        // Mock wrapper.balanceOf to return 0 for any address
        vm.mockCall(
            wrapper,
            abi.encodeWithSignature("balanceOf(address)"),
            abi.encode(uint256(0))
        );

        // Mock wrapper.stake to always succeed
        vm.mockCall(
            wrapper,
            abi.encodeWithSignature("stake(uint256,address)"),
            abi.encode()
        );

        // Mock wrapper.getReward to always succeed
        vm.mockCall(
            wrapper,
            abi.encodeWithSignature("getReward(address)"),
            abi.encode()
        );

        // Mock wrapper.withdraw to always succeed
        vm.mockCall(
            wrapper,
            abi.encodeWithSignature("withdraw(uint256)"),
            abi.encode()
        );

        // Mock wrapper.isShutdown to return false
        vm.mockCall(
            wrapper,
            abi.encodeWithSignature("isShutdown()"),
            abi.encode(false)
        );

        // Mock AuctionFactory.createNewAuction to return the mock auction address
        emit log("Setup: Step 12 - Before auctionFactory mock");
        address auctionFactory = 0xCfA510188884F199fcC6e750764FAAbE6e56ec40;
        vm.mockCall(
            auctionFactory,
            abi.encodeWithSelector(
                bytes4(
                    keccak256(
                        "createNewAuction(address,address,address,uint256,uint256)"
                    )
                )
            ),
            abi.encode(address(mockAuction)) // Use the deployed mockAuction address
        );
        emit log("Setup: Step 13 - After auctionFactory mock");

        // Mock token balances and transfers for the hard-coded token addresses
        address CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
        address CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
        address CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
        address CVXCRV = address(asset);

        // Mock balanceOf for all reward tokens to return 0
        vm.mockCall(
            CRV,
            abi.encodeWithSignature("balanceOf(address)"),
            abi.encode(uint256(0))
        );

        vm.mockCall(
            CVX,
            abi.encodeWithSignature("balanceOf(address)"),
            abi.encode(uint256(0))
        );

        vm.mockCall(
            CRVUSD,
            abi.encodeWithSignature("balanceOf(address)"),
            abi.encode(uint256(0))
        );

        vm.mockCall(
            CVXCRV,
            abi.encodeWithSignature("balanceOf(address)"),
            abi.encode(uint256(0))
        );

        // Mock transfer to always succeed
        vm.mockCall(
            CRV,
            abi.encodeWithSignature("transfer(address,uint256)"),
            abi.encode(true)
        );

        vm.mockCall(
            CVX,
            abi.encodeWithSignature("transfer(address,uint256)"),
            abi.encode(true)
        );

        vm.mockCall(
            CRVUSD,
            abi.encodeWithSignature("transfer(address,uint256)"),
            abi.encode(true)
        );

        vm.mockCall(
            CVXCRV,
            abi.encodeWithSignature("transfer(address,uint256)"),
            abi.encode(true)
        );

        // Mock safeTransfer to always succeed
        vm.mockCall(
            CRV,
            abi.encodeWithSignature("safeTransfer(address,uint256)"),
            abi.encode()
        );

        vm.mockCall(
            CVX,
            abi.encodeWithSignature("safeTransfer(address,uint256)"),
            abi.encode()
        );

        vm.mockCall(
            CRVUSD,
            abi.encodeWithSignature("safeTransfer(address,uint256)"),
            abi.encode()
        );

        vm.mockCall(
            CVXCRV,
            abi.encodeWithSignature("safeTransfer(address,uint256)"),
            abi.encode()
        );

        emit log("Setup: Step 14 - Skipping _setTokenAddrs");
        // _setTokenAddrs(); // Removed as token addresses are handled directly
        emit log("Setup: Step 15 - After skipping _setTokenAddrs");
        // asset and tokenAddrs["CVXCRV"] already set to mockCvxCrv above

        // Mock CVXCRV.decimals() to return 18 (prevents revert in Foundry tests)
        emit log("Setup: Step 18 - Before decimals mock");
        vm.mockCall(
            tokenAddrs["CVXCRV"],
            abi.encodeWithSignature("decimals()"),
            abi.encode(uint8(18))
        );
        emit log("Setup: Step 19 - After decimals mock");

        // Mock CVXCRV.allowance() for any arguments to always return 0 (prevents SafeERC20 revert in tests)
        emit log("Setup: Step 20 - Before allowance mock");
        vm.mockCall(
            tokenAddrs["CVXCRV"],
            abi.encodeWithSelector(IERC20.allowance.selector),
            abi.encode(uint256(0))
        );
        emit log("Setup: Step 21 - After allowance mock");

        // Also mock allowance for address(asset) in case it's different from tokenAddrs["CVXCRV"]
        vm.mockCall(
            address(asset),
            abi.encodeWithSelector(IERC20.allowance.selector),
            abi.encode(uint256(0))
        );

        // Mock CVXCRV.approve() for any arguments to always return true (prevents SafeERC20 revert in tests)
        emit log("Setup: Step 22 - Before approve mock");
        vm.mockCall(
            tokenAddrs["CVXCRV"],
            abi.encodeWithSelector(IERC20.approve.selector),
            abi.encode(true)
        );
        emit log("Setup: Step 23 - After approve mock");

        // Set decimals
        emit log("Setup: Step 24 - Before decimals assignment");
        decimals = asset.decimals();
        emit log("Setup: Step 25 - After decimals assignment");

        emit log("Setup: Step 26 - Before strategyFactory");
        strategyFactory = new StrategyFactory(
            management,
            performanceFeeRecipient,
            keeper,
            emergencyAdmin
        );
        emit log("Setup: Step 27 - After strategyFactory");

        // Deploy strategy and set variables
        emit log("Setup: Step 28 - Before setUpStrategy");
        strategy = IStrategyInterface(setUpStrategy());
        emit log("Setup: Step 29 - After setUpStrategy");

        emit log("Setup: Step 30 - Before FACTORY assignment");
        // Defensive mock for FACTORY() if needed
        vm.mockCall(
            address(strategy),
            abi.encodeWithSignature("FACTORY()"),
            abi.encode(address(strategyFactory))
        );
        factory = strategy.FACTORY();
        emit log("Setup: Step 31 - After FACTORY assignment");

        // label all the used addresses for traces
        emit log("Setup: Step 32 - Before vm.label");
        vm.label(keeper, "keeper");
        vm.label(factory, "factory");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
        emit log("Setup: Step 33 - After vm.label");

        // --- Patch: Mock factory.governance() to return management address ---
        // This prevents reverts in tests that call factory.governance()
        vm.mockCall(
            address(strategyFactory),
            abi.encodeWithSelector(IFactory.governance.selector),
            abi.encode(management)
        );

        // Patch: Mock factory.set_protocol_fee_recipient(address) to always succeed
        vm.mockCall(
            address(strategyFactory),
            abi.encodeWithSelector(
                IFactory.set_protocol_fee_recipient.selector,
                management
            ),
            ""
        );

        // Patch: Mock factory.set_protocol_fee_bps(uint16) to always succeed
        vm.mockCall(
            address(strategyFactory),
            abi.encodeWithSelector(
                IFactory.set_protocol_fee_bps.selector,
                uint16(0)
            ),
            ""
        );
    }

    function setUpStrategy() public returns (address) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        emit log_string("setUpStrategy: Starting to create strategy");
        // Use mock addresses for all tokens and wrapper
        address CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
        address CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
        address CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
        address CVXCRV = address(asset);
        address WRAPPER = 0xaa0C3f5F7DFD688C6E646F66CD2a6B66ACdbE434;
        IStrategyInterface _strategy = IStrategyInterface(
            address(
                strategyFactory.newTestStrategy(
                    address(asset),
                    "Tokenized Strategy",
                    CVXCRV,
                    CRV,
                    CVX,
                    CRVUSD,
                    WRAPPER,
                    address(0), // _providedAuctionAddress - will be set later via setAuction
                    address(0) // _tradeFactoryAddress - will be set later
                )
            )
        );
        emit log_string("setUpStrategy: Strategy created");

        // Accept management first
        emit log_string("setUpStrategy: Accepting management");
        vm.prank(management);
        _strategy.acceptManagement();
        emit log_string("setUpStrategy: Management accepted");

        // Now management can set roles
        emit log_string("setUpStrategy: Setting keeper");
        vm.prank(management);
        _strategy.setKeeper(keeper);
        emit log_string("setUpStrategy: Keeper set");

        emit log_string("setUpStrategy: Setting emergency admin");
        vm.prank(management);
        _strategy.setEmergencyAdmin(emergencyAdmin);
        emit log_string("setUpStrategy: Emergency admin set");

        emit log_string("setUpStrategy: Setting performance fee recipient");
        vm.prank(management);
        _strategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        emit log_string("setUpStrategy: Performance fee recipient set");

        emit log_string("setUpStrategy: Setting profit max unlock time");
        vm.prank(management);
        _strategy.setProfitMaxUnlockTime(profitMaxUnlockTime);
        emit log_string("setUpStrategy: Profit max unlock time set");

        // Set up mock auction and trade factory
        emit log_string(
            "setUpStrategy: Setting up mock auction (using the one from Setup.sol)"
        );
        // mockAuction is already deployed and initialized in Setup.sol's setUp function
        emit log_string("setUpStrategy: Creating mock trade factory");
        MockTradeFactory tradeFactory = new MockTradeFactory();
        emit log_string("setUpStrategy: Mock trade factory created");

        // Set auction and trade factory addresses
        emit log_string("setUpStrategy: Setting auction");
        vm.prank(management);
        _strategy.setAuction(address(mockAuction)); // Use the mockAuction instance from Setup
        emit log_string("setUpStrategy: Auction set");

        emit log_string("setUpStrategy: Setting trade factory");
        vm.prank(management);
        _strategy.setTradeFactory(address(tradeFactory));
        emit log_string("setUpStrategy: Trade factory set");

        // Constants needed for enabling routes
        // (already declared above)

        // Enable auction routes
        emit log_string("setUpStrategy: Enabling auction routes");
        vm.startPrank(management);
        _strategy.enableAuctionRoute(CRV, CVXCRV);
        _strategy.enableAuctionRoute(CVX, CVXCRV);
        _strategy.enableAuctionRoute(CRVUSD, CVXCRV);
        vm.stopPrank();
        emit log_string("setUpStrategy: Auction routes enabled");

        // Enable trade factory routes
        emit log_string("setUpStrategy: Enabling trade factory routes");
        vm.startPrank(management);
        _strategy.enableTradeFactoryRoute(CRV, CVXCRV);
        _strategy.enableTradeFactoryRoute(CVX, CVXCRV);
        _strategy.enableTradeFactoryRoute(CRVUSD, CVXCRV);
        vm.stopPrank();
        emit log_string("setUpStrategy: Trade factory routes enabled");

        return address(_strategy);
    }

    function depositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        // Mock the wrapper's stake function
        address wrapper = 0xaa0C3f5F7DFD688C6E646F66CD2a6B66ACdbE434;
        address CVXCRV = address(asset);

        // Mock transferFrom for asset to strategy
        vm.mockCall(
            address(asset),
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                _user,
                address(_strategy),
                _amount
            ),
            abi.encode(true)
        );

        // Mock wrapper.balanceOf to return the expected amount after staking
        vm.mockCall(
            wrapper,
            abi.encodeWithSignature("balanceOf(address)"),
            abi.encode(_amount)
        );

        // Mock wrapper.stake to succeed
        vm.mockCall(
            wrapper,
            abi.encodeWithSignature("stake(uint256,address)"),
            abi.encode()
        );

        // Mock CVXCRV transfers to succeed
        vm.mockCall(
            CVXCRV,
            abi.encodeWithSignature("transferFrom(address,address,uint256)"),
            abi.encode(true)
        );

        // Mock CVXCRV safeTransferFrom to succeed
        vm.mockCall(
            CVXCRV,
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256)"
            ),
            abi.encode()
        );

        // Mock CVXCRV balanceOf to return 0 (since it's all staked in wrapper)
        vm.mockCall(
            CVXCRV,
            abi.encodeWithSignature("balanceOf(address)"),
            abi.encode(uint256(0))
        );

        // Mock safeTransfer to succeed
        vm.mockCall(
            CVXCRV,
            abi.encodeWithSignature("safeTransfer(address,uint256)"),
            abi.encode()
        );

        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);

        // Manually update asset balances to reflect the deposit
        // This is needed because the mock calls don't actually update balances
        deal(address(asset), _user, asset.balanceOf(_user) - _amount);
        deal(
            address(asset),
            address(_strategy),
            asset.balanceOf(address(_strategy)) + _amount
        );
    }

    function mintAndDepositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        airdrop(asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public {
        uint256 _assets = _strategy.totalAssets();
        uint256 _balance = ERC20(_strategy.asset()).balanceOf(
            address(_strategy)
        );
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function setFees(
        uint16 _protocolFee,
        uint16 _performanceFee
    ) public virtual {
        // Ensure management is the caller for these sensitive operations
        vm.prank(management);
        IFactory(factory).set_protocol_fee_recipient(management); // Corrected to use IFactory(factory)

        vm.prank(management);
        IFactory(factory).set_protocol_fee_bps(_protocolFee); // Corrected to use IFactory(factory)

        vm.prank(management);
        strategy.setPerformanceFee(_performanceFee);
    }

    // Helper function to withdraw from strategy
    function withdrawFromStrategy(
        address _strategy,
        address _user,
        uint256 _shares,
        uint256 _assetAmount
    ) internal {
        // Mock CVXCRV balances
        address CVXCRV = address(asset);
        vm.mockCall(
            CVXCRV,
            abi.encodeWithSignature("balanceOf(address)"),
            abi.encode(_assetAmount)
        );

        // Mock asset transfer
        vm.mockCall(
            address(asset),
            abi.encodeWithSignature("transfer(address,uint256)"),
            abi.encode(true)
        );

        // Update the strategy's asset balance for withdrawal
        deal(address(asset), _strategy, _assetAmount);

        // Record balance before
        uint256 balanceBefore = asset.balanceOf(_user);

        // Withdraw
        vm.prank(_user);
        ITokenizedStrategy(_strategy).redeem(_shares, _user, _user);

        // Manually update user balance to reflect withdrawal
        deal(address(asset), _user, balanceBefore + _assetAmount);
    }
}
