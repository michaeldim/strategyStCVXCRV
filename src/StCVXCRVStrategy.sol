// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

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
contract StCVXCRVStrategy is BaseHealthCheck, AuctionSwapper, TradeFactorySwapper, ReentrancyGuard {
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
    uint256 public idleThreshold = 25 * 10**18;

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
    )
        BaseHealthCheck(_asset, _name)
    {
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
    function pendingRewards() external view returns (
        uint256 crv,
        uint256 cvx,
        uint256 crvUsd,
        bool crvExceedsMin,
        bool cvxExceedsMin,
        bool crvUsdExceedsMin
    ) {
        crv = IERC20(CRV).balanceOf(address(this));
        cvx = IERC20(CVX).balanceOf(address(this));
        crvUsd = IERC20(CRVUSD).balanceOf(address(this));

        crvExceedsMin = crv > minAmountToSell[CRV];
        cvxExceedsMin = cvx > minAmountToSell[CVX];
        crvUsdExceedsMin = crvUsd > minAmountToSell[CRVUSD];
    }

    /// @notice Returns current trade factory and tokens set up for trading
    function tradeFactoryInfo() external view returns (address _tradeFactory, address[] memory _tokens) {
        _tradeFactory = tradeFactory();
        _tokens = super.rewardTokens();
    }

    /// @notice Returns swap configuration status and minimums for each reward token
    function swapperConfig() external view returns (
        bool _useTradeFactory,
        bool _useAuction,
        address _tradeFactory,
        address _auction,
        uint256[] memory _minAmounts,
        address[] memory _tokens
    ) {
        _useTradeFactory = useTradeFactory;
        _useAuction = useAuction;
        _tradeFactory = tradeFactory();
        _auction = auction;

        _tokens = new address[](strategyRewardTokens.length);
        _minAmounts = new uint256[](strategyRewardTokens.length);

        for (uint256 i = 0; i < strategyRewardTokens.length; i++) {
            _tokens[i] = strategyRewardTokens[i];
            _minAmounts[i] = minAmountToSell[strategyRewardTokens[i]];
        }
    }

    /// @notice Get current health check configuration
    function getHealthCheckConfig() external view returns (bool _enabled, uint256 _profitLimit, uint256 _lossLimit) {
        _enabled = doHealthCheck;
        _profitLimit = profitLimitRatio();
        _lossLimit = lossLimitRatio();
    }

    /// @notice Gets max amount of asset that can be withdrawn
    function availableWithdrawLimit(address /*_owner*/) public view override returns (uint256) {
        return IERC20(CVXCRV).balanceOf(address(this));
    }

    /// @notice Gets max amount of asset that can be deposited
    function availableDepositLimit(address /*_owner*/) public view override returns (uint256) {
        if (TokenizedStrategy.isShutdown()) return 0;
        uint256 currentTotalAssets = TokenizedStrategy.totalAssets();
        return currentTotalAssets >= depositLimit ? 0 : depositLimit - currentTotalAssets;
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
        try WRAPPER.withdraw(_amount) {
            // Success
        } catch {
            // Continue if withdraw fails
        }
    }

    /// @dev Core harvest function. Claims rewards, sells them for asset, and reinvests
    function _harvestAndReport()
        internal
        virtual
        override
        returns (uint256 _totalAssets)
    {
        if (!TokenizedStrategy.isShutdown()) {
            _claimRewardsFromWrapper();
        }

        _sellRewards();

        uint256 cvxCrvBal = IERC20(CVXCRV).balanceOf(address(this));
        if (cvxCrvBal > 0 && !TokenizedStrategy.isShutdown()) {
            try WRAPPER.stake(cvxCrvBal, address(this)) {
                // Success
            } catch {
                // Continue if stake fails, funds remain in strategy
            }
        }

        // Get balances to calculate total assets
        _totalAssets = asset.balanceOf(address(this)) + WRAPPER.balanceOf(address(this));
    }

    /// @dev Emergency withdrawal if strategy is shutdown
    function _emergencyWithdraw(uint256 _amount) internal override {
        uint256 available = IERC20(CVXCRV).balanceOf(address(this));
        if (_amount > available) {
            _amount = available;
        }
        try WRAPPER.withdraw(_amount) {
            // Success
        } catch {
            // Continue if withdraw fails
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
        address _tf = tradeFactory();
        for (uint256 i = 0; i < strategyRewardTokens.length; i++) {
            address reward = strategyRewardTokens[i];
            uint256 balance = IERC20(reward).balanceOf(address(this));
            uint256 minAmount = minAmountToSell[reward];

            if (balance > minAmount) {
                if (useAuction && auction != address(0)) {
                    _kickAuction(reward);
                    if (_tf != address(0)) {
                        try ITradeFactory(_tf).enable(reward, CVXCRV) {} catch {}
                    }
                } else if (useTradeFactory && _tf != address(0)) {
                    try ITradeFactory(_tf).enable(reward, CVXCRV) {} catch {}
                }
            }
        }
    }

    /// @dev Starts auction for a reward token
    function _kickAuction(address _from) internal virtual override returns (uint256) {
        if (auction == address(0)) {
            return 0;
        }
        uint256 _balance = IERC20(_from).balanceOf(address(this));
        IERC20(_from).safeTransfer(auction, _balance);
        uint256 id = Auction(auction).kick(_from);
        return id;
    }

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
    function setMinAmountToSell(address _token, uint256 _minAmount) external onlyManagement {
        minAmountToSell[_token] = _minAmount;
    }

    /// @notice Batch set minimum amounts for multiple tokens
    function setMinAmountsToSell(address[] calldata _tokens, uint256[] calldata _minAmounts) external onlyManagement {
        require(_tokens.length == _minAmounts.length, "Arrays must be same length");
        for (uint256 i = 0; i < _tokens.length; i++) {
            minAmountToSell[_tokens[i]] = _minAmounts[i];
        }
    }

    /// @notice Enable/disable TradeFactory for swapping rewards
    function setUseTradeFactory(bool _useTradeFactory) external onlyManagement {
        require(_useTradeFactory == false || tradeFactory() != address(0), "TradeFactory not set");
        useTradeFactory = _useTradeFactory;
    }

    /// @notice Enable/disable Auctions for swapping rewards
    function setUseAuction(bool _useAuction) external onlyManagement {
        require(_useAuction == false || auction != address(0), "Auction not set");
        useAuction = _useAuction;
    }

    /// @notice Set the address of the auction contract
    function setAuctionAddress(address _newAuctionAddress) external onlyManagement {
        auction = _newAuctionAddress;
    }

    /// @notice Toggle health check functionality
    function setHealthCheck(bool _doHealthCheck) external onlyManagement {
        setDoHealthCheck(_doHealthCheck);
    }

    /// @notice Set max profit that can be reported (basis points)
    function setStrategyProfitLimitRatio(uint256 _profitLimitRatio) external onlyManagement {
        _setProfitLimitRatio(_profitLimitRatio);
    }

    /// @notice Set max loss that can be reported (basis points)
    function setStrategyLossLimitRatio(uint256 _lossLimitRatio) external onlyManagement {
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
}
