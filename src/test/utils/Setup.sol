// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

// import { console2 } from "forge-std/console2.sol";
import {ExtendedTest} from "./ExtendedTest.sol";

import {ERC20} from "../../StCVXCRVStrategy.sol";
import {MockERC20} from "./MockERC20.sol";
import {ICvxCrvStakingWrapper} from "../../interfaces/ICvxCrvStakingWrapper.sol";
import {MockTradeFactory} from "./MockTradeFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StrategyFactory} from "../../StrategyFactory.sol";
import {TestStrategyFactory} from "../TestStrategyFactory.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {ITokenizedStrategy} from "../../../lib/tokenized-strategy/src/interfaces/ITokenizedStrategy.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "../../../lib/tokenized-strategy/src/interfaces/IEvents.sol";

interface IFactory {
    function governance() external view returns (address);
    function set_protocol_fee_bps(uint16) external;
    function set_protocol_fee_recipient(address) external;
}

abstract contract Setup is ExtendedTest, IEvents {
    // Contract instances that we will use repeatedly.
    ERC20 public asset;
    IStrategyInterface public strategy;

    StrategyFactory public strategyFactory;
    TestStrategyFactory public testStrategyFactory;

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

    // Flag to control whether to create a strategy in setUp
    bool public shouldCreateStrategy = true;

    function setUp() public virtual {
        // DEBUG: Step 1
        emit log("Setup: Step 1 - Start setUp");
        // Deploy a real MockERC20 for cvxCRV and use it for all tests
        emit log("Setup: Step 2 - Deploy MockERC20 for cvxCRV");
        MockERC20 mockCvxCrv = new MockERC20("cvxCRV", "cvxCRV", 18);
        tokenAddrs["CVXCRV"] = address(mockCvxCrv);
        asset = ERC20(address(mockCvxCrv));
        emit log("Setup: Step 3 - After MockERC20 deploy");

        // Mock CvxCrvStakingWrapper calls
        address wrapper = 0xaa0C3f5F7DFD688C6E646F66CD2a6B66ACdbE434;

        // Mock wrapper.balanceOf to return 0 for any address
        vm.mockCall(wrapper, abi.encodeWithSignature("balanceOf(address)"), abi.encode(uint256(0)));

        // Mock wrapper.stake to always succeed
        vm.mockCall(wrapper, abi.encodeWithSignature("stake(uint256,address)"), abi.encode());

        // Mock wrapper.getReward to always succeed
        vm.mockCall(wrapper, abi.encodeWithSignature("getReward(address)"), abi.encode());

        // Mock wrapper.withdraw to always succeed
        vm.mockCall(wrapper, abi.encodeWithSignature("withdraw(uint256)"), abi.encode());

        // Mock wrapper.isShutdown to return false
        vm.mockCall(wrapper, abi.encodeWithSignature("isShutdown()"), abi.encode(false));

        // Mock token balances and transfers for the hard-coded token addresses
        address CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
        address CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
        address CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
        address CVXCRV = address(asset);

        // Mock balanceOf for all reward tokens to return 0
        vm.mockCall(CRV, abi.encodeWithSignature("balanceOf(address)"), abi.encode(uint256(0)));
        vm.mockCall(CVX, abi.encodeWithSignature("balanceOf(address)"), abi.encode(uint256(0)));
        vm.mockCall(CRVUSD, abi.encodeWithSignature("balanceOf(address)"), abi.encode(uint256(0)));
        vm.mockCall(CVXCRV, abi.encodeWithSignature("balanceOf(address)"), abi.encode(uint256(0)));

        // Mock transfer to always succeed
        vm.mockCall(CRV, abi.encodeWithSignature("transfer(address,uint256)"), abi.encode(true));
        vm.mockCall(CVX, abi.encodeWithSignature("transfer(address,uint256)"), abi.encode(true));
        vm.mockCall(CRVUSD, abi.encodeWithSignature("transfer(address,uint256)"), abi.encode(true));
        vm.mockCall(CVXCRV, abi.encodeWithSignature("transfer(address,uint256)"), abi.encode(true));

        // Mock safeTransfer to always succeed
        vm.mockCall(CRV, abi.encodeWithSignature("safeTransfer(address,uint256)"), abi.encode());
        vm.mockCall(CVX, abi.encodeWithSignature("safeTransfer(address,uint256)"), abi.encode());
        vm.mockCall(CRVUSD, abi.encodeWithSignature("safeTransfer(address,uint256)"), abi.encode());
        vm.mockCall(CVXCRV, abi.encodeWithSignature("safeTransfer(address,uint256)"), abi.encode());

        // Mock CVXCRV.decimals() to return 18 (prevents revert in Foundry tests)
        vm.mockCall(tokenAddrs["CVXCRV"], abi.encodeWithSignature("decimals()"), abi.encode(uint8(18)));

        // Mock CVXCRV.allowance() and approve()
        vm.mockCall(tokenAddrs["CVXCRV"], abi.encodeWithSelector(IERC20.allowance.selector), abi.encode(uint256(0)));
        vm.mockCall(address(asset), abi.encodeWithSelector(IERC20.allowance.selector), abi.encode(uint256(0)));
        vm.mockCall(tokenAddrs["CVXCRV"], abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));

        // Set decimals
        emit log("Setup: Step 24 - Before decimals assignment");
        decimals = asset.decimals();
        emit log("Setup: Step 25 - After decimals assignment");

        emit log("Setup: Step 26 - Before strategyFactory");
        strategyFactory = new StrategyFactory(management, performanceFeeRecipient, keeper, emergencyAdmin);
        testStrategyFactory = new TestStrategyFactory(management, performanceFeeRecipient, keeper, emergencyAdmin);
        emit log("Setup: Step 27 - After strategyFactory");

        // Set factory address regardless of creating a strategy
        factory = address(testStrategyFactory);

        // Label common addresses regardless of creating a strategy
        vm.label(keeper, "keeper");
        vm.label(factory, "factory");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");

        // Mock common factory functions regardless of creating a strategy
        vm.mockCall(
            address(testStrategyFactory),
            abi.encodeWithSelector(IFactory.governance.selector),
            abi.encode(management)
        );
        vm.mockCall(
            address(testStrategyFactory),
            abi.encodeWithSelector(IFactory.set_protocol_fee_recipient.selector, management),
            ""
        );
        vm.mockCall(
            address(testStrategyFactory),
            abi.encodeWithSelector(IFactory.set_protocol_fee_bps.selector, uint16(0)),
            ""
        );

        // Deploy strategy and set variables - only if the flag is set
        if (shouldCreateStrategy) {
            emit log("Setup: Step 28 - Before setUpStrategy");
            strategy = IStrategyInterface(setUpStrategy());
            emit log("Setup: Step 29 - After setUpStrategy");

            emit log("Setup: Step 30 - Before FACTORY assignment");
            // Defensive mock for FACTORY() if needed
            vm.mockCall(address(strategy), abi.encodeWithSignature("FACTORY()"), abi.encode(address(testStrategyFactory)));
            emit log("Setup: Step 31 - After FACTORY assignment");

            // Label strategy address
            vm.label(address(strategy), "strategy");
        }
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
                testStrategyFactory.newTestStrategy(
                    address(asset),
                    "Tokenized Strategy",
                    CVXCRV,
                    CRV,
                    CVX,
                    CRVUSD,
                    WRAPPER,
                    address(0), // _providedAuctionAddress - unused but kept for compatibility
                    address(0) // _tradeFactoryAddress - will be set later
                )
            )
        );
        emit log_string("setUpStrategy: Strategy created");

        // Debug: Log current management and pendingManagement before accepting
        address mgmt = _strategy.management();
        address pendingMgmt = _strategy.pendingManagement();
        emit log_named_address("setUpStrategy: Current management", mgmt);
        emit log_named_address("setUpStrategy: Current pendingManagement", pendingMgmt);

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

        // Set up mock trade factory
        emit log_string("setUpStrategy: Creating mock trade factory");
        MockTradeFactory tradeFactory = new MockTradeFactory();
        emit log_string("setUpStrategy: Mock trade factory created");

        // Set trade factory address
        emit log_string("setUpStrategy: Setting trade factory");
        vm.prank(management);
        _strategy.setTradeFactory(address(tradeFactory));
        emit log_string("setUpStrategy: Trade factory set");

        // Constants needed for enabling routes
        // (already declared above)

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

    function depositIntoStrategy(IStrategyInterface _strategy, address _user, uint256 _amount) public {
        // Mock the wrapper's stake function
        address wrapper = 0xaa0C3f5F7DFD688C6E646F66CD2a6B66ACdbE434;
        address CVXCRV = address(asset);

        // Mock transferFrom for asset to strategy
        vm.mockCall(
            address(asset),
            abi.encodeWithSignature("transferFrom(address,address,uint256)", _user, address(_strategy), _amount),
            abi.encode(true)
        );

        // Mock wrapper.balanceOf to return the expected amount after staking
        vm.mockCall(wrapper, abi.encodeWithSignature("balanceOf(address)"), abi.encode(_amount));

        // Mock wrapper.stake to succeed
        vm.mockCall(wrapper, abi.encodeWithSignature("stake(uint256,address)"), abi.encode());

        // Mock CVXCRV transfers to succeed
        vm.mockCall(CVXCRV, abi.encodeWithSignature("transferFrom(address,address,uint256)"), abi.encode(true));

        // Mock CVXCRV safeTransferFrom to succeed
        vm.mockCall(CVXCRV, abi.encodeWithSignature("safeTransferFrom(address,address,uint256)"), abi.encode());

        // Mock CVXCRV balanceOf to return 0 (since it's all staked in wrapper)
        vm.mockCall(CVXCRV, abi.encodeWithSignature("balanceOf(address)"), abi.encode(uint256(0)));

        // Mock safeTransfer to succeed
        vm.mockCall(CVXCRV, abi.encodeWithSignature("safeTransfer(address,uint256)"), abi.encode());

        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);

        // Manually update asset balances to reflect the deposit
        // This is needed because the mock calls don't actually update balances
        // Use vm.mockCall instead of deal for coverage compatibility
        vm.mockCall(
            address(asset),
            abi.encodeWithSignature("balanceOf(address)", _user),
            abi.encode(asset.balanceOf(_user) - _amount)
        );
        vm.mockCall(
            address(asset),
            abi.encodeWithSignature("balanceOf(address)", address(_strategy)),
            abi.encode(asset.balanceOf(address(_strategy)) + _amount)
        );
    }

    function mintAndDepositIntoStrategy(IStrategyInterface _strategy, address _user, uint256 _amount) public {
        airdrop(asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public view {
        uint256 _assets = _strategy.totalAssets();
        uint256 _balance = ERC20(_strategy.asset()).balanceOf(address(_strategy));
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public virtual {
        uint256 balanceBefore = _asset.balanceOf(_to);
        uint256 newBalance = balanceBefore + _amount;

        // Use mockCall instead of deal for compatibility with coverage tests
        vm.mockCall(address(_asset), abi.encodeWithSignature("balanceOf(address)", _to), abi.encode(newBalance));

        // Mock transferFrom to succeed
        vm.mockCall(
            address(_asset),
            abi.encodeWithSignature("transferFrom(address,address,uint256)"),
            abi.encode(true)
        );
    }

    function setFees(uint16 _protocolFee, uint16 _performanceFee) public virtual {
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
    ) internal virtual {
        // Mock CVXCRV balances
        address CVXCRV = address(asset);
        vm.mockCall(CVXCRV, abi.encodeWithSignature("balanceOf(address)"), abi.encode(_assetAmount));

        // Mock asset transfer
        vm.mockCall(address(asset), abi.encodeWithSignature("transfer(address,uint256)"), abi.encode(true));

        // Update the strategy's asset balance for withdrawal using mockCall instead of deal
        vm.mockCall(address(asset), abi.encodeWithSignature("balanceOf(address)", _strategy), abi.encode(_assetAmount));

        // Record balance before
        uint256 balanceBefore = asset.balanceOf(_user);

        // Withdraw
        vm.prank(_user);
        ITokenizedStrategy(_strategy).redeem(_shares, _user, _user);

        // Manually update user balance to reflect withdrawal using mockCall instead of deal
        vm.mockCall(
            address(asset),
            abi.encodeWithSignature("balanceOf(address)", _user),
            abi.encode(balanceBefore + _assetAmount)
        );
    }
}
