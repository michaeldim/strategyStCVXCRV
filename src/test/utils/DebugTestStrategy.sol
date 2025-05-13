// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {StCVXCRVStrategy} from "../../StCVXCRVStrategy.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITradeFactory} from "@periphery/interfaces/TradeFactory/ITradeFactory.sol";

contract DebugTestStrategy is StCVXCRVStrategy {
    bool public mockIsShutdown = false;

    constructor(
        address _asset,
        string memory _name
    )
        StCVXCRVStrategy(
            _asset,
            _name
        )
    {}

    function setMockShutdown(bool _isShutdown) external {
        mockIsShutdown = _isShutdown;
    }

    function testHarvest() external returns (uint256) {
        console.log("DebugTestStrategy: Starting testHarvest -> _harvestAndReport");
        return _harvestAndReport();
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        console.log("DebugTestStrategy._harvestAndReport: Entered");

        if (!mockIsShutdown) {
            console.log("DebugTestStrategy._harvestAndReport: Calling _doClaimRewardsFromWrapper");
            _doClaimRewardsFromWrapper();
        } else {
            console.log("DebugTestStrategy._harvestAndReport: mockIsShutdown is true, skipping reward claim");
        }

        console.log("DebugTestStrategy._harvestAndReport: Calling _doSellRewards");
        _doSellRewards();

        uint256 cvxCrvBal;
        try IERC20(address(asset)).balanceOf(address(this)) returns (uint256 balance) {
            cvxCrvBal = balance;
            console.log("DebugTestStrategy._harvestAndReport: CVXCRV balance in strategy =");
            console.logUint(cvxCrvBal);
        } catch {
            console.log("DebugTestStrategy._harvestAndReport: ERROR: CVXCRV.balanceOf reverted");
            cvxCrvBal = 0;
        }

        if (cvxCrvBal > 0 && !mockIsShutdown) {
            console.log("DebugTestStrategy._harvestAndReport: Attempting to transfer CVXCRV to WRAPPER and stake");
            try IERC20(address(asset)).transfer(address(WRAPPER), cvxCrvBal) returns (bool success) {
                if (success) {
                    console.log("DebugTestStrategy._harvestAndReport: CVXCRV transfer to WRAPPER succeeded");
                    try WRAPPER.stake(cvxCrvBal, address(this)) {
                        console.log("DebugTestStrategy._harvestAndReport: WRAPPER.stake succeeded");
                    } catch Error(string memory reason) {
                        console.log("DebugTestStrategy._harvestAndReport: WARNING: WRAPPER.stake failed with reason:");
                        console.log(reason);
                    } catch (bytes memory reasonBytes) {
                        console.log(
                            "DebugTestStrategy._harvestAndReport: WARNING: WRAPPER.stake failed with unknown reason (bytes):"
                        );
                        console.logBytes(reasonBytes);
                    }
                } else {
                    console.log("DebugTestStrategy._harvestAndReport: WARNING: CVXCRV transfer to WRAPPER failed");
                }
            } catch Error(string memory reason) {
                console.log(
                    "DebugTestStrategy._harvestAndReport: ERROR: CVXCRV transfer to WRAPPER reverted with reason:"
                );
                console.log(reason);
            } catch (bytes memory reasonBytes) {
                console.log(
                    "DebugTestStrategy._harvestAndReport: ERROR: CVXCRV transfer to WRAPPER reverted with unknown reason (bytes):"
                );
                console.logBytes(reasonBytes);
            }
        } else {
            console.log("DebugTestStrategy._harvestAndReport: No CVXCRV to stake or mockIsShutdown is true");
        }

        _totalAssets = IERC20(asset).balanceOf(address(this)) + WRAPPER.balanceOf(address(this));
        console.log("DebugTestStrategy._harvestAndReport: Total assets calculated =");
        console.logUint(_totalAssets);
        return _totalAssets;
    }

    function _doClaimRewardsFromWrapper() internal {
        console.log("  _doClaimRewardsFromWrapper: Attempting WRAPPER.getReward");
        try WRAPPER.getReward(address(this)) {
            console.log("  _doClaimRewardsFromWrapper: WRAPPER.getReward succeeded");
        } catch Error(string memory reason) {
            console.log("  _doClaimRewardsFromWrapper: ERROR: WRAPPER.getReward failed with reason:");
            console.log(reason);
        } catch (bytes memory reasonBytes) {
            console.log("  _doClaimRewardsFromWrapper: ERROR: WRAPPER.getReward failed with unknown reason (bytes):");
            console.logBytes(reasonBytes);
        }
    }

    function _doSellRewards() internal {
        console.log("  _doSellRewards: Entered");
        address tf = tradeFactory();
        console.log("  _doSellRewards: Trade factory address:");
        console.log(tf);

        for (uint256 i = 0; i < strategyRewardTokens.length; i++) {
            address rewardToken = strategyRewardTokens[i];
            console.log("  _doSellRewards: Checking reward token:");
            console.log(rewardToken);

            uint256 balance;
            try IERC20(rewardToken).balanceOf(address(this)) returns (uint256 bal) {
                balance = bal;
                console.log("    Balance =");
                console.logUint(balance);
            } catch {
                console.log("    ERROR: balanceOf reverted for reward token");
                balance = 0;
            }

            uint256 minSell = minAmountToSellMapping[rewardToken];
            console.log("    Min amount to sell =");
            console.logUint(minSell);

            if (balance > minSell) {
                console.log("    Balance exceeds minimum, attempting to sell.");
                if (tf != address(0)) {
                    console.log("    Using trade factory. Enabling trade.");
                    try ITradeFactory(tf).enable(rewardToken, address(asset)) {
                        console.log("    ITradeFactory.enable succeeded.");
                    } catch Error(string memory reason) {
                        console.log("    ERROR: ITradeFactory.enable failed with reason:");
                        console.log(reason);
                    } catch (bytes memory reasonBytes) {
                        console.log("    ERROR: ITradeFactory.enable failed with unknown reason (bytes):");
                        console.logBytes(reasonBytes);
                    }
                } else {
                    console.log("    No selling mechanism (trade factory) is enabled or configured.");
                }
            } else {
                console.log("    Balance does not exceed minimum, no selling.");
            }
        }
        console.log("  _doSellRewards: Finished processing reward tokens.");
    }
}
