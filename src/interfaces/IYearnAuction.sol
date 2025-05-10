// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

/**
 * @title IYearnAuction
 * @notice Interface for Yearn Auction contracts
 */
interface IYearnAuction {
    function want() external view returns (address);
    function kick(address token) external returns (uint256);
    function enable(address token) external;
    function disable(address token) external;
}