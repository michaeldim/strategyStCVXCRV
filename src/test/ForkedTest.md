# ForkedTest Issues and Fix Notes

The `ForkedTest.t.sol` has been temporarily disabled due to issues with permissions and AccessControl when testing on a forked environment. The main error was:

```
FAIL: AccessControl: account 0x18a9cb93349f6a24a15b3199d12090e073b19cfb is missing role 0x49e347583a7b9e7f325e8963ee1f94127eba81e401796874b5a22f7c8f9d45f7
```

## Why was it disabled?

1. The test was attempting to interact with Yearn's TradeFactory contract which uses AccessControl for permission management.
2. The mocking approach was incomplete - we needed to mock more aspects of the AccessControl system.
3. The `SimplifiedForkedTest.t.sol` already provides a working example of forked testing without these issues.

## How to fix this test

If you need to enable this test in the future, consider these approaches:

1. Complete mocking: Mock all AccessControl functions and related calls in the TradeFactory contract
2. Use a more comprehensive mocking strategy for TradeFactory interactions
3. Deploy a mock TradeFactory for testing instead of using the real one
4. Implement fork test helpers to better handle access control systems

## Mock implementations to consider

```solidity
// More comprehensive mocking example for TradeFactory permissions
bytes32 strategyManagerRole = bytes32(0x49e347583a7b9e7f325e8963ee1f94127eba81e401796874b5a22f7c8f9d45f7);

// Mock all relevant AccessControl functions
vm.mockCall(
    TRADE_FACTORY,
    abi.encodeWithSignature("STRATEGY_MANAGER_ROLE()"),
    abi.encode(strategyManagerRole)
);

// Generic mock to return true for any address
vm.mockCall(
    TRADE_FACTORY,
    abi.encodeWithSelector(bytes4(keccak256("hasRole(bytes32,address)"))),
    abi.encode(true)
);

// Mock getRoleAdmin if needed
vm.mockCall(
    TRADE_FACTORY,
    abi.encodeWithSelector(bytes4(keccak256("getRoleAdmin(bytes32)"))),
    abi.encode(strategyManagerRole)
);

// Mock all needed TradeFactory actions
vm.mockCall(
    TRADE_FACTORY,
    abi.encodeWithSignature("enable(address,address)", CRV, CVXCRV),
    abi.encode()
);
```

For now, use the `SimplifiedForkedTest.t.sol` for forked environment testing.