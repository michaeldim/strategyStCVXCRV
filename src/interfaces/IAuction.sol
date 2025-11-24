// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

/**
 * @title Auction Interface
 * @notice Interface for an auction contract that can sell tokens for a target token
 */
interface IAuction {
    /// @notice Returns the address of the token the auction will swap to
    function want() external view returns (address);

    /// @notice Returns the address that should receive the want tokens
    function receiver() external view returns (address);

    /// @notice Starts an auction for the given token
    /// @param _token Address of the token to auction
    /// @return id ID of the auction
    function kick(address _token) external returns (uint256);

    /// @notice Returns the amount available to kick for a token
    /// @param _token Address of the token to check
    /// @return Amount kickable (0 if auction is active or no balance)
    function kickable(address _token) external view returns (uint256);
}
