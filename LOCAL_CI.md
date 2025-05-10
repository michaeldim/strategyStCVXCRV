# Local CI Testing

This document explains how to run the CI checks locally before pushing to GitHub.

## Overview

Our repository uses GitHub Actions for Continuous Integration (CI), which runs a series of checks whenever you push code or create a pull request. To avoid surprises and save time, you can run these checks locally before committing your changes.

## Available Checks

The CI workflow runs the following checks:

1. **Code Formatting**: Uses Prettier to check if all Solidity and JSON files follow our formatting style.
2. **Linting**: Uses Solhint to check Solidity files for best practices and potential issues.
3. **Commit Message Format**: Ensures commit messages follow the [Conventional Commits](https://www.conventionalcommits.org/) specification.
4. **Security Analysis**: Uses Slither to perform static analysis and find security vulnerabilities.
5. **Uncommitted Changes**: Shows a warning if you have uncommitted files.

## Running Checks Locally

### Recommended: Run our Custom Script

We've created a script that runs all the CI checks locally with a nice progress indicator:

```bash
./run_ci_locally.sh
```

This script will:
- Check code formatting with a visual progress indicator
- Run the linter with a visual progress indicator
- Validate commit message format
- Show uncommitted changes in your repository
- Provide helpful recommendations if any checks fail

#### Bypassing Checks During Development

During development, you may want to skip certain checks:

```bash
# Skip Slither security checks temporarily
./run_ci_locally.sh --ignore-slither

# Or when committing, use environment variables:
SKIP_SLITHER=1 git commit -m "feat: your commit message"
SKIP_ALL=1 git commit -m "feat: skip all checks for this commit"
```

> **Note**: While these options are useful during development, all checks will run on GitHub when you push your code. Make sure to fix all issues before creating a pull request.

### Alternative: Run Individual Checks

You can also run the checks individually:

```bash
# Format check
yarn format:check

# Fix formatting issues
yarn format

# Linting check
yarn lint

# Fix linting issues
yarn lint:fix

# Test a commit message
echo "feat: your commit message" | npx commitlint
```

### Advanced: Using `act` (Not Recommended)

While it's possible to use the `act` tool to run the actual GitHub Actions workflow locally, we recommend using our custom script instead as it's faster and more reliable, especially on Apple Silicon Macs.

If you still want to use `act`, you'll need Docker installed, and you can run:

```bash
cd /Users/michael/Development/projects/strategyStCVXCRV && act -j solidity --container-architecture linux/amd64 -P ubuntu-latest=nektos/act-environments-ubuntu:18.04-full
```

Note: This method is more complex, slower, and may have issues with Docker on macOS.

## Automatic Pre-commit Checks

A pre-commit hook has been set up that automatically runs these checks before each commit. If any check fails, the commit will be prevented until you fix the issues.

## Conventional Commits Format

Commit messages must follow this format:
```
type(scope): description
```

Where:
- **type**: One of `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `ci`, `chore`, `revert`
- **scope**: (Optional) The scope of the change
- **description**: A concise description of the change

Examples:
```
feat: add new trading strategy
fix(auction): resolve error in bid processing
docs: update README with installation instructions
```

## Contact

If you have any questions or encounter issues with the CI checks, please contact the repository maintainer.
