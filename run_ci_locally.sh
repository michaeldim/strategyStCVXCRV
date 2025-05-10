#!/bin/bash

# This script simulates the GitHub workflow locally

cd . || exit

# Set colors for pretty output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Function to show a spinner during long-running operations
spinner() {
  local pid=$1
  local delay=0.1
  local spinstr='|/-\'
  while [ "$(ps -p $pid -o pid=)" ]; do
    local temp=${spinstr#?}
    printf " [%c]  " "$spinstr"
    local spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\b\b\b\b\b\b"
  done
  printf "    \b\b\b\b"
}

echo -e "${BOLD}${BLUE}=== Yearn Strategy CI Checks ===${NC}"
echo -e "${YELLOW}Running GitHub Actions checks locally${NC}"
echo "========================================"

echo -e "${YELLOW}1. Running Prettier format check...${NC}"
yarn format:check > /tmp/format_check.log 2>&1 &
spinner $!
if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ Format check passed${NC}"
else
  FORMAT_FAILED=true
  echo -e "${RED}✗ Format check failed${NC}"
fi

echo -e "${YELLOW}2. Running Solhint linter check...${NC}"
yarn lint > /tmp/lint_check.log 2>&1 &
spinner $!
if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ Linter check passed${NC}"
else
  LINT_FAILED=true
  echo -e "${RED}✗ Linter check failed${NC}"
fi

echo -e "${YELLOW}3. Testing commit message format...${NC}"
# Test with sample commit message
echo "Sample commit with conventional format:"
echo "feat: sample commit message" | npx commitlint

# Check the last commit message if we're in a git repo
if [ -d .git ]; then
  echo -e "${YELLOW}Checking last actual commit message:${NC}"
  COMMIT_MSG=$(git log -1 --pretty=format:"%s")
  echo "$COMMIT_MSG"
  echo "$COMMIT_MSG" | npx commitlint > /tmp/commit_check.log 2>&1
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Commit format check passed${NC}"
  else
    COMMIT_FAILED=true
    echo -e "${RED}✗ Commit format check failed${NC}"
  fi
else
  echo "Not in a git repository, skipping git commit check"
fi

# Run Slither security analysis
echo -e "${YELLOW}4. Running Slither security analysis...${NC}"
# Check if slither is installed
if command -v slither &> /dev/null; then
  # Using similar settings as GitHub workflow
  echo -e "${YELLOW}Running Slither on StCVXCRVStrategy.sol...${NC}"

  # Remove any existing slither output to avoid the prevention of overwrite
  rm -f /tmp/slither_results.json

  # Run on StCVXCRVStrategy.sol
  slither src/StCVXCRVStrategy.sol --json /tmp/slither_results.json > /tmp/slither_check.log 2>&1
  SLITHER_EXIT_CODE=$?

  # Count number of medium or high findings
  if [ -f /tmp/slither_results.json ]; then
    # Use -s to suppress error messages when no matches are found
    HIGH_FINDINGS=$(grep -c -s '"impact": "High"' /tmp/slither_results.json || echo 0)
    MEDIUM_FINDINGS=$(grep -c -s '"impact": "Medium"' /tmp/slither_results.json || echo 0)

    # Make sure these are actual integers
    HIGH_FINDINGS=$(echo $HIGH_FINDINGS | tr -d '[:space:]')
    MEDIUM_FINDINGS=$(echo $MEDIUM_FINDINGS | tr -d '[:space:]')

    # Default to 0 if empty
    [ -z "$HIGH_FINDINGS" ] && HIGH_FINDINGS=0
    [ -z "$MEDIUM_FINDINGS" ] && MEDIUM_FINDINGS=0

    if [ "$HIGH_FINDINGS" -gt 0 ]; then
      echo -e "${RED}✗ Slither found $HIGH_FINDINGS high severity issues in StCVXCRVStrategy.sol${NC}"
      SLITHER_FAILED=true
    elif [ $SLITHER_EXIT_CODE -ne 0 ]; then
      echo -e "${RED}✗ Slither check on StCVXCRVStrategy.sol failed with exit code $SLITHER_EXIT_CODE${NC}"
      SLITHER_FAILED=true
    else
      echo -e "${GREEN}✓ Slither check on StCVXCRVStrategy.sol passed${NC}"
    fi
  else
    if [ $SLITHER_EXIT_CODE -ne 0 ]; then
      echo -e "${RED}✗ Slither check on StCVXCRVStrategy.sol failed with exit code $SLITHER_EXIT_CODE${NC}"
      SLITHER_FAILED=true
    else
      echo -e "${GREEN}✓ Slither check on StCVXCRVStrategy.sol passed${NC}"
    fi
  fi
else
  echo -e "${YELLOW}⚠ Slither not installed. Install with: pip3 install slither-analyzer${NC}"
fi  # First fix the commit message issue by modifying our HEAD commit
  if [ -d .git ] && [[ "$COMMIT_FAILED" == true ]]; then
    echo -e "${YELLOW}Attempting to fix the commit message automatically...${NC}"
    CURRENT_MSG=$(git log -1 --pretty=format:"%s")
    # Extract the message part, ignoring any type prefix
    MSG_CONTENT=$(echo "$CURRENT_MSG" | sed -E 's/^[a-z]+(\([a-z-]+\))?:\s*//i')
    if [[ -z "$MSG_CONTENT" ]]; then
      # If we couldn't extract content, use the whole message
      MSG_CONTENT="$CURRENT_MSG"
    fi

    # Suggest a fixed commit message
    FIXED_MSG="refactor: $MSG_CONTENT"
    echo -e "${YELLOW}Suggested fixed commit message: ${NC}$FIXED_MSG"
    echo -e "${YELLOW}To fix your commit message, run:${NC}"
    echo -e "  ${BLUE}git commit --amend -m \"$FIXED_MSG\"${NC}"
  fi

  # Optional - check for any uncommitted changes
  if [ -d .git ]; then
    echo -e "${YELLOW}5. Checking for uncommitted changes...${NC}"
    UNCOMMITTED=$(git status --porcelain | wc -l)
    if [ "$UNCOMMITTED" -eq 0 ]; then
      echo -e "${GREEN}✓ No uncommitted changes${NC}"
    else
      echo -e "${YELLOW}! You have $UNCOMMITTED uncommitted changes${NC}"
    fi
  fi

echo "========================================"

if [ "$FORMAT_FAILED" = true ] || [ "$LINT_FAILED" = true ] || [ "$COMMIT_FAILED" = true ] || [ "$SLITHER_FAILED" = true ]; then
  echo -e "${RED}❌ Some checks failed!${NC}"
  [ "$FORMAT_FAILED" = true ] && echo -e "${RED}  - Format check failed${NC}" && cat /tmp/format_check.log
  [ "$LINT_FAILED" = true ] && echo -e "${RED}  - Linter check failed${NC}" && cat /tmp/lint_check.log
  [ "$COMMIT_FAILED" = true ] && echo -e "${RED}  - Commit format check failed${NC}" && cat /tmp/commit_check.log

  if [ "$SLITHER_FAILED" = true ]; then
    echo -e "${RED}  - Slither security check failed${NC}"
    if [ -f /tmp/slither_results.json ]; then
      echo -e "${RED}    Medium/High severity findings:${NC}"
      grep -A 10 -B 2 '"impact": "High"\|"impact": "Medium"' /tmp/slither_results.json | grep -E '"check"|"impact"|"description"|"elements"' | sed 's/^/      /'
    else
      cat /tmp/slither_check.log
    fi

    # Add an option to bypass slither checks when needed during development
    if [ "$1" = "--ignore-slither" ]; then
      echo -e "${YELLOW}Ignoring Slither failures due to --ignore-slither flag${NC}"
      SLITHER_FAILED=false
    else
      echo -e "${YELLOW}Note: You can bypass Slither checks during development with:${NC}"
      echo -e "  ${BLUE}./run_ci_locally.sh --ignore-slither${NC}"
    fi
  fi

  echo ""
  echo -e "${YELLOW}Recommendations:${NC}"
  [ "$FORMAT_FAILED" = true ] && echo "  - Run 'yarn format' to fix formatting issues"
  [ "$LINT_FAILED" = true ] && echo "  - Run 'yarn lint:fix' to fix linting issues"
  [ "$COMMIT_FAILED" = true ] && echo "  - Format your commit messages as: 'type(scope): message'"
  [ "$COMMIT_FAILED" = true ] && echo "    Valid types: feat, fix, docs, style, refactor, perf, test, ci, chore, revert"
  [ "$SLITHER_FAILED" = true ] && echo "  - Check full Slither output in /tmp/slither_check.log"
  [ "$SLITHER_FAILED" = true ] && echo "  - Fix medium and high severity security issues before committing"

  # Only exit with error if there are still failures after processing flags
  if [ "$FORMAT_FAILED" = true ] || [ "$LINT_FAILED" = true ] || [ "$COMMIT_FAILED" = true ] || [ "$SLITHER_FAILED" = true ]; then
    exit 1
  fi
else
  echo -e "${GREEN}✅ All checks passed!${NC}"
  echo -e "${GREEN}Your code is ready to be committed!${NC}"

  # Check if there are uncommitted changes
  if [ -d .git ] && [ "$(git status --porcelain | wc -l)" -ne 0 ]; then
    echo -e "${YELLOW}Don't forget to commit your changes:${NC}"
    echo -e "  ${BLUE}git add .${NC}"
    echo -e "  ${BLUE}git commit -m \"feat: your meaningful commit message\"${NC}"
  fi

  exit 0
fi
