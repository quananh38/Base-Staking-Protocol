# base-staking-protocol/contracts/StakingProtocol.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract StakingProtocol is Ownable {
    struct Staker {
        uint256 amountStaked;
        uint256 rewardDebt;
        uint256 lastRewardTime;
        bool isStaking;
    }
    
    struct Pool {
        IERC20 token;
        uint256 totalStaked;
        uint256 rewardPerSecond;
        uint256 lastUpdateTime;
        uint256 accRewardPerShare;
        uint256 poolStartTime;
        uint256 poolEndTime;
    }
    
    mapping(address => Staker) public stakers;
    mapping(address => uint256) public userRewards;
    mapping(address => uint256) public pendingRewards;
    
    Pool public pool;
    uint256 public constant REWARD_PRECISION = 1e18;
    
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);
    
    constructor(
        address _token,
        uint256 _rewardPerSecond,
        uint256 _startTime,
        uint256 _endTime
    ) {
        pool.token = IERC20(_token);
        pool.rewardPerSecond = _rewardPerSecond;
        pool.poolStartTime = _startTime;
        pool.poolEndTime = _endTime;
        pool.lastUpdateTime = _startTime;
    }
    
    function stake(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        require(block.timestamp >= pool.poolStartTime, "Pool not started");
        require(block.timestamp <= pool.poolEndTime, "Pool ended");
        require(pool.token.balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        updatePool();
        updateUserRewards(msg.sender);
        
        pool.token.transferFrom(msg.sender, address(this), amount);
        stakers[msg.sender].amountStaked += amount;
        stakers[msg.sender].lastRewardTime = block.timestamp;
        stakers[msg.sender].isStaking = true;
        pool.totalStaked += amount;
        
        emit Staked(msg.sender, amount);
    }
    
    function unstake(uint256 amount) external {
        require(stakers[msg.sender].amountStaked >= amount, "Insufficient staked amount");
        
        updatePool();
        updateUserRewards(msg.sender);
        
        stakers[msg.sender].amountStaked -= amount;
        pool.totalStaked -= amount;
        pool.token.transfer(msg.sender, amount);
        
        if (stakers[msg.sender].amountStaked == 0) {
            stakers[msg.sender].isStaking = false;
        }
        
        emit Unstaked(msg.sender, amount);
    }
    
    function claimReward() external {
        updatePool();
        updateUserRewards(msg.sender);
        
        uint256 reward = userRewards[msg.sender];
        require(reward > 0, "No rewards to claim");
        
        userRewards[msg.sender] = 0;
        pool.token.transfer(msg.sender, reward);
        
        emit RewardClaimed(msg.sender, reward);
    }
    
    function updatePool() internal {
        if (block.timestamp <= pool.lastUpdateTime) return;
        
        uint256 timePassed = block.timestamp - pool.lastUpdateTime;
        uint256 rewards = timePassed * pool.rewardPerSecond;
        
        if (pool.totalStaked > 0) {
            pool.accRewardPerShare += (rewards * REWARD_PRECISION) / pool.totalStaked;
        }
        
        pool.lastUpdateTime = block.timestamp;
    }
    
    function updateUserRewards(address user) internal {
        if (stakers[user].amountStaked > 0) {
            uint256 pending = (stakers[user].amountStaked * pool.accRewardPerShare) / REWARD_PRECISION;
            userRewards[user] += pending - stakers[user].rewardDebt;
            stakers[user].rewardDebt = pending;
        }
    }
    
    function getPendingReward(address user) external view returns (uint256) {
        if (stakers[user].amountStaked == 0) return 0;
        
        uint256 accRewardPerShare = pool.accRewardPerShare;
        if (block.timestamp > pool.lastUpdateTime && pool.totalStaked != 0) {
            uint256 timePassed = block.timestamp - pool.lastUpdateTime;
            uint256 rewards = timePassed * pool.rewardPerSecond;
            accRewardPerShare += (rewards * REWARD_PRECISION) / pool.totalStaked;
        }
        
        uint256 pending = (stakers[user].amountStaked * accRewardPerShare) / REWARD_PRECISION;
        return pending - stakers[user].rewardDebt;
    }
}
