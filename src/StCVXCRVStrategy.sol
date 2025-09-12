// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {BaseStrategy} from "@tokenized-strategy/BaseStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ICvxCrvStakingWrapper} from "./interfaces/ICvxCrvStakingWrapper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAuction} from "./interfaces/IAuction.sol";

/**
 * @title Staked cvxCRV Compounder
 * @notice This strategy stakes cvxCRV via a wrapper to earn CRV, CVX, and crvUSD rewards, then compounds these rewards back into cvxCRV.
 */
contract StCVXCRVStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    // --- Strategy state ---
    ICvxCrvStakingWrapper public constant WRAPPER = ICvxCrvStakingWrapper(0xaa0C3f5F7DFD688C6E646F66CD2a6B66ACdbE434);

    // --- Auction configuration ---
    address public auction;

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

        uint256 assetBal = IERC20(address(asset)).balanceOf(address(this));
        if (assetBal > 0 && !TokenizedStrategy.isShutdown()) {
            _deployFunds(assetBal);
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
            require(IAuction(_auction).want() == address(asset), "Auction want must be asset");
            require(IAuction(_auction).receiver() == address(this), "Auction receiver must be strategy");
        }

        auction = _auction;
    }

    /**
     * @notice Manually kick an auction for a specific token
     * @dev Can be called by keepers to auction any token held by the strategy
     * @param _token Token address to auction
     */
    function kickAuction(address _token) external onlyKeepers {
        require(auction != address(0), "No auction configured");
        require(_token != address(asset), "Cannot auction strategy asset");
        require(_token != address(WRAPPER), "Cannot auction wrapper");

        uint256 balance = IERC20(_token).balanceOf(address(this));
        require(balance > 0, "No tokens to auction");

        IERC20(_token).safeTransfer(auction, balance);
        IAuction(auction).kick(_token);
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
}
