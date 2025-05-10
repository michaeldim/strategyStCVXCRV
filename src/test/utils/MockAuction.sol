// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IYearnAuction} from "../../interfaces/IYearnAuction.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./MockERC20.sol";

contract MockAuction is IYearnAuction {
    address public override want;
    mapping(address => bool) public enabled;
    uint256 public nextKickId = 1;

    // Mock return values
    uint256 private mockReturnAmount;
    mapping(address => uint256) private tokenReturnAmounts;

    event Kicked(address indexed token, uint256 id);
    event Enabled(address indexed token);
    event Disabled(address indexed token);

    constructor(address _want) {
        want = _want == address(0)
            ? address(0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7)
            : _want; // Default to cvxCRV if not specified
    }

    function kick(address token) external override returns (uint256) {
        uint256 id = nextKickId++;
        emit Kicked(token, id);
        return id;
    }

    function enable(address token) external override {
        enabled[token] = true;
        emit Enabled(token);
    }

    function disable(address token) external override {
        enabled[token] = false;
        emit Disabled(token);
    }

    // Additional functions for testing

    /**
     * @notice Mock function to simulate trading tokens for want token
     * @param _amount Amount of source token to trade
     * @param _srcToken Source token address
     * @param _destToken Destination token address (should be want)
     * @param _receiver Address to receive the output tokens
     * @return Amount of want tokens received
     */
    function initiateTrade(
        uint256 _amount,
        address _srcToken,
        address _destToken,
        address _receiver
    ) external returns (uint256) {
        require(
            _destToken == want || want == address(0),
            "MockAuction: destToken must be want"
        );
        require(enabled[_srcToken], "MockAuction: srcToken not enabled");

        // Transfer source tokens from sender to this contract
        bool success = IERC20(_srcToken).transferFrom(
            msg.sender,
            address(this),
            _amount
        );
        require(success, "MockAuction: transferFrom failed");

        // Determine return amount
        uint256 returnAmount;
        if (tokenReturnAmounts[_srcToken] > 0) {
            returnAmount = tokenReturnAmounts[_srcToken];
        } else {
            returnAmount = mockReturnAmount > 0 ? mockReturnAmount : _amount; // Default 1:1 swap
        }

        // Transfer want tokens to receiver (mint them if we're in test)
        if (_destToken != address(0)) {
            // For tests where we have a real token, try to transfer
            // Try a regular transfer first, but if it fails (due to lack of balance), try to mint
            try IERC20(_destToken).transfer(_receiver, returnAmount) {
                // Transfer succeeded
            } catch {
                // If transfer fails, try to cast to MockERC20 and mint
                // This works for our test cases where we're using MockERC20
                MockERC20 mockToken = MockERC20(_destToken);
                mockToken.mint(_receiver, returnAmount);
            }
        }

        return returnAmount;
    }

    // Helper functions for tests

    function setMockReturnAmount(uint256 _amount) external {
        mockReturnAmount = _amount;
    }

    function setTokenReturnAmount(address _token, uint256 _amount) external {
        tokenReturnAmounts[_token] = _amount;
    }

    function getMockReturnAmount() external view returns (uint256) {
        return mockReturnAmount;
    }
}
