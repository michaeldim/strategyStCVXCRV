// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

contract MockAuctionFactory {
    address public lastAuction;
    event AuctionCreated(address indexed auction);

    function createNewAuction(address asset, address recipient) external returns (address) {
        // For testing, just emit an event and return a dummy address
        address auction = address(uint160(uint256(keccak256(abi.encodePacked(asset, recipient, block.timestamp)))));
        lastAuction = auction;
        emit AuctionCreated(auction);
        return auction;
    }
}
