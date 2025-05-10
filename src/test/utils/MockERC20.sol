// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockERC20 is IERC20 {
    // Always return 0 for allowance to prevent SafeERC20 reverts in tests
    function allowance(address, address) public pure override returns (uint256) {
        return 0;
    }
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 public override totalSupply;
    mapping(address => uint256) public override balanceOf;


    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "MockERC20: transfer amount exceeds balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    // No-op approve for compatibility
    function approve(address, uint256) external pure override returns (bool) {
        return true;
    }

    // No-op transferFrom for compatibility
    function transferFrom(address, address, uint256) external pure override returns (bool) {
        return true;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(balanceOf[from] >= amount, "MockERC20: burn amount exceeds balance");
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }
}
