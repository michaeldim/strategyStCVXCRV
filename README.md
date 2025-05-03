# Yearn Finance - strategyStCVXCRV

This repository implements a Yearn Finance Ethereum strategy called strategyStCVXCRV, which stakes cvxCRV tokens in a Convex Finance wrapper to earn additional rewards.

## Overview

The strategy works by:
1. Accepting cvxCRV token deposits
2. Staking those tokens in a Convex Finance staking wrapper
3. Periodically harvesting rewards
4. Converting rewards back to cvxCRV to compound returns

# Tokenized Strategy Mix for Yearn V3 strategies

This repo will allow you to write, test and deploy V3 "Tokenized Strategies" using [Foundry](https://book.getfoundry.sh/).

You will only need to override the three functions in Strategy.sol of `_deployFunds`, `_freeFunds` and `_harvestAndReport`. With the option to also override `_tend`, `_tendTrigger`, `availableDepositLimit`, `availableWithdrawLimit` and `_emergencyWithdraw` if desired.

For a more complete overview of how the Tokenized Strategies work please visit the [TokenizedStrategy Repo](https://github.com/yearn/tokenized-strategy).

## How to start

### Requirements

- First you will need to install [Foundry](https://book.getfoundry.sh/getting-started/installation).
NOTE: If you are on a windows machine it is recommended to use [WSL](https://learn.microsoft.com/en-us/windows/wsl/install)
- Install [Node.js](https://nodejs.org/en/download/package-manager/)

### Clone this repository

```sh
git clone --recursive https://github.com/yearn/tokenized-strategy-foundry-mix

cd tokenized-strategy-foundry-mix

yarn
```

### Set your environment Variables

Use the `.env.example` template to create a `.env` file and store the environement variables. You will need to populate the `RPC_URL` for the desired network(s). RPC url can be obtained from various providers, including [Ankr](https://www.ankr.com/rpc/) (no sign-up required) and [Infura](https://infura.io/).

Use .env file

1. Make a copy of `.env.example`
2. Add the value for `ETH_RPC_URL` and other example vars
     NOTE: If you set up a global environment variable, that will take precedence.

### Build the project

```sh
make build
```

Run tests

```sh
make test
```

## Strategy Writing

For a complete guide to creating a Tokenized Strategy please visit: [How to build a Tokenized Strategy](https://docs.yearn.fi/developers/v3/strategy_development).

The 3 main functions that you are required to override are outlined below.

#### `_deployFunds(uint256 _amount)`

This function will attempt to deploy up to `_amount` of `asset`.

This can be done by depositing into a protocol, opening a position, staking in a gauge, etc.

#### `_freeFunds(uint256 _amount)`

This function will attempt to free up to `_amount` of `asset`.

This can be done by withdrawing from a protocol, closing a position, unstaking from a gauge, etc.

#### `_harvestAndReport()`

This function will do any needed harvesting, rewards selling, accrual, etc. and then return a `_totalAssets` amount denominated in `asset` that includes all `asset` the strategy holds, and any realized profits. If the strategy has taken any losses this report cycle realized losses can be reported by setting `_loss` and `_debtPayment`.

### Optional Functions

#### `_tend`

This function will be called during a `tend` call and can be used if a strategy needs to perform any maintenance or rebalancing. This can be done by depositing/withdrawing from a protocol, opening/closing a position, staking/unstaking from a gauge, etc.

## Testing

Due to the nature of the BaseStrategy utilizing an external release registry, the default way to test strategies is to use a mocked release registry where you are the owner and can add strategies and endorsers to it. 

You can do this by using the default functions such as `setUpStrategy()` within the `Setup` contract to create your own strategy, management, deployment etc. 

To make any assertions or write specific tests against the strategy you can simply inherit the `Setup` contract and begin writing your tests with forge.

See the `Operation.t.sol` for a guide.

### Deployment

#### Contract Verification

Once the Strategy is fully deployed and verified, you will need to verify the TokenizedStrategy functions. To do this, navigate to the /#code page on Etherscan.

1. Click on the `More Options` drop-down menu
2. Click "is this a proxy?"
3. Click the "Verify" button
4. Click "Save"

This should add all of the external `TokenizedStrategy` functions to the contract interface on Etherscan.

### CI/CD

This repo uses [GitHub Actions](.github/workflows) for CI/CD workflows.