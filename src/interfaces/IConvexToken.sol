// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

/**
 * @title IConvexToken
 * @notice Interface for the Convex token contract with minting parameters
 */
interface IConvexToken {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    // Convex specific functions
    function reductionPerCliff() external view returns (uint256);
    function totalCliffs() external view returns (uint256);
    function maxSupply() external view returns (uint256);
}
