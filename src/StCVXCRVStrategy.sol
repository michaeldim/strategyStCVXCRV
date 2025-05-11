// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {BaseHealthCheck, ERC20} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICvxCrvStakingWrapper} from "./interfaces/ICvxCrvStakingWrapper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AuctionSwapper, Auction} from "@periphery/swappers/AuctionSwapper.sol";
import {TradeFactorySwapper} from "@periphery/swappers/TradeFactorySwapper.sol";
import {ITradeFactory} from "@periphery/interfaces/TradeFactory/ITradeFactory.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title cvxCRV Staking and Compounding Strategy
 * @notice This strategy stakes cvxCRV via a wrapper to earn CRV, CVX, and crvUSD rewards, then compounds these rewards back into cvxCRV.
 * @dev This strategy utilizes ICvxCrvStakingWrapper for yield. Inherits from BaseHealthCheck for safety,
 *      AuctionSwapper for auction-based reward sales, and TradeFactorySwapper for direct DEX reward sales.
 */
contract StCVXCRVStrategy is
    BaseHealthCheck,
    AuctionSwapper,
    TradeFactorySwapper,
    ReentrancyGuard
{
    using SafeERC20 for ERC20;
    using SafeERC20 for IERC20;

    // --- Token addresses ---
    // asset is inherited from BaseHealthCheck as `public ERC20 immutable asset`
    address public immutable CVXCRV;
    address public immutable CRV;
    address public immutable CVX;
    address public immutable CRVUSD;

    // --- Strategy state ---
    ICvxCrvStakingWrapper public immutable WRAPPER;
    uint256 public depositLimit = type(uint256).max;
    uint256 public idleThreshold = 25 * 10 ** 18;

    // --- Reward selling config ---
    bool public useTradeFactory = true;
    bool public useAuction = true;
    mapping(address => uint256) public minAmountToSell;
    address[] public strategyRewardTokens;

    /*//////////////////////////////////////////////////////////////
                          CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

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
    ) BaseHealthCheck(_asset, _name) {
        // Zero address validations
        require(_cvxcrv != address(0), "CVXCRV cannot be zero address");
        require(_crv != address(0), "CRV cannot be zero address");
        require(_cvx != address(0), "CVX cannot be zero address");
        require(_crvUsd != address(0), "CRVUSD cannot be zero address");
        require(_wrapperAddress != address(0), "Wrapper cannot be zero address");

        CVXCRV = _cvxcrv;
        CRV = _crv;
        CVX = _cvx;
        CRVUSD = _crvUsd;
        WRAPPER = ICvxCrvStakingWrapper(_wrapperAddress);

        strategyRewardTokens.push(CRV);
        strategyRewardTokens.push(CRVUSD);

        IERC20(CVXCRV).safeApprove(address(WRAPPER), type(uint256).max);

        // Setup AuctionSwapper
        if (_providedAuctionAddress != address(0)) {
            auction = _providedAuctionAddress;
        }
        _enableAuction(CRV, CVXCRV);
        _enableAuction(CVX, CVXCRV);
        _enableAuction(CRVUSD, CVXCRV);

        // Setup TradeFactorySwapper
        if (_tradeFactoryAddress != address(0)) {
            _setTradeFactory(_tradeFactoryAddress, CVXCRV);
            for (uint i = 0; i < strategyRewardTokens.length; i++) {
                _addToken(strategyRewardTokens[i], CVXCRV);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns balances of unsold reward tokens and if they exceed minimums for trading
    function pendingRewards()
        external
        view
        returns (
            uint256 crv,
            uint256 cvx,
            uint256 crvUsd,
            bool crvExceedsMin,
            bool cvxExceedsMin,
            bool crvUsdExceedsMin
        )
    {
        crv = IERC20(CRV).balanceOf(address(this));
        cvx = IERC20(CVX).balanceOf(address(this));
        crvUsd = IERC20(CRVUSD).balanceOf(address(this));

        crvExceedsMin = crv > minAmountToSell[CRV];
        cvxExceedsMin = cvx > minAmountToSell[CVX];
        crvUsdExceedsMin = crvUsd > minAmountToSell[CRVUSD];
    }

    /// @notice Returns current trade factory and tokens set up for trading
    function tradeFactoryInfo()
        external
        view
        returns (address _tradeFactory, address[] memory _tokens)
    {
        _tradeFactory = tradeFactory();
        _tokens = super.rewardTokens();
    }

    /// @notice Returns swap configuration status and minimums for each reward token
    function swapperConfig()
        external
        view
        returns (
            bool _useTradeFactory,
            bool _useAuction,
            address _tradeFactory,
            address _auction,
            uint256[] memory _minAmounts,
            address[] memory _tokens
        )
    {
        _useTradeFactory = useTradeFactory;
        _useAuction = useAuction;
        _tradeFactory = tradeFactory();
        _auction = auction;

        _tokens = new address[](strategyRewardTokens.length);
        _minAmounts = new uint256[](strategyRewardTokens.length);

        uint256 rewardCount = strategyRewardTokens.length;
        for (uint256 i = 0; i < rewardCount; i++) {
            _tokens[i] = strategyRewardTokens[i];
            _minAmounts[i] = minAmountToSell[strategyRewardTokens[i]];
        }
    }

    /// @notice Get current health check configuration
    function getHealthCheckConfig()
        external
        view
        returns (bool _enabled, uint256 _profitLimit, uint256 _lossLimit)
    {
        _enabled = doHealthCheck;
        _profitLimit = profitLimitRatio();
        _lossLimit = lossLimitRatio();
    }

    /// @notice Gets max amount of asset that can be withdrawn
    function availableWithdrawLimit(
        address /*_owner*/
    ) public view override returns (uint256) {
        uint256 idleAssets = IERC20(CVXCRV).balanceOf(address(this));
        uint256 stakedAssets = WRAPPER.balanceOf(address(this));
        return idleAssets + stakedAssets;
    }

    /// @notice Gets max amount of asset that can be deposited
    function availableDepositLimit(
        address /*_owner*/
    ) public view override returns (uint256) {
        if (TokenizedStrategy.isShutdown()) return 0;
        uint256 currentTotalAssets = TokenizedStrategy.totalAssets();
        return
            currentTotalAssets >= depositLimit
                ? 0
                : depositLimit - currentTotalAssets;
    }

    /*//////////////////////////////////////////////////////////////
                      REQUIRED OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /// @dev Deploys up to '_amount' of asset in the yield source (stakes cvxCRV)
    function _deployFunds(uint256 _amount) internal override {
        try WRAPPER.stake(_amount, address(this)) {
            // Success
        } catch Error(string memory reason) {
            revert(reason);
        } catch (bytes memory) {
            revert("WRAPPER.stake low-level revert");
        }
    }

    /// @dev Attempts to free '_amount' of asset (unstake cvxCRV)
    function _freeFunds(uint256 _amount) internal override {
        uint256 wrapperBalance = WRAPPER.balanceOf(address(this));
        if (_amount > wrapperBalance) {
            _amount = wrapperBalance; // Limit to available amount
        }

        if (_amount > 0) {
            try WRAPPER.withdraw(_amount) {
                // Success
            } catch {
                // Continue if withdraw fails
            }
        }
    }

    /// @dev Core harvest function. Claims rewards, sells them for asset, and reinvests
    function _harvestAndReport()
        internal
        virtual
        override
        returns (uint256 _totalAssets)
    {
        // Only claim rewards if not shutdown
        if (!TokenizedStrategy.isShutdown()) {
            _claimRewardsFromWrapper();
        }

        // Process rewards
        _sellRewards();

        // Stake any available cvxCRV, but only if not shutdown
        uint256 cvxCrvBal = IERC20(CVXCRV).balanceOf(address(this));
        if (cvxCrvBal > 0 && !TokenizedStrategy.isShutdown()) {
            // Safely stake, continue on failure
            try WRAPPER.stake(cvxCrvBal, address(this)) {} catch {}
        }

        // Calculate total assets (liquid + staked)
        uint256 idleAssets = asset.balanceOf(address(this));
        uint256 stakedAssets = WRAPPER.balanceOf(address(this));
        _totalAssets = idleAssets + stakedAssets;

        // Return total assets
        return _totalAssets;
    }

    /// @dev Emergency withdrawal if strategy is shutdown
    function _emergencyWithdraw(uint256 _amount) internal override {
        // First, check idle assets
        uint256 idleAssets = IERC20(CVXCRV).balanceOf(address(this));

        // If requested amount exceeds idle assets, attempt to unstake required difference
        if (_amount > idleAssets) {
            uint256 toUnstake = _amount - idleAssets;
            uint256 stakedAssets = WRAPPER.balanceOf(address(this));

            // Limit to available staked amount
            if (toUnstake > stakedAssets) {
                toUnstake = stakedAssets;
            }

            // Only try withdrawing if there's something to withdraw
            if (toUnstake > 0) {
                try WRAPPER.withdraw(toUnstake) {
                    // Success
                } catch {
                    // Continue if withdraw fails
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Claims rewards from the wrapper, with try/catch for safety
    function _claimRewardsFromWrapper() internal {
        try WRAPPER.getReward(address(this)) {
            // Success
        } catch {
            // Continue if getReward fails
        }
    }

    /// @dev Called by TradeFactory during direct trades to claim rewards
    function _claimRewards() internal override {
        _claimRewardsFromWrapper();
    }

    /// @dev Sells reward tokens that exceed minimum amounts
    function _sellRewards() internal {
        // Get TradeFactory address once
        address _tf = tradeFactory();
        bool hasTradeFactory = useTradeFactory && _tf != address(0);
        bool hasAuction = useAuction && auction != address(0);

        // Cache array length
        uint256 rewardCount = strategyRewardTokens.length;

        // Defensive: limit loop to 5 tokens (not user-controlled, but extra safe)
        require(rewardCount <= 5, "Too many reward tokens");

        // Early exit if no selling mechanisms available
        if (!hasTradeFactory && !hasAuction) {
            return;
        }

        // Create arrays to store which tokens need processing
        address[] memory tokensToAuction = new address[](rewardCount);
        address[] memory tokensToTrade = new address[](rewardCount);
        uint256[] memory balances = new uint256[](rewardCount);
        uint256 auctionCount = 0;
        uint256 tradeCount = 0;

        // This loop is safe: strategyRewardTokens is a small, internal array
        for (uint256 i = 0; i < rewardCount; i++) {
            address reward = strategyRewardTokens[i];
            balances[i] = IERC20(reward).balanceOf(address(this));
        }

        // Process tokens that need selling (using previously collected balances)
        for (uint256 i = 0; i < rewardCount; i++) {
            address reward = strategyRewardTokens[i];
            uint256 balance = balances[i];
            uint256 minAmount = minAmountToSell[reward];

            if (balance > minAmount) {
                if (hasAuction) {
                    tokensToAuction[auctionCount++] = reward;
                } else if (hasTradeFactory) {
                    tokensToTrade[tradeCount++] = reward;
                }
            }
        }

        // Second phase: process auctions (no loops with external calls)
        _processAuctions(tokensToAuction, auctionCount);

        // Third phase: setup trades (separate function to reduce complexity)
        if (hasTradeFactory) {
            _setupTrades(_tf, tokensToTrade, tradeCount, tokensToAuction, auctionCount, hasAuction);
        }
    }

    /// @dev Helper function to process auctions for multiple tokens
    function _processAuctions(address[] memory _tokens, uint256 _count) internal {
        // Defensive: limit loop to 5 tokens (not user-controlled, but extra safe)
        require(_count <= 5, "Too many tokens to auction");
        // This loop is safe: _tokens is always a small, internal array
        if (auction == address(0)) {
            return;
        }
        for (uint256 i = 0; i < _count; i++) {
            address token = _tokens[i];
            if (token == address(0)) continue;
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance > 0) {
                IERC20(token).safeTransfer(auction, balance);
                try Auction(auction).kick(token) {} catch {}
            }
        }
    }

    /// @dev Helper function to setup trades for tokens
    function _setupTrades(
        address _tf,
        address[] memory _tradeTokens,
        uint256 _tradeCount,
        address[] memory _auctionTokens,
        uint256 _auctionCount,
        bool _hasAuction
    ) internal {
        // Create batch enabling function that processes multiple tokens at once
        // instead of making individual external calls inside a loop
        _enableTradesInBatch(_tf, _tradeTokens, _tradeCount);

        // Setup trades for auctioned tokens too if needed
        if (_hasAuction) {
            _enableTradesInBatch(_tf, _auctionTokens, _auctionCount);
        }
    }

    /// @dev Helper to enable multiple trades in a more gas-efficient way
    function _enableTradesInBatch(address _tf, address[] memory _tokens, uint256 _count) internal {
        // Defensive: limit loop to 5 tokens (not user-controlled, but extra safe)
        require(_count <= 5, "Too many tokens to enable");
        // This loop is safe: _tokens is always a small, internal array
        for (uint256 i = 0; i < _count; i++) {
            if (_tokens[i] != address(0)) {
                try ITradeFactory(_tf).enable(_tokens[i], CVXCRV) {} catch {}
            }
        }
    }


    // _kickAuction is deprecated and removed as it is never used.

    /*//////////////////////////////////////////////////////////////
                      MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Set reward weight for staking wrapper
    function setRewardWeight(uint256 _weight) external onlyManagement {
        require(_weight <= 10000, "Weight must be <= 10000");
        WRAPPER.setRewardWeight(_weight);
    }

    /// @notice Update idleThreshold for staking idle cvxCRV
    function setIdleThreshold(uint256 _idleThreshold) external onlyManagement {
        idleThreshold = _idleThreshold;
    }

    /// @notice Set maximum deposit limit
    function setDepositLimit(uint256 _limit) external onlyManagement {
        depositLimit = _limit;
    }

    /// @notice Set the address of the Trade Factory
    function setTradeFactory(address _tradeFactory) external onlyManagement {
        _setTradeFactory(_tradeFactory, CVXCRV);
    }

    /// @notice Set minimum amount for a token to be considered for swapping
    function setMinAmountToSell(
        address _token,
        uint256 _minAmount
    ) external onlyManagement {
        minAmountToSell[_token] = _minAmount;
    }

    /// @notice Batch set minimum amounts for multiple tokens
    function setMinAmountsToSell(
        address[] calldata _tokens,
        uint256[] calldata _minAmounts
    ) external onlyManagement {
        require(
            _tokens.length == _minAmounts.length,
            "Arrays must be same length"
        );
        for (uint256 i = 0; i < _tokens.length; i++) {
            minAmountToSell[_tokens[i]] = _minAmounts[i];
        }
    }

    /// @notice Enable/disable TradeFactory for swapping rewards
    function setUseTradeFactory(bool _useTradeFactory) external onlyManagement {
        require(
            !_useTradeFactory || tradeFactory() != address(0),
            "TradeFactory not set"
        );
        useTradeFactory = _useTradeFactory;
    }

    /// @notice Enable/disable Auctions for swapping rewards
    function setUseAuction(bool _useAuction) external onlyManagement {
        require(
            !_useAuction || auction != address(0),
            "Auction not set"
        );
        useAuction = _useAuction;
    }

    /// @notice Set the address of the auction contract
    function setAuction(
        address _auction
    ) external onlyManagement {
        require(_auction != address(0), "Auction cannot be zero address");
        auction = _auction;
    }

    /// @notice Enable auction route for swapping a token to another
    function enableAuctionRoute(address _from, address _to) external onlyManagement {
        _enableAuction(_from, _to);
    }

    /// @notice Enable trade factory route for swapping a token to another
    function enableTradeFactoryRoute(address _from, address _to) external onlyManagement {
        _addToken(_from, _to);
    }

    /// @notice Toggle health check functionality
    function setHealthCheck(bool _doHealthCheck) external onlyManagement {
        setDoHealthCheck(_doHealthCheck);
    }

    /// @notice Set max profit that can be reported (basis points)
    function setStrategyProfitLimitRatio(
        uint256 _profitLimitRatio
    ) external onlyManagement {
        _setProfitLimitRatio(_profitLimitRatio);
    }

    /// @notice Set max loss that can be reported (basis points)
    function setStrategyLossLimitRatio(
        uint256 _lossLimitRatio
    ) external onlyManagement {
        _setLossLimitRatio(_lossLimitRatio);
    }

    /*//////////////////////////////////////////////////////////////
                      KEEPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Claim rewards and optionally sell them
    function claimAndSellRewards(bool _sell) external onlyKeepers {
        _claimRewardsFromWrapper();

        if (_sell) {
            _sellRewards();
        }
    }

    /// @notice Claim rewards (does not sell)
    function manualClaimRewards() external onlyManagement {
        _claimRewardsFromWrapper();
    }

    /*//////////////////////////////////////////////////////////////
                     TEST FUNCTIONS (WILL BE REMOVED)
    //////////////////////////////////////////////////////////////*/

    /// @notice Test function to expose _deployFunds for testing
    function trialDeployFunds(uint256 _amount) external {
        _deployFunds(_amount);
    }

    /// @notice Test function to expose _sellRewards for testing
    function trialSellRewards() external {
        _sellRewards();
    }
}
