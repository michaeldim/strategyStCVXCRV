#!/bin/bash

# Cleanup script for removing redundant test files after consolidation

# Define the root directory of the project
PROJECT_ROOT="/Users/michael/Development/projects/strategyStCVXCRV"
TEST_DIR="${PROJECT_ROOT}/src/test"
REDUNDANT_FILES=(
  "StrategyHarvest.t.sol"
  "StrategyHarvestFixed.t.sol"
  "TokenFixedHarvest.t.sol"
  "SimpleHarvest.t.sol"
  "DebugHarvest.t.sol"
  "FixedStrategy.t.sol"
  "Oracle.t.sol"
  "StrategyAprOracle.t.sol"
)

echo "Checking for redundant test files to remove..."

# Count variable for found files
found_count=0

# Check each redundant file
for file in "${REDUNDANT_FILES[@]}"; do
  file_path="${TEST_DIR}/${file}"
  if [ -f "$file_path" ]; then
    echo "Found redundant file: $file_path"
    rm "$file_path"
    echo "Removed: $file_path"
    found_count=$((found_count + 1))
  else
    echo "Not found (already removed): $file"
  fi
done

if [ $found_count -eq 0 ]; then
  echo "All redundant files have already been removed."
else
  echo "Removed $found_count redundant file(s)."
fi

echo "Cleanup complete."
