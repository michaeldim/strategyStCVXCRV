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
 * @title cvxCRV Staking and Compounding Strategy
 * @notice This strategy stakes cvxCRV via a wrapper to earn CRV, CVX, and crvUSD rewards, then compounds these rewards back into cvxCRV.
 * @dev This strategy utilizes ICvxCrvStakingWrapper for yield. Inherits from BaseStrategy for safety
 *      and TradeFactorySwapper for direct DEX reward sales. Can also use auctions for selling rewards.
 */
contract StCVXCRVStrategy is BaseStrategy, TradeFactorySwapper {
    using SafeERC20 for IERC20;

    // --- Swap Configuration ---
    enum SwapType {
        NULL,       // Not configured for swapping
        TRADE_FACTORY, // Use TradeFactory for swaps (default)
        AUCTION     // Use Auction for swaps
    }

    // --- Strategy state ---
    ICvxCrvStakingWrapper public constant WRAPPER = ICvxCrvStakingWrapper(0xaa0C3f5F7DFD688C6E646F66CD2a6B66ACdbE434);

    // --- Auction configuration ---
    /// @notice Address of the specific Auction this strategy uses
    address public auction; // Address of the Auction contract
    mapping(address => SwapType) public swapType; // Token address => swap method

    // --- Reward selling config ---
    mapping(address => uint256) public minAmountToSellMapping;
    address[] public strategyRewardTokens;

    /*//////////////////////////////////////////////////////////////
                          CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _asset,
        string memory _name
    ) BaseStrategy(_asset, _name) {
        // Set max approval for the wrapper to save gas on future deposits
        IERC20(address(asset)).safeApprove(address(WRAPPER), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns all reward tokens tracked by the strategy
    function getAllRewardTokens() external view returns (address[] memory) {
        return strategyRewardTokens;
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

        // Limit the amount to the available balance using Math.min
        _amount = Math.min(_amount, wrapperBalance);

        if (_amount > 0) {
            try WRAPPER.withdraw(_amount) {
                // Success
            } catch {
                // Continue if withdraw fails
            }
        }
    }

    /// @dev Core harvest function. Claims rewards, sells them for asset, and reinvests
    function _harvestAndReport() internal virtual override returns (uint256 _totalAssets) {
        // Only claim rewards if not shutdown
        if (!TokenizedStrategy.isShutdown()) {
            _claimRewards();
        }

        // Process rewards
        _sellRewards();

        // Stake any available strategy asset, but only if not shutdown
        uint256 assetBal = IERC20(address(asset)).balanceOf(address(this));
        if (assetBal > 0 && !TokenizedStrategy.isShutdown()) {
            // Safely stake, continue on failure
            try WRAPPER.stake(assetBal, address(this)) {} catch {}
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
        uint256 idleAssets = IERC20(address(asset)).balanceOf(address(this));

        // If requested amount exceeds idle assets, attempt to unstake required difference
        if (_amount > idleAssets) {
            uint256 toUnstake = _amount - idleAssets;

            // Use _freeFunds to handle the unstaking logic
            _freeFunds(toUnstake);
        }
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Claims rewards from the wrapper, with try/catch for safety
    function _claimRewards() internal override {
        try WRAPPER.getReward(address(this)) {
            // Success
        } catch {
            // Continue if getReward fails
        }
    }



    /// @dev Sells reward tokens that exceed minimum amounts
    function _sellRewards() internal {
        // Cache array length
        uint256 rewardCount = strategyRewardTokens.length;

        // Get TradeFactory address for DEX-based trades
        address _tf = tradeFactory();

        // Process each reward token according to its configured swap type
        for (uint256 i = 0; i < rewardCount; i++) {
            address reward = strategyRewardTokens[i];
            uint256 balance = IERC20(reward).balanceOf(address(this));
            uint256 minAmount = minAmountToSellMapping[reward];

            // Skip tokens that don't meet the minimum amount
            if (balance <= minAmount) continue;

            // Determine which swap method to use
            SwapType swapMethod = swapType[reward];

            if (swapMethod == SwapType.AUCTION && auction != address(0)) {
                // Use auction strategy
                _kickAuction(reward);
            }
            else if (swapMethod == SwapType.TRADE_FACTORY && _tf != address(0)) {
                // Use TradeFactory - no need to call enable again, just let it run
                // TradeFactory will handle the swap based on our existing configuration
            }
            // If NULL or unsupported method or mechanism unavailable, do nothing
        }
    }

    /// @dev Initiates an auction for a reward token
    /// @param _token The token to be sold via auction
    /// @return The auction address used
    function _kickAuction(address _token) internal returns (address) {
        require(_token != address(asset), "Cannot auction strategy asset");
        require(auction != address(0), "No auction configured");

        // Transfer tokens to the auction contract
        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(_token).safeTransfer(auction, balance);

            // Start the auction
            try IAuction(auction).kick(_token) {
                // Auction started successfully
            } catch {
                // If auction fails, just continue
            }
        }

        return auction;
    }

    /*//////////////////////////////////////////////////////////////
                      EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                   MANAGEMENT (onlyManagement) FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// -----------------------------------------------------------------------
    /// Staking Wrapper Configuration
    /// -----------------------------------------------------------------------

    /// @notice Set reward weight for staking wrapper
    function setRewardWeight(uint256 _weight) external onlyManagement {
        require(_weight <= 10000, "Weight must be <= 10000");
        WRAPPER.setRewardWeight(_weight);
    }

    /// -----------------------------------------------------------------------
    /// Reward Token Management
    /// -----------------------------------------------------------------------

    /// @notice Add a new reward token to the strategy
    /// @param _token Address of the token to add
    /// @param _swapType The swap method to use (must be TRADE_FACTORY or AUCTION)
    function addRewardToken(
        address _token,
        uint8 _swapType
    ) external onlyManagement {
        require(
            _token != address(asset),
            "Cannot use asset as reward token"
        );

        // Make sure we haven't already set a swap type for this asset
        require(swapType[_token] == SwapType.NULL, "!exists");

        // Shouldn't ever add an asset but set to null
        require(_swapType > 0, "!null");

        // Convert uint8 to SwapType and validate
        require(_swapType <= uint8(SwapType.AUCTION), "Invalid swap type");
        SwapType method = SwapType(_swapType);

        // Add to our tracking array
        strategyRewardTokens.push(_token);
        swapType[_token] = method;

        // Enable on our trade factory
        if (method == SwapType.TRADE_FACTORY) {
            address tf = tradeFactory();
            if (tf != address(0)) {
                _addToken(_token, address(asset));
            }
        }
    }

    /// @notice Remove a reward token from the strategy
    /// @param _token Address of the token to remove
    function removeRewardToken(address _token) external onlyManagement {
        address[] memory _allRewardTokens = strategyRewardTokens;
        uint256 _length = _allRewardTokens.length;
        SwapType _swapType = swapType[_token];
        bool found = false;

        for (uint256 i = 0; i < _length; ++i) {
            if (_allRewardTokens[i] == _token) {
                // Replace with the last element and pop
                strategyRewardTokens[i] = _allRewardTokens[_length - 1];
                strategyRewardTokens.pop();
                found = true;
                break;
            }
        }

        require(found, "Token not found");

        // Clear token configuration
        delete swapType[_token];
        delete minAmountToSellMapping[_token];

        // Disable on our trade factory
        if (_swapType == SwapType.TRADE_FACTORY) {
            address tf = tradeFactory();
            if (tf != address(0)) {
                _removeToken(_token, address(asset));
            }
        }
    }

    /// @notice Claim rewards (optionally sell them) from the strategy
    function manualClaimRewards(bool sell) external onlyManagement {
        _claimRewards();
        if (sell) {
            _sellRewards();
        }
    }

    /// -----------------------------------------------------------------------
    /// TradeFactory Configuration
    /// -----------------------------------------------------------------------

    /// @notice Set the address of the Trade Factory
    function setTradeFactory(address _tradeFactory) external onlyManagement {
        _setTradeFactory(_tradeFactory, address(asset));
    }

    /// @notice Enable trade factory route for swapping a token to another
    function enableTradeFactoryRoute(address _from, address _to) external onlyManagement {
        _addToken(_from, _to);
    }

    /// @notice Configure all reward tokens to use TradeFactory
    function setAllTokensToTradeFactory() external onlyManagement {
        address tf = tradeFactory();
        require(tf != address(0), "No TradeFactory configured");

        uint256 rewardCount = strategyRewardTokens.length;
        for (uint256 i = 0; i < rewardCount; i++) {
            swapType[strategyRewardTokens[i]] = SwapType.TRADE_FACTORY;
        }
    }

    /// -----------------------------------------------------------------------
    /// Auction Configuration
    /// -----------------------------------------------------------------------

    /// @notice Set the auction address
    function setAuction(address _auction) external onlyManagement {
        if (_auction != address(0)) {
            // Verify the auction contract is properly configured for this strategy
            require(IAuction(_auction).want() == address(asset), "Auction want must be asset");
            require(IAuction(_auction).receiver() == address(this), "Auction receiver must be strategy");
        }

        auction = _auction;
    }

    /// @notice Configure all reward tokens to use auctions
    function setAllTokensToAuction() external onlyManagement {
        require(auction != address(0), "No auction configured");

        uint256 rewardCount = strategyRewardTokens.length;
        for (uint256 i = 0; i < rewardCount; i++) {
            swapType[strategyRewardTokens[i]] = SwapType.AUCTION;
        }
    }

    /// -----------------------------------------------------------------------
    /// Swap Configuration
    /// -----------------------------------------------------------------------

    /// @notice Set the swap type for a specific token
    function setSwapType(address _token, SwapType _swapType) external onlyManagement {
        swapType[_token] = _swapType;
    }

    /// @notice Set minimum amount for a token to be considered for swapping
    function setMinAmountToSellMapping(address _token, uint256 _minAmount) external onlyManagement {
        minAmountToSellMapping[_token] = _minAmount;
    }

    /// @notice Batch set minimum amounts for multiple tokens
    function setMinAmountsToSellMapping(address[] calldata _tokens, uint256[] calldata _minAmounts) external onlyManagement {
        require(_tokens.length == _minAmounts.length, "Arrays must be same length");
        for (uint256 i = 0; i < _tokens.length; i++) {
            minAmountToSellMapping[_tokens[i]] = _minAmounts[i];
        }
    }

    /*//////////////////////////////////////////////////////////////
                   KEEPER (onlyKeepers) FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Manually start an auction for a specific token
    /// @return The auction address used
    function kickAuction(address _token) external onlyKeepers returns (address) {
        require(swapType[_token] == SwapType.AUCTION, "Token not configured for auction");
        return _kickAuction(_token);
    }
}
