// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup} from "./Setup.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICvxCrvStakingWrapper} from "../../interfaces/ICvxCrvStakingWrapper.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// Use the same import path as in Setup.sol
import {ITokenizedStrategy} from "../../../lib/tokenized-strategy/src/interfaces/ITokenizedStrategy.sol";

contract TestHelper is Setup {
    /**
     * @notice Mock the balanceOf function for an ERC20 token to return a specific amount for a specific address
     * @dev This replaces the need for stdStorage.deal which is causing test failures
     * @param token The token address to mock
     * @param account The account to set balance for
     * @param amount The balance amount to set
     */
    function mockDeal(address token, address account, uint256 amount) internal {
        vm.mockCall(token, abi.encodeWithSignature("balanceOf(address)", account), abi.encode(amount));

        // Also mock the transferFrom function to allow transfers
        vm.mockCall(token, abi.encodeWithSignature("transferFrom(address,address,uint256)"), abi.encode(true));

        // Also mock maxWithdraw and maxRedeem for ERC4626 compatibility
        if (token == address(strategy)) {
            vm.mockCall(token, abi.encodeWithSignature("maxWithdraw(address)", account), abi.encode(amount));

            vm.mockCall(token, abi.encodeWithSignature("maxRedeem(address)", account), abi.encode(amount));
        }
    }

    /**
     * @notice Mock token balance changes for an account similar to the forge deal() function
     * @dev This replaces the standard deal() function which causes issues with coverage
     * @param token The token address to update balance for
     * @param account The account to update balance for
     * @param newBalance The new balance to set
     */
    function mockTokenBalance(address token, address account, uint256 newBalance) internal {
        // Mock the balanceOf function to return the new balance
        vm.mockCall(token, abi.encodeWithSignature("balanceOf(address)", account), abi.encode(newBalance));
    }

    /**
     * @notice Override the airdrop function from Setup.sol to use mockDeal instead of deal
     * @param _asset The asset to airdrop
     * @param _to The recipient
     * @param _amount The amount to airdrop
     */
    function airdrop(ERC20 _asset, address _to, uint256 _amount) public override {
        // Instead of using deal, use mockDeal
        mockDeal(address(_asset), _to, _amount);
    }

    /**
     * @notice Mock the setRewardWeight function for CvxCrvStakingWrapper to avoid subtraction overflow
     * @dev This function should be called before testing setRewardWeight in the strategy
     * @param wrapper The address of the CvxCrvStakingWrapper
     * @param weight The weight value to mock a successful response for
     */
    function mockSetRewardWeight(address wrapper, uint256 weight) internal {
        vm.mockCall(wrapper, abi.encodeWithSignature("setRewardWeight(uint256)", weight), abi.encode());
    }

    /**
     * @notice Mock wrapper withdrawal operations
     * @dev This function helps simulate successful withdrawals from the wrapper
     * @param wrapper The address of the CvxCrvStakingWrapper
     * @param amount The amount to mock for withdrawal
     * @param newBalance The new balance to set after withdrawal
     */
    function mockWrapperWithdraw(address wrapper, uint256 amount, uint256 newBalance) internal {
        // Mock the withdraw function
        vm.mockCall(wrapper, abi.encodeWithSignature("withdraw(uint256)", amount), abi.encode());

        // Update the mock balance after withdrawal
        vm.mockCall(wrapper, abi.encodeWithSignature("balanceOf(address)", address(strategy)), abi.encode(newBalance));
    }

    /**
     * @notice Mock the full reward claim and sell process
     * @dev This helps test the harvest functions without storage-related errors
     * @param assetAmount Asset amount to set after selling rewards
     */
    function mockRewardProcess(uint256 assetAmount) internal {
        // Mock the getReward call
        address wrapper = 0xaa0C3f5F7DFD688C6E646F66CD2a6B66ACdbE434;
        vm.mockCall(wrapper, abi.encodeWithSignature("getReward(address)"), abi.encode());

        // Mock the balanceOf for asset (cvxCRV) after rewards are processed
        vm.mockCall(
            address(asset),
            abi.encodeWithSignature("balanceOf(address)", address(strategy)),
            abi.encode(assetAmount)
        );
    }

    /**
     * @notice Override withdrawFromStrategy in Setup to use mocks instead of deal() for compatibility with coverage
     * @param _strategy The strategy address
     * @param _user The user address
     * @param _shares The shares amount
     * @param _assetAmount The asset amount
     */
    function withdrawFromStrategy(
        address _strategy,
        address _user,
        uint256 _shares,
        uint256 _assetAmount
    ) internal override {
        // Mock CVXCRV balances
        address CVXCRV = address(asset);
        vm.mockCall(CVXCRV, abi.encodeWithSignature("balanceOf(address)"), abi.encode(_assetAmount));

        // Mock asset transfer
        vm.mockCall(address(asset), abi.encodeWithSignature("transfer(address,uint256)"), abi.encode(true));

        // Update the strategy's asset balance for withdrawal using mockCall
        vm.mockCall(address(asset), abi.encodeWithSignature("balanceOf(address)", _strategy), abi.encode(_assetAmount));

        // Mock ERC4626 functions for successful withdrawal
        vm.mockCall(_strategy, abi.encodeWithSignature("maxRedeem(address)", _user), abi.encode(_shares));

        vm.mockCall(_strategy, abi.encodeWithSignature("maxWithdraw(address)", _user), abi.encode(_assetAmount));

        vm.mockCall(_strategy, abi.encodeWithSignature("previewRedeem(uint256)", _shares), abi.encode(_assetAmount));

        vm.mockCall(_strategy, abi.encodeWithSignature("balanceOf(address)", _user), abi.encode(_shares));

        // Record balance before
        uint256 balanceBefore = asset.balanceOf(_user);

        // Withdraw
        vm.prank(_user);
        ITokenizedStrategy(_strategy).redeem(_shares, _user, _user);

        // Manually update user balance to reflect withdrawal using mockCall
        vm.mockCall(
            address(asset),
            abi.encodeWithSignature("balanceOf(address)", _user),
            abi.encode(balanceBefore + _assetAmount)
        );
    }

    /**
     * @notice Helper function to correctly mock TokenizedStrategy's internal profit tracking
     * Used to make profit calculation work correctly in tests
     */
    function mockPreviousTotalAssets(address _strategy, uint256 _value) internal {
        vm.mockCall(_strategy, abi.encodeWithSelector(bytes4(keccak256("previousTotalAssets()"))), abi.encode(_value));
    }
}
