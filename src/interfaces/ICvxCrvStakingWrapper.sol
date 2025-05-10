// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICvxCrvStakingWrapper {
    // --- ERC20 ---
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);

    // --- Metadata ---
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);

    // --- Staking/Depositing ---
    function deposit(uint256 _amount, address _to) external;
    function depositAndSetWeight(uint256 _amount, uint256 _weight) external;
    function stake(uint256 _amount, address _to) external;
    function stakeAndSetWeight(uint256 _amount, uint256 _weight) external;
    function stakeFor(address _to, uint256 _amount) external;
    function withdraw(uint256 _amount) external;

    // --- Rewards ---
    function getReward(address _account) external;
    function getReward(address _account, address _forwardTo) external;
    function earned(address _account) external view returns (EarnedData[] memory);
    function userRewardBalance(address _address, uint256 _rewardGroup) external view returns (uint256);
    function userRewardWeight(address) external view returns (uint256);
    function user_checkpoint(address _account) external returns (bool);

    // --- Reward Management ---
    function addTokenReward(address _token, uint256 _rewardGroup) external;
    function setRewardGroup(address _token, uint256 _rewardGroup) external;
    function setRewardWeight(uint256 _weight) external;
    function invalidateReward(address _token) external;
    function setHook(address _hook) external;
    function setApprovals() external;
    function rewardLength() external view returns (uint256);
    function rewardSupply(uint256 _rewardGroup) external view returns (uint256);
    function rewards(uint256) external view returns (
        address reward_token,
        uint8 reward_group,
        uint128 reward_integral,
        uint128 reward_remaining
    );
    function registeredRewards(address) external view returns (uint256);
    function rewardHook() external view returns (address);

    // --- Admin/Ownership ---
    function owner() external view returns (address);
    function transferOwnership(address newOwner) external;
    function renounceOwnership() external;
    function shutdown() external;
    function reclaim() external;

    // --- State/Info ---
    function isShutdown() external view returns (bool);
    function supplyWeight() external view returns (uint256);
    function crv() external view returns (address);
    function cvx() external view returns (address);
    function cvxCrv() external view returns (address);
    function cvxCrvStaking() external view returns (address);
    function crvDepositor() external view returns (address);
    function threeCrv() external view returns (address);
    function treasury() external view returns (address);

    // --- Structs ---
    struct EarnedData {
        address token;
        uint256 amount;
    }

    // --- Events ---
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, address indexed token, uint256 amount, address indexed receiver);
    event Deposited(address indexed user, address indexed account, uint256 amount, bool isCrv);
    event HookSet(address rewardToken);
    event IsShutdown();
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RewardGroupSet(address rewardToken, uint256 rewardGroup);
    event RewardInvalidated(address rewardToken);
}
