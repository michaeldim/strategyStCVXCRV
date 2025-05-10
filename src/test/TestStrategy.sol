// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "../Strategy.sol";

/// @notice Test-only subclass to expose internal harvest logic for testing
contract TestStrategy is Strategy {
    bool public mockIsShutdown = false;

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
    ) Strategy(
        _asset,
        _name,
        _cvxcrv,
        _crv,
        _cvx,
        _crvUsd,
        _wrapperAddress,
        _providedAuctionAddress,
        _tradeFactoryAddress
    ) {}

    function setMockShutdown(bool _isShutdown) external {
        mockIsShutdown = _isShutdown;
    }

    /// @notice Expose harvest for tests only
    function testHarvest() external returns (uint256 profit) {
        return _fixedHarvestAndReport();
    }

    /// @dev Modified version that doesn't use TokenizedStrategy.isShutdown()
    function _fixedHarvestAndReport() internal returns (uint256 _totalAssets) {
        if (!mockIsShutdown) {
            _claimRewardsFromWrapper();
        }

        _sellRewards();

        uint256 cvxCrvBal = IERC20(CVXCRV).balanceOf(address(this));
        if (cvxCrvBal > 0 && !mockIsShutdown) {
            try WRAPPER.stake(cvxCrvBal, address(this)) {
                // Intentionally empty: continue if stake succeeds
            } catch {
                // Intentionally empty: continue if stake fails, funds remain in strategy
            }
        }

        // Get balances to calculate total assets
        uint256 freeBalance = IERC20(asset).balanceOf(address(this));
        uint256 stakedBalance = WRAPPER.balanceOf(address(this));

        // Return total assets
        return freeBalance + stakedBalance;
    }
}
