// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

import {BaseStrategy} from "@tokenized-strategy/BaseStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ICvxCrvStakingWrapper} from "./interfaces/ICvxCrvStakingWrapper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAuction} from "./interfaces/IAuction.sol";
import {IAuctionRegistry, IAuctionFactory} from "./interfaces/IAuctionRegistry.sol";

/**
 * @title Staked cvxCRV Compounder
 * @notice This strategy stakes cvxCRV via a wrapper to earn CRV, CVX, and crvUSD rewards, then compounds these rewards back into cvxCRV.
 */
contract StCVXCRVStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    // --- Constants ---
    ICvxCrvStakingWrapper public constant WRAPPER = ICvxCrvStakingWrapper(0xaa0C3f5F7DFD688C6E646F66CD2a6B66ACdbE434);
    IAuctionRegistry public constant AUCTION_REGISTRY = IAuctionRegistry(0x94F44706A61845a4f9e59c4Bc08cEA4503e48D12);
    address public constant auctionFactory = 0xd8e03D6D24d43c46c0f7f61327E391316E4f3c15;

    // --- Auction state ---
    address public auction;
    mapping(address => uint256) public minAmountToSell;

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
        if (assetBal > 0 && !TokenizedStrategy.isShutdown()) {
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
            require(_isOfficialAuction(_auction), "Auction not from official factory");
            require(IAuction(_auction).want() == address(asset), "Auction want must be asset");
            require(IAuction(_auction).receiver() == address(this), "Auction receiver must be strategy");
        }

        auction = _auction;
    }

    /**
     * @dev Verifies an auction was deployed from an official factory in the registry
     * @param _auction Address to verify
     * @return True if auction is from an official factory
     */
    function _isOfficialAuction(address _auction) internal view returns (bool) {
        address[] memory factories = AUCTION_REGISTRY.getAllFactories();

        for (uint256 i = 0; i < factories.length; i++) {
            address[] memory auctions = IAuctionFactory(factories[i]).getAllAuctions();
            for (uint256 j = 0; j < auctions.length; j++) {
                if (auctions[j] == _auction) {
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * @notice Kick an auction for a specific token
     * @dev Only keepers can call - set keeper to address(0) for permissionless
     * @param _token Token address to auction
     * @return _auctionId The ID of the started auction
     */
    function kickAuction(address _token) external onlyKeepers returns (uint256 _auctionId) {
        require(auction != address(0), "No auction configured");
        require(_token != address(asset), "Cannot auction strategy asset");
        require(_token != address(WRAPPER), "Cannot auction wrapper");

        uint256 balance = IERC20(_token).balanceOf(address(this));
        uint256 minAmount = minAmountToSell[_token];

        require(minAmount > 0 && balance >= minAmount, "Below threshold");

        IERC20(_token).safeTransfer(auction, balance);
        return IAuction(auction).kick(_token);
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
    // Auction Management (IAuctionSwapper compatible)
    // -----------------------------------------------------------------------

    /**
     * @notice Returns whether this strategy uses auctions for token swaps
     * @dev Part of IAuctionSwapper interface
     * @return True if an auction is configured
     */
    function useAuction() external view returns (bool) {
        return auction != address(0);
    }

    /**
     * @notice Set minimum amount for a token to be auctioned
     * @param _token Token address
     * @param _minAmount Minimum amount to trigger auction
     */
    function setMinAmountToSell(address _token, uint256 _minAmount) external onlyManagement {
        minAmountToSell[_token] = _minAmount;
    }

    /**
     * @notice Returns how much of a token can be kicked into auction
     * @dev Part of IAuctionSwapper interface - returns 0 if below minAmountToSell
     * @param _token The token to check
     * @return The amount available to kick, or 0 if below threshold
     */
    function kickable(address _token) external view returns (uint256) {
        if (auction == address(0)) return 0;
        if (_token == address(asset) || _token == address(WRAPPER)) return 0;

        uint256 balance = IERC20(_token).balanceOf(address(this));
        uint256 minAmount = minAmountToSell[_token];

        // Return 0 if below threshold or threshold not set
        if (minAmount == 0 || balance < minAmount) return 0;

        // Check if auction contract is ready (no active auction)
        if (IAuction(auction).kickable(_token) == 0) return 0;

        return balance;
    }

    /**
     * @notice Check if an auction should be triggered for a specific token
     * @param _from The token to potentially auction
     * @return Whether an auction should be kicked
     * @return Calldata for the kick function or error message
     */
    function auctionTrigger(address _from) external view returns (bool, bytes memory) {
        if (auction == address(0)) {
            return (false, bytes("No auction set"));
        }

        if (_from == address(asset) || _from == address(WRAPPER)) {
            return (false, bytes("Invalid token"));
        }

        uint256 balance = IERC20(_from).balanceOf(address(this));
        uint256 minAmount = minAmountToSell[_from];

        // If minAmount is 0, treat as disabled to prevent dust attacks
        if (minAmount == 0) {
            return (false, bytes("Min amount not set"));
        }

        if (balance < minAmount) {
            return (false, bytes("Below min amount"));
        }

        // Check if auction is kickable (no active auction)
        if (IAuction(auction).kickable(_from) == 0) {
            return (false, bytes("Auction not kickable"));
        }

        return (true, abi.encodeCall(this.kickAuction, (_from)));
    }
}
