// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.23;

/**
 * @title IConvexBasicRewards
 * @notice Interface for Convex rewards contracts
 */
interface IConvexBasicRewards {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function earned(address account) external view returns (uint256);
    function getReward() external returns (bool);
    function getReward(address _account, bool _claimExtras) external returns (bool);
    function extraRewardsLength() external view returns (uint256);
    function extraRewards(uint256 _pid) external view returns (address);
    function rewardToken() external view returns (address);
    function periodFinish() external view returns (uint256);
    function rewardRate() external view returns (uint256);
    function lastTimeRewardApplicable() external view returns (uint256);
    function rewardPerToken() external view returns (uint256);
    function rewardPerTokenStored() external view returns (uint256);
    function userRewardPerTokenPaid(address account) external view returns (uint256);
    function rewards(address account) external view returns (uint256);
}
