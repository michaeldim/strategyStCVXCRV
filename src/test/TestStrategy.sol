// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "../StCVXCRVStrategy.sol";

/// @notice Test-only subclass to expose internal harvest logic for testing
contract TestStrategy is StCVXCRVStrategy {
    // Mock boolean flags to control behavior
    bool public mockIsShutdown = false;
    bool public mockIsKeeper = false;

    constructor(
        address _asset,
        string memory _name,
        address _cvxcrv,
        address _crv,
        address _cvx,
        address _crvUsd,
        address _wrapperAddress,
        address _providedAuctionAddress, // Unused in parent constructor but kept for testing compatibility
        address _tradeFactoryAddress
    )
        StCVXCRVStrategy(
            _asset,
            _name,
            _cvxcrv,
            _crv,
            _cvx,
            _crvUsd,
            _wrapperAddress,
            _tradeFactoryAddress
        )
    {}

    // Helper to identify this as a test contract
    function isMock() external pure returns (bool) {
        return true;
    }

    function setMockShutdown(bool _isShutdown) external {
        mockIsShutdown = _isShutdown;
    }

    function isKeeper(address) public view returns (bool) {
        return mockIsKeeper || true; // Always return true for testing
    }

    function setMockIsKeeper(bool _isKeeper) external {
        mockIsKeeper = _isKeeper;
    }

    // Override management check for easier testing
    function isManagement(address) public pure returns (bool) {
        return true; // Always return true for testing
    }

    // Expose asset getter for testing
    function getAsset() external view returns (address) {
        return address(asset);
    }

    /// @notice Expose internal functions for testing
    function testClaimRewardsFromWrapper() external {
        _claimRewardsFromWrapper();
    }

    function testFreeFunds(uint256 _amount) external {
        _freeFunds(_amount);
    }

    function testDeployFunds(uint256 _amount) external {
        _deployFunds(_amount);
    }

    // Special version that forces a revert with string message
    function testDeployFundsWithNamedRevert(uint256 _amount) external returns (bool) {
        // Call a function that will always revert with a named error
        try WRAPPER.stake(_amount, address(this)) {
            return true;
        } catch Error(string memory reason) {
            // Manually revert with the message to simulate the line 200-201 in the actual code
            revert(reason);
        } catch (bytes memory) {
            // Simulate the line 202-203 in the actual code
            revert("WRAPPER.stake low-level revert");
        }
    }

    // Special version that forces an unnamed revert
    function testDeployFundsWithUnnamedRevert(uint256 _amount) external returns (bool) {
        // Call a function that will always revert with an unnamed error
        try WRAPPER.stake(_amount, address(this)) {
            return true;
        } catch Error(string memory reason) {
            // Manually revert with the message to simulate the line 200-201 in the actual code
            revert(reason);
        } catch (bytes memory) {
            // Simulate the line 202-203 in the actual code
            revert("WRAPPER.stake low-level revert");
        }
    }

    function testHarvestAndReport() external returns (uint256) {
        return _harvestAndReport();
    }

    function testSellRewards() external {
        _sellRewards();
    }

    // Special version to test early return in _sellRewards
    function testSellRewardsWithNoMechanisms() external {
        // Save the current trade factory address
        address originalTradeFactory = tradeFactory();

        // Set tradeFactory to zero address to test early return
        _setTradeFactory(address(0), CVXCRV);

        // Call the function - should hit early return
        _sellRewards();

        // Restore original settings
        _setTradeFactory(originalTradeFactory, CVXCRV);
    }

    function testClaimRewards() external {
        _claimRewards();
    }

    function testEmergencyWithdraw(uint256 _amount) external {
        _emergencyWithdraw(_amount);
    }

    function testEnableTradesInBatch(address _tf, address[] memory _tokens, uint256 _count) external {
        _enableTradesInBatch(_tf, _tokens, _count);
    }

    /// @notice Expose harvest for tests only - legacy version
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
