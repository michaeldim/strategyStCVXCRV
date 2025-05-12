My notes:

So we currently have built a yearn tokenised strategy that deploys capital into the stkCVXCRVWrapper and it harvest rewards from that (CRV/CVX/CRVUSD) back into more CVXCRV using tradeFactory.

We have built tests that pass.

**Test Cleanup (May 12, 2023):**
- Fixed ForkedTest.t.sol to work properly with mock TradeFactory and AccessControl
- Added comprehensive testing of wrapper rewards between staking and harvesting
- Removed SimplifiedForkedTest.t.sol as it's no longer needed after fixing ForkedTest.t.sol
- Removed ForkedTest.md documentation file as the issues have been fixed
- Fixed all compiler warnings across the test suite
- Removed redundant test files and .bak backup files

Currently there are issues with github Actions not passing:

Once we have then passed we need to start looking at deploying the strategy, firstly on tenderly using https://tenderly.co/virtual-testnets. using exact replica of the mainnet. I dont know how we are going to get the swaps to work because we wont be mocking them on this? also harvesting we might have to allocate ourselves to do. We need to deploy a vault via https://kalani.yearn.farm/. I dont know if we need to create a new project first, we already have one called Yieldoor but that name is used by another defi protocol and i dont want there to be a confusion. We can't rename the project so we might need to create a new project, deploy a vault and then we can add this strategy to that vault. I would like appropriate names for both the vault and the strategy. I like how yearn uses yvDAI-1, yvDAI-2 to reflect a new vault. then the vault has multiple strategies like stratergy name: Morpho Gauntlet DAI Core Compounder, symbol: ysDAI / name: Morpho Y-DAI Compounder, symbol: ysDAI / name : StrategyGearboxLenderDAI, symbol: ysDAI.

another vault for crvusd has name of crvUSD-2 yVault symbol: yvcrvUSD-2 and then the strategies: name:: Aave V3 crvUSD Lender, symbol: yscrvUSD or name: Sturdy crvUSD Compounder, symbol: yscrvUSD...

on the kalami UI they recommend given an underlying asset such as cvxCRV to have that followed by the project for the vault:

so if i had a project called Yieldoor. it would be named: cvxCRV Yieldoor and the symbol would be: ycvxCRV.

I want the project to be called something else. Because it relates to curve finance and there are linked to llamas we need to create a unique name for the project. i do like the idea of just calling it cvxCRV yVault or cvxCRV-1 yVault. for the strategy name maybe: cvxCRV Compounder or Staked cvxCRX Compounder or st-cvxCRV Compounder or just StrategyStCVXCRV

with the tenderly testnets because it will always mimic the mainnet we can then deploy the one way lending contracts:

CryptoFromPoolsRate.vy with our vault on top top as the price oracle:

interface IMulti { def price() -> uint256: view }
interface IVault { def pricePerShare() -> uint256: view }

contract VaultPlusPools {
IMulti public multi; # cvxCRV→CRV→crvUSD pool EMA
IVault public vault; # locked-profit ERC-4626 compounder

    constructor(address _multi, address _vault) {
        multi = IMulti(_multi);
        vault = IVault(_vault);
    }
    @view
    def price() -> uint256:
        # multi.price() is crvUSD per cvxCRV
        # vault.pricePerShare() is cvxCRV per 1 vault-share
        return multi.price() * vault.pricePerShare() / 1e18
    }

} as CryptoFromPoolsRate.vy doesn't use a erc4626.

in CryptoFromPoolsRate.vy we will use two curve pools. cvxcrv/crv and the tricrypto pool.

once we have our one way lending contracts deployed: https://docs.curve.fi/lending/contracts/oneway-factory/#create we need to be able set a % of the strategy fee to a gauge that encourages lending on the one way lending market: https://resources.curve.fi/reward-gauges/permissionless-rewards/

i would also like a simple front end using viem to interact with a vault and simulate deposits on this virtual testnet.

once we are happy with the tenderly simulations/forking env we can then deploy our mainnet script.

when we do test deployments on tenderly we also need to deploy the oracle and make sure that matches real apr/apys from convex, they use defillama api for pricing.

i would also like a front end being to give us the oracle price from our one way lending market.

just to summarise;

1.) deploy strategy via tenderly add to existing vault
2.) deploy a price oracle for one way lending market to use (using our vault)
3.) deploy the one way lending market, limit deposits and ltv to 30% initially.
4.) add gauge to the lending market / setup rewards ()
5.) set the strategy up to send a percentage of fees to the gauge of the lending market (5% initially). rewards will be cvxCRV
6.) run through tests of both the strategy/vault and lending market/ price oracles and aprOracles.
