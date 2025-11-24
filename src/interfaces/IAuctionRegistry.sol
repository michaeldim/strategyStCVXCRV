// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

interface IAuctionRegistry {
    function getAllFactories() external view returns (address[] memory);
}

interface IAuctionFactory {
    function getAllAuctions() external view returns (address[] memory);
}
