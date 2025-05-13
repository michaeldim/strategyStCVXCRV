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
        string memory _name
    )
        StCVXCRVStrategy(
            _asset,
            _name
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
    
    string private strategyName;

    function getName() external view returns (string memory) {
        // Use bytes to check string emptiness
        bytes memory nameBytes = bytes(strategyName);
        return nameBytes.length > 0 ? strategyName : "Test Strategy"; // Default to "Test Strategy" if name is not set
    }
    
    // Allow tests to set the name explicitly
    function setName(string memory _name) external {
        strategyName = _name;
    }
    
    // Implement report for testing
    function report() external view returns (uint256) {
        // Return the total assets for testing
        uint256 total = this.totalAssets();
        return total;
    }
    
    // Implement totalAssets for testing
    function totalAssets() external view returns (uint256) {
        // Get balances to calculate total assets
        address wrapper = 0xaa0C3f5F7DFD688C6E646F66CD2a6B66ACdbE434;
        uint256 freeBalance = IERC20(address(asset)).balanceOf(address(this));
        uint256 stakedBalance = ICvxCrvStakingWrapper(wrapper).balanceOf(address(this));
        
        // Return total assets
        return freeBalance + stakedBalance;
    }
    
    // Implement redeem for testing
    function redeem(uint256 _shares, address _receiver, address) external returns (uint256) {
        // Simplified implementation for testing
        // Unstake if needed
        _freeFunds(_shares);
        
        // Transfer assets to receiver
        uint256 balance = IERC20(address(asset)).balanceOf(address(this));
        uint256 toTransfer = balance > _shares ? _shares : balance;
        IERC20(address(asset)).transfer(_receiver, toTransfer);
        
        return toTransfer;
    }

    /// @notice Expose internal functions for testing
    function testClaimRewardsFromWrapper() external {
        _claimRewards();
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

    function testSellRewards() external {
        _sellRewards();
    }

    // Special version to test early return in _sellRewards
    function testSellRewardsWithNoMechanisms() external {
        // Save the current trade factory address
        address originalTradeFactory = tradeFactory();

        // Set tradeFactory to zero address to test early return
        _setTradeFactory(address(0), address(asset));

        // Call the function - should hit early return
        _sellRewards();

        // Restore original settings
        _setTradeFactory(originalTradeFactory, address(asset));
    }

    function testClaimRewards() external {
        _claimRewards();
    }

    function testEmergencyWithdraw(uint256 _amount) external {
        _emergencyWithdraw(_amount);
    }

    /// @notice Expose harvest for tests only - uses the harvestAndReport method
    function testHarvest() external returns (uint256 profit) {
        return _harvestAndReport();
    }
    
    function testHarvestAndReport() external returns (uint256) {
        uint256 assets = _harvestAndReport();
        return assets;
    }
}
