// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {BaseStrategy} from "@tokenized-strategy/BaseStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ICvxCrvStakingWrapper} from "./interfaces/ICvxCrvStakingWrapper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TradeFactorySwapper} from "@periphery/swappers/TradeFactorySwapper.sol";
import {ITradeFactory} from "@periphery/interfaces/TradeFactory/ITradeFactory.sol";
import {IAuction} from "./interfaces/IAuction.sol";

/**
 * @title Staked cvxCRV Compounder
 * @notice This strategy stakes cvxCRV via a wrapper to earn CRV, CVX, and crvUSD rewards, then compounds these rewards back into cvxCRV.
 */
contract StCVXCRVStrategy is BaseStrategy, TradeFactorySwapper {
    using SafeERC20 for IERC20;

    enum SwapType {
        NULL,
        TRADE_FACTORY,
        AUCTION
    }

    // --- Strategy state ---
    ICvxCrvStakingWrapper public constant WRAPPER = ICvxCrvStakingWrapper(0xaa0C3f5F7DFD688C6E646F66CD2a6B66ACdbE434);

    // --- Auction configuration ---
    address public auction;
    mapping(address => SwapType) public swapType;

    // --- Reward selling config ---
    mapping(address => uint256) public minAmountToSellMapping;
    address[] public strategyRewardTokens;

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    constructor(
        address _asset,
        string memory _name
    ) BaseStrategy(_asset, _name) {
        IERC20(address(asset)).safeApprove(address(WRAPPER), type(uint256).max);
    }

    // -----------------------------------------------------------------------
    // View Functions
    // -----------------------------------------------------------------------

    /**
     * @notice Returns all reward tokens tracked by the strategy
     */
    function getAllRewardTokens() external view returns (address[] memory) {
        return strategyRewardTokens;
    }

    // -----------------------------------------------------------------------
    // Core Strategy Implementation
    // -----------------------------------------------------------------------

    /**
     * @dev Deploys up to '_amount' of asset in the yield source (stakes cvxCRV)
     * @param _amount Amount of asset to stake
     */
    function _deployFunds(uint256 _amount) internal override {
        try WRAPPER.stake(_amount, address(this)) {} catch Error(string memory reason) {
            revert(reason);
        } catch (bytes memory) {
            revert("WRAPPER.stake low-level revert");
        }
    }

    /**
     * @dev Attempts to free '_amount' of asset (unstake cvxCRV)
     * @param _amount Amount of asset to unstake
     */
    function _freeFunds(uint256 _amount) internal override {
        uint256 wrapperBalance = WRAPPER.balanceOf(address(this));

        _amount = Math.min(_amount, wrapperBalance);

        if (_amount > 0) {
            try WRAPPER.withdraw(_amount) {} catch {}
        }
    }

    /**
     * @dev Core harvest function. Claims rewards, sells them for asset, and reinvests
     * @return _totalAssets Total assets under management after harvest
     */
    function _harvestAndReport() internal virtual override returns (uint256 _totalAssets) {
        if (!TokenizedStrategy.isShutdown()) {
            _claimRewards();
        }

        _sellRewards();

        uint256 assetBal = IERC20(address(asset)).balanceOf(address(this));
        if (assetBal > 0 && !TokenizedStrategy.isShutdown()) {
            try WRAPPER.stake(assetBal, address(this)) {} catch {}
        }

        uint256 idleAssets = asset.balanceOf(address(this));
        uint256 stakedAssets = WRAPPER.balanceOf(address(this));
        _totalAssets = idleAssets + stakedAssets;

        return _totalAssets;
    }

    /**
     * @dev Emergency withdrawal if strategy is shutdown
     * @param _amount Amount of asset to withdraw
     */
    function _emergencyWithdraw(uint256 _amount) internal override {
        uint256 idleAssets = IERC20(address(asset)).balanceOf(address(this));

        if (_amount > idleAssets) {
            uint256 toUnstake = _amount - idleAssets;

            _freeFunds(toUnstake);
        }
    }

    /**
     * @dev Claims rewards from the wrapper, with try/catch for safety
     */
    function _claimRewards() internal override {
        try WRAPPER.getReward(address(this)) {} catch {}
    }

    // -----------------------------------------------------------------------
    // Reward Management
    // -----------------------------------------------------------------------

    /**
     * @notice Add a new reward token to the strategy
     * @param _token Address of the token to add
     * @param _swapType The swap method to use (must be TRADE_FACTORY or AUCTION)
     */
    function addRewardToken(
        address _token,
        uint8 _swapType
    ) external onlyManagement {
        require(
            _token != address(asset),
            "Cannot use asset as reward token"
        );

        require(swapType[_token] == SwapType.NULL, "!exists");

        require(_swapType > 0, "!null");

        require(_swapType <= uint8(SwapType.AUCTION), "Invalid swap type");
        SwapType method = SwapType(_swapType);

        strategyRewardTokens.push(_token);
        swapType[_token] = method;

        if (method == SwapType.TRADE_FACTORY) {
            address tf = tradeFactory();
            if (tf != address(0)) {
                _addToken(_token, address(asset));
            }
        }
    }

    /**
     * @notice Remove a reward token from the strategy
     * @param _token Address of the token to remove
     */
    function removeRewardToken(address _token) external onlyManagement {
        address[] memory _allRewardTokens = strategyRewardTokens;
        uint256 _length = _allRewardTokens.length;
        SwapType _swapType = swapType[_token];
        bool found = false;

        for (uint256 i = 0; i < _length; ++i) {
            if (_allRewardTokens[i] == _token) {
                strategyRewardTokens[i] = _allRewardTokens[_length - 1];
                strategyRewardTokens.pop();
                found = true;
                break;
            }
        }

        require(found, "Token not found");

        delete swapType[_token];
        delete minAmountToSellMapping[_token];

        if (_swapType == SwapType.TRADE_FACTORY) {
            address tf = tradeFactory();
            if (tf != address(0)) {
                _removeToken(_token, address(asset));
            }
        }
    }

    /**
     * @notice Claim rewards (optionally sell them) from the strategy
     * @param sell Whether to sell the claimed rewards
     */
    function manualClaimRewards(bool sell) external onlyManagement {
        _claimRewards();
        if (sell) {
            _sellRewards();
        }
    }

    /**
     * @notice Set minimum amount for a token to be considered for swapping
     * @param _token Token address to configure
     * @param _minAmount Minimum amount needed to trigger a swap
     */
    function setMinAmountToSellMapping(address _token, uint256 _minAmount) external onlyManagement {
        minAmountToSellMapping[_token] = _minAmount;
    }

    // -----------------------------------------------------------------------
    // Reward Selling
    // -----------------------------------------------------------------------

    /**
     * @dev Sells reward tokens that exceed minimum amounts
     */
    function _sellRewards() internal {
        uint256 rewardCount = strategyRewardTokens.length;

        address _tf = tradeFactory();

        for (uint256 i = 0; i < rewardCount; i++) {
            address reward = strategyRewardTokens[i];
            uint256 balance = IERC20(reward).balanceOf(address(this));
            uint256 minAmount = minAmountToSellMapping[reward];

            if (balance <= minAmount) continue;

            SwapType swapMethod = swapType[reward];

            if (swapMethod == SwapType.AUCTION && auction != address(0)) {
                _kickAuction(reward);
            }
            else if (swapMethod == SwapType.TRADE_FACTORY && _tf != address(0)) {
                // No immediate action needed - TradeFactory's off-chain keepers handle swaps
            }
        }
    }

    /**
     * @notice Set the swap type for a specific token
     * @param _token Token address to configure
     * @param _swapType Swap method to use for this token
     */
    function setSwapType(address _token, SwapType _swapType) external onlyManagement {
        swapType[_token] = _swapType;
    }

    // -----------------------------------------------------------------------
    // TradeFactory Configuration
    // -----------------------------------------------------------------------

    /**
     * @notice Set the address of the Trade Factory
     * @param _tradeFactory Address of the new Trade Factory
     */
    function setTradeFactory(address _tradeFactory) external onlyManagement {
        _setTradeFactory(_tradeFactory, address(asset));
    }

    /**
     * @notice Enable trade factory route for swapping a token to another
     * @param _from Token to swap from
     * @param _to Token to swap to
     */
    function enableTradeFactoryRoute(address _from, address _to) external onlyManagement {
        _addToken(_from, _to);
    }

    // -----------------------------------------------------------------------
    // Auction Configuration
    // -----------------------------------------------------------------------

    /**
     * @notice Set the auction address
     * @param _auction Address of the new auction contract
     */
    function setAuction(address _auction) external onlyManagement {
        if (_auction != address(0)) {
            require(IAuction(_auction).want() == address(asset), "Auction want must be asset");
            require(IAuction(_auction).receiver() == address(this), "Auction receiver must be strategy");
        }

        auction = _auction;
    }

    /**
     * @dev Initiates an auction for a reward token
     * @param _token The token to be sold via auction
     * @return The auction address used
     */
    function _kickAuction(address _token) internal returns (address) {
        require(_token != address(asset), "Cannot auction strategy asset");
        require(auction != address(0), "No auction configured");

        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(_token).safeTransfer(auction, balance);

            try IAuction(auction).kick(_token) {} catch {}
        }

        return auction;
    }

    /**
     * @notice Manually start an auction for a specific token
     * @param _token Token to auction
     * @return The auction address used
     */
    function kickAuction(address _token) external onlyKeepers returns (address) {
        require(swapType[_token] == SwapType.AUCTION, "Token not configured for auction");
        return _kickAuction(_token);
    }

    // -----------------------------------------------------------------------
    // Staking Wrapper Configuration
    // -----------------------------------------------------------------------

    /**
     * @notice Set reward weight for staking wrapper
     * @param _weight New weight to set (capped at 10000)
     */
    function setRewardWeight(uint256 _weight) external onlyManagement {
        require(_weight <= 10000, "Weight must be <= 10000");
        WRAPPER.setRewardWeight(_weight);
    }
}