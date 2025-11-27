// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {BaseStrategy} from "@tokenized-strategy/BaseStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ICvxCrvStakingWrapper} from "./interfaces/ICvxCrvStakingWrapper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AuctionSwapper, Auction} from "@periphery/swappers/AuctionSwapper.sol";

/**
 * @title Convex stkCvxCrv Compounder
 * @notice This strategy stakes cvxCRV via a wrapper to earn CRV, CVX, and crvUSD rewards, then compounds these rewards back into cvxCRV.
 */
contract ConvexStkCvxCrvStrategy is BaseStrategy, AuctionSwapper {
    using SafeERC20 for IERC20;

    // --- Constants ---
    ICvxCrvStakingWrapper public constant WRAPPER = ICvxCrvStakingWrapper(0xaa0C3f5F7DFD688C6E646F66CD2a6B66ACdbE434);

    // --- Per-token auction thresholds ---
    mapping(address => uint256) public tokenMinAmountToSell;

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    constructor(address _asset, string memory _name) BaseStrategy(_asset, _name) {
        IERC20(address(asset)).forceApprove(address(WRAPPER), type(uint256).max);
    }

    // -----------------------------------------------------------------------
    // View Functions
    // -----------------------------------------------------------------------

    /**
     * @notice Returns the maximum amount that can be deposited
     * @return The maximum deposit amount, 0 if wrapper is shutdown
     */
    function availableDepositLimit(address) public view override returns (uint256) {
        if (WRAPPER.isShutdown()) {
            return 0;
        }
        return type(uint256).max;
    }

    // -----------------------------------------------------------------------
    // Core Strategy Implementation
    // -----------------------------------------------------------------------

    /**
     * @dev Deploys up to '_amount' of asset in the yield source (stakes cvxCRV)
     * @param _amount Amount of asset to stake
     */
    function _deployFunds(uint256 _amount) internal override {
        WRAPPER.stake(_amount, address(this));
    }

    /**
     * @dev Attempts to free '_amount' of asset (unstake cvxCRV)
     * @param _amount Amount of asset to unstake
     */
    function _freeFunds(uint256 _amount) internal override {
        WRAPPER.withdraw(Math.min(_amount, WRAPPER.balanceOf(address(this))));
    }

    /**
     * @dev Core harvest function. Claims rewards and reinvests any asset balance
     * @return _totalAssets Total assets under management after harvest
     */
    function _harvestAndReport() internal virtual override returns (uint256 _totalAssets) {
        _claimRewards();

        uint256 assetBal = asset.balanceOf(address(this));
        if (assetBal > 0 && !TokenizedStrategy.isShutdown() && !WRAPPER.isShutdown()) {
            _deployFunds(assetBal);
        }

        return asset.balanceOf(address(this)) + WRAPPER.balanceOf(address(this));
    }

    /**
     * @dev Emergency withdrawal if strategy is shutdown
     * @param _amount Amount of asset to withdraw
     */
    function _emergencyWithdraw(uint256 _amount) internal override {
        _freeFunds(_amount);
    }

    /**
     * @dev Claims rewards from the wrapper
     */
    function _claimRewards() internal {
        WRAPPER.getReward(address(this));
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
            require(Auction(_auction).want() == address(asset), "Auction want must be asset");
        }
        _setAuction(_auction);
    }

    /**
     * @notice Set minimum amount for a token to be auctioned
     * @param _token Token address
     * @param _minAmount Minimum amount to trigger auction
     */
    function setMinAmountToSell(address _token, uint256 _minAmount) external onlyManagement {
        tokenMinAmountToSell[_token] = _minAmount;
    }

    // -----------------------------------------------------------------------
    // Staking Wrapper Configuration
    // -----------------------------------------------------------------------

    /**
     * @notice Get the current reward weight for this strategy
     * @return The current reward weight
     */
    function getRewardWeight() external view returns (uint256) {
        return WRAPPER.userRewardWeight(address(this));
    }

    /**
     * @notice Set reward weight for staking wrapper
     * @param _weight New weight to set
     */
    function setRewardWeight(uint256 _weight) external onlyManagement {
        uint256 currentWeight = WRAPPER.userRewardWeight(address(this));
        if (_weight != currentWeight) {
            WRAPPER.setRewardWeight(_weight);
        }
    }

    // -----------------------------------------------------------------------
    // Auction Overrides
    // -----------------------------------------------------------------------

    /**
     * @notice Override kickable to exclude asset/wrapper tokens and check per-token threshold
     * @param _token The token to check
     * @return The amount available to kick, or 0 if invalid token or below threshold
     */
    function kickable(address _token) public view override returns (uint256) {
        if (_token == address(asset) || _token == address(WRAPPER)) return 0;

        uint256 _minAmount = tokenMinAmountToSell[_token];
        if (_minAmount == 0) return 0;

        uint256 _kickable = super.kickable(_token);
        if (_kickable < _minAmount) return 0;

        return _kickable;
    }

    /**
     * @notice Override auctionTrigger to exclude asset and wrapper tokens
     * @param _from The token to potentially auction
     * @return shouldKick Whether an auction should be kicked
     * @return data Calldata for the kick function or error message
     */
    function auctionTrigger(
        address _from
    ) external view override returns (bool shouldKick, bytes memory data) {
        if (_from == address(asset) || _from == address(WRAPPER)) {
            return (false, bytes("Invalid token"));
        }

        address _auction = auction;
        if (_auction == address(0)) {
            return (false, bytes("No auction set"));
        }

        if (!useAuction) {
            return (false, bytes(
                "Auctions disabled"));
        }

        uint256 kickableAmount = kickable(_from);
        if (kickableAmount == 0) {
            return (false, bytes("not enough kickable"));
        }

        return (true, abi.encodeCall(this.kickAuction, (_from)));
    }

    /**
     * @dev Override _kickAuction to add token validation
     * @param _from The token to auction
     */
    function _kickAuction(address _from) internal override returns (uint256) {
        require(_from != address(asset), "Cannot auction strategy asset");
        require(_from != address(WRAPPER), "Cannot auction wrapper");
        return super._kickAuction(_from);
    }
}
