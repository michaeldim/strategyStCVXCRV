## Testing Strategy

This repository employs a structured approach to testing the strategy contract and its components.

### Test Files Overview

#### Core Test Files
- **HarvestTests.t.sol**: Comprehensive tests for the harvest functionality, including normal conditions, edge cases, and error scenarios.
- **OracleTests.t.sol**: Tests for the APR Oracle, including price calculations, reward rate retrieval, and USD value conversions.
- **Operation.t.sol**: Tests for day-to-day operations of the strategy.
- **Shutdown.t.sol**: Tests for the strategy shutdown process and emergency functionality.
- **ForkedTest.t.sol**: Tests that run against a forked mainnet for integration testing.
- **FunctionSignature.t.sol**: Tests to ensure function signatures match expected interfaces.
- **Integration.t.sol**: System integration tests that verify how different components interact with each other.

#### Utility Files
- **TestStrategy.sol**: Utility contract for testing, providing hooks into the strategy.
- **utils/**: Directory containing mocks and helper contracts for testing.

### Test Organization

The tests are organized following these principles:

1. **Separation of Concerns**: Each test file focuses on a specific aspect of the strategy's functionality.
2. **Comprehensive Coverage**: Test cases cover normal operation, edge cases, and error conditions.
3. **Mock Dependencies**: External dependencies are mocked where appropriate to isolate testing.
4. **Reuse Test Components**: Common test fixtures and mocks are shared across test files.
5. **Realistic Scenarios**: Some tests simulate real-world conditions with realistic token values and TVL.

### Running Tests

To run the test suite:

```bash
# Run all tests
forge test
make test

# Run specific test categories
make test-harvest  # Run harvest-related tests
make test-oracle   # Run oracle-related tests
make test-core     # Run core functionality tests

# Run a specific test file
forge test --match-path src/test/HarvestTests.t.sol

# Run a specific test function
forge test --match-test test_StandardHarvest

# Run tests with gas reporting
forge test --gas-report
make gas
```

### Test Consolidation

The test suite was consolidated to reduce duplication and improve maintainability. The following files were combined:

#### Harvest Tests
- **HarvestTests.t.sol**: Consolidated from:
  - StrategyHarvest.t.sol
  - StrategyHarvestFixed.t.sol
  - TokenFixedHarvest.t.sol
  - SimpleHarvest.t.sol
  - DebugHarvest.t.sol
  - FixedStrategy.t.sol

#### Oracle Tests
- **OracleTests.t.sol**: Consolidated from:
  - Oracle.t.sol
  - StrategyAprOracle.t.sol
  - Oracle-related portions of Integration.t.sol

### Test Benefits

This consolidated approach provides several benefits:

1. **Reduced Maintenance Overhead**: Fewer files to maintain and keep in sync
2. **Better Test Coverage**: Comprehensive tests in a single file make it easier to ensure all edge cases are covered
3. **Improved Documentation**: Each test file now has a clear purpose and describes its test approach
4. **Faster Test Execution**: Running tests is more efficient with fewer file compilations
5. **Easier Onboarding**: New developers can understand the test strategy more quickly
