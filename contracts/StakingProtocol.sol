// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract StakingProtocolV2 is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    struct Staker {
        uint256 amountStaked;
        uint256 rewardDebt;
        uint256 lastRewardTime;
        bool isStaking;
        uint256[] stakingHistory;
        uint256 totalRewardsReceived;
        uint256 firstStakeTime;
        uint256 lastClaimTime;
        uint256 pendingRewards;
    }

    struct Pool {
        IERC20 token;
        uint256 totalStaked;
        uint256 rewardPerSecond;
        uint256 lastUpdateTime;
        uint256 accRewardPerShare;
        uint256 poolStartTime;
        uint256 poolEndTime;
        bool isActive;
        uint256 apr;
        uint256 minimumStake;
        uint256 maximumStake;
        uint256 lockupPeriod;
        uint256 performanceFee;
        uint256 withdrawalFee;
    }

    struct RewardTier {
        uint256 minStake;
        uint256 multiplier;
        string tierName;
    }

    struct UserStakeInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 lastUpdateTime;
        uint256[] stakingHistory;
        uint256 totalRewardsReceived;
        uint256 firstStakeTime;
        uint256 lastClaimTime;
        uint256 pendingRewards;
    }

    mapping(address => Staker) public stakers;
    mapping(address => Pool) public pools;
    mapping(address => RewardTier[]) public rewardTiers;
    
    IERC20 public rewardToken;
    uint256 public constant REWARD_PRECISION = 1e18;
    uint256 public constant MAX_LOCKUP_PERIOD = 365 days;
    uint256 public constant MAX_PERFORMANCE_FEE = 1000; // 10%
    uint256 public constant MAX_WITHDRAWAL_FEE = 1000; // 10%
    uint256 public constant MIN_STAKE_AMOUNT = 1;
    
    // Events
    event Staked(
        address indexed user,
        address indexed pool,
        uint256 amount,
        uint256 sharesMinted,
        uint256 timestamp
    );
    
    event Unstaked(
        address indexed user,
        address indexed pool,
        uint256 amount,
        uint256 sharesBurned,
        uint256 timestamp
    );
    
    event RewardClaimed(
        address indexed user,
        address indexed pool,
        uint256 rewardAmount,
        uint256 timestamp
    );
    
    event PoolCreated(
        address indexed pool,
        address indexed token,
        uint256 rewardPerSecond,
        uint256 startTime,
        uint256 endTime,
        uint256 apr,
        uint256 minimumStake,
        uint256 maximumStake
    );
    
    event PoolUpdated(
        address indexed pool,
        uint256 rewardPerSecond,
        uint256 apr,
        uint256 minimumStake,
        uint256 maximumStake
    );
    
    event RewardTierAdded(
        address indexed pool,
        uint256 minStake,
        uint256 multiplier,
        string tierName
    );
    
    event FeeUpdated(
        address indexed pool,
        uint256 performanceFee,
        uint256 withdrawalFee
    );
    
    event LockupPeriodUpdated(
        address indexed pool,
        uint256 newPeriod
    );
    
    event PoolActivated(address indexed pool);
    event PoolDeactivated(address indexed pool);

    constructor(
        address _rewardToken
    ) {
        rewardToken = IERC20(_rewardToken);
    }

    // Create pool
    function createPool(
        address token,
        uint256 rewardPerSecond,
        uint256 startTime,
        uint256 endTime,
        uint256 apr,
        uint256 minimumStake,
        uint256 maximumStake
    ) external onlyOwner {
        require(token != address(0), "Invalid token");
        require(startTime > block.timestamp, "Invalid start time");
        require(endTime > startTime, "Invalid end time");
        require(apr <= 1000000, "APR too high"); // 10000% max APR
        require(minimumStake >= MIN_STAKE_AMOUNT, "Minimum stake too low");
        require(maximumStake >= minimumStake, "Invalid stake limits");
        
        pools[token] = Pool({
            token: IERC20(token),
            totalStaked: 0,
            rewardPerSecond: rewardPerSecond,
            lastUpdateTime: startTime,
            accRewardPerShare: 0,
            poolStartTime: startTime,
            poolEndTime: endTime,
            isActive: true,
            apr: apr,
            minimumStake: minimumStake,
            maximumStake: maximumStake,
            lockupPeriod: 0,
            performanceFee: 0,
            withdrawalFee: 0
        });
        
        emit PoolCreated(
            token,
            token,
            rewardPerSecond,
            startTime,
            endTime,
            apr,
            minimumStake,
            maximumStake
        );
    }

    // Update pool
    function updatePool(
        address token,
        uint256 rewardPerSecond,
        uint256 apr,
        uint256 minimumStake,
        uint256 maximumStake
    ) external onlyOwner {
        Pool storage pool = pools[token];
        require(pool.token != address(0), "Pool does not exist");
        require(apr <= 1000000, "APR too high");
        require(minimumStake >= MIN_STAKE_AMOUNT, "Minimum stake too low");
        require(maximumStake >= minimumStake, "Invalid stake limits");
        
        pool.rewardPerSecond = rewardPerSecond;
        pool.apr = apr;
        pool.minimumStake = minimumStake;
        pool.maximumStake = maximumStake;
        
        emit PoolUpdated(token, rewardPerSecond, apr, minimumStake, maximumStake);
    }

    // Add reward tier
    function addRewardTier(
        address pool,
        uint256 minStake,
        uint256 multiplier,
        string memory tierName
    ) external onlyOwner {
        require(pools[pool].token != address(0), "Pool does not exist");
        require(multiplier >= 1e18, "Multiplier too low");
        
        rewardTiers[pool].push(RewardTier({
            minStake: minStake,
            multiplier: multiplier,
            tierName: tierName
        }));
        
        emit RewardTierAdded(pool, minStake, multiplier, tierName);
    }

    // Set fees
    function setFees(
        address pool,
        uint256 performanceFee,
        uint256 withdrawalFee
    ) external onlyOwner {
        require(pools[pool].token != address(0), "Pool does not exist");
        require(performanceFee <= MAX_PERFORMANCE_FEE, "Performance fee too high");
        require(withdrawalFee <= MAX_WITHDRAWAL_FEE, "Withdrawal fee too high");
        
        pools[pool].performanceFee = performanceFee;
        pools[pool].withdrawalFee = withdrawalFee;
        
        emit FeeUpdated(pool, performanceFee, withdrawalFee);
    }

    // Set lockup period
    function setLockupPeriod(
        address pool,
        uint256 lockupPeriod
    ) external onlyOwner {
        require(pools[pool].token != address(0), "Pool does not exist");
        require(lockupPeriod <= MAX_LOCKUP_PERIOD, "Lockup period too long");
        
        pools[pool].lockupPeriod = lockupPeriod;
        emit LockupPeriodUpdated(pool, lockupPeriod);
    }

    // Stake
    function stake(
        address pool,
        uint256 amount
    ) external nonReentrant {
        Pool storage poolInfo = pools[pool];
        require(poolInfo.token != address(0), "Pool does not exist");
        require(poolInfo.isActive, "Pool not active");
        require(block.timestamp >= poolInfo.poolStartTime, "Pool not started");
        require(block.timestamp <= poolInfo.poolEndTime, "Pool ended");
        require(amount >= poolInfo.minimumStake, "Amount below minimum");
        require(amount <= poolInfo.maximumStake, "Amount above maximum");
        require(poolInfo.token.balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        updatePool(pool);
        Staker storage staker = stakers[msg.sender];
        
        if (staker.amountStaked > 0) {
            uint256 pending = calculatePendingReward(msg.sender, pool);
            if (pending > 0) {
                staker.pendingRewards = staker.pendingRewards.add(pending);
            }
        }
        
        staker.amountStaked = staker.amountStaked.add(amount);
        staker.lastRewardTime = block.timestamp;
        staker.isStaking = true;
        
        if (staker.firstStakeTime == 0) {
            staker.firstStakeTime = block.timestamp;
        }
        
        poolInfo.totalStaked = poolInfo.totalStaked.add(amount);
        poolInfo.token.transferFrom(msg.sender, address(this), amount);
        
        // Add to history
        staker.stakingHistory.push(amount);
        
        emit Staked(msg.sender, pool, amount, amount, block.timestamp);
    }

    // Unstake
    function unstake(
        address pool,
        uint256 amount
    ) external nonReentrant {
        Pool storage poolInfo = pools[pool];
        require(poolInfo.token != address(0), "Pool does not exist");
        require(poolInfo.isActive, "Pool not active");
        require(stakers[msg.sender].amountStaked >= amount, "Insufficient stake");
        
        updatePool(pool);
        Staker storage staker = stakers[msg.sender];
        
        uint256 pending = calculatePendingReward(msg.sender, pool);
        if (pending > 0) {
            staker.pendingRewards = staker.pendingRewards.add(pending);
        }
        
        // Check lockup period
        uint256 feeAmount = 0;
        if (block.timestamp < staker.firstStakeTime.add(poolInfo.lockupPeriod)) {
            feeAmount = amount.mul(poolInfo.withdrawalFee).div(10000);
        }
        
        uint256 amountAfterFee = amount.sub(feeAmount);
        
        staker.amountStaked = staker.amountStaked.sub(amountAfterFee);
        poolInfo.totalStaked = poolInfo.totalStaked.sub(amountAfterFee);
        
        // Apply fee
        if (feeAmount > 0) {
            poolInfo.token.transfer(owner(), feeAmount);
        }
        
        poolInfo.token.transfer(msg.sender, amountAfterFee);
        staker.lastUpdateTime = block.timestamp;
        
        emit Unstaked(msg.sender, pool, amountAfterFee, amountAfterFee, block.timestamp);
    }

    // Claim reward
    function claimReward(
        address pool
    ) external nonReentrant {
        Pool storage poolInfo = pools[pool];
        require(poolInfo.token != address(0), "Pool does not exist");
        require(poolInfo.isActive, "Pool not active");
        
        updatePool(pool);
        Staker storage staker = stakers[msg.sender];
        
        uint256 pending = calculatePendingReward(msg.sender, pool);
        require(pending > 0, "No rewards to claim");
        
        // Apply performance fee
        uint256 performanceFeeAmount = pending.mul(poolInfo.performanceFee).div(10000);
        uint256 amountAfterFee = pending.sub(performanceFeeAmount);
        
        if (performanceFeeAmount > 0) {
            rewardToken.transfer(owner(), performanceFeeAmount);
        }
        
        // Transfer rewards
        rewardToken.transfer(msg.sender, amountAfterFee);
        
        // Update stats
        staker.rewardDebt = staker.rewardDebt.add(amountAfterFee);
        staker.totalRewardsReceived = staker.totalRewardsReceived.add(amountAfterFee);
        staker.lastClaimTime = block.timestamp;
        staker.pendingRewards = staker.pendingRewards.sub(amountAfterFee);
        
        emit RewardClaimed(msg.sender, pool, amountAfterFee, block.timestamp);
    }

    // Update pool
    function updatePool(address pool) internal {
        Pool storage poolInfo = pools[pool];
        if (block.timestamp <= poolInfo.lastUpdateTime) return;
        
        uint256 timePassed = block.timestamp.sub(poolInfo.lastUpdateTime);
        uint256 rewards = timePassed.mul(poolInfo.rewardPerSecond);
        
        if (poolInfo.totalStaked > 0) {
            poolInfo.accRewardPerShare = poolInfo.accRewardPerShare.add(
                rewards.mul(REWARD_PRECISION).div(poolInfo.totalStaked)
            );
        }
        
        poolInfo.lastUpdateTime = block.timestamp;
    }

    // Calculate pending reward
    function calculatePendingReward(address user, address pool) public view returns (uint256) {
        Pool storage poolInfo = pools[pool];
        Staker storage staker = stakers[user];
        
        uint256 rewardPerToken = poolInfo.accRewardPerShare;
        uint256 userReward = staker.rewardDebt;
        
        if (staker.amountStaked > 0) {
            uint256 userEarned = staker.amountStaked.mul(rewardPerToken.sub(userReward)).div(REWARD_PRECISION);
            return userEarned;
        }
        return 0;
    }

    // Get pool info
    function getPoolInfo(address pool) external view returns (Pool memory) {
        return pools[pool];
    }

    // Get user info
    function getUserInfo(address user) external view returns (Staker memory) {
        return stakers[user];
    }

    // Get reward info
    function getUserRewardInfo(address user, address pool) external view returns (
        uint256 pendingRewards,
        uint256 totalRewardsReceived,
        uint256 estimatedAPR
    ) {
        Staker storage staker = stakers[user];
        Pool storage poolInfo = pools[pool];
        
        uint256 pending = calculatePendingReward(user, pool);
        uint256 totalRewards = staker.totalRewardsReceived;
        uint256 apr = poolInfo.apr;
        
        return (pending, totalRewards, apr);
    }

    // Get reward tiers
    function getRewardTiers(address pool) external view returns (RewardTier[] memory) {
        return rewardTiers[pool];
    }

    // Get pool stats
    function getPoolStats(address pool) external view returns (
        uint256 totalStaked,
        uint256 totalRewards,
        uint256 apr,
        uint256 activeUsers
    ) {
        Pool storage poolInfo = pools[pool];
        uint256 activeUsersCount = 0;
        
        // Count active users (simplified)
        // In real implementation, you'd have a mapping or other structure
        
        return (
            poolInfo.totalStaked,
            0, // totalRewards
            poolInfo.apr,
            activeUsersCount
        );
    }

    // Activate pool
    function activatePool(address pool) external onlyOwner {
        Pool storage poolInfo = pools[pool];
        require(poolInfo.token != address(0), "Pool does not exist");
        poolInfo.isActive = true;
        emit PoolActivated(pool);
    }

    // Deactivate pool
    function deactivatePool(address pool) external onlyOwner {
        Pool storage poolInfo = pools[pool];
        require(poolInfo.token != address(0), "Pool does not exist");
        poolInfo.isActive = false;
        emit PoolDeactivated(pool);
    }

    // Get user staking history
    function getUserStakingHistory(address user) external view returns (uint256[] memory) {
        return stakers[user].stakingHistory;
    }

    // Get total stakers
    function getTotalStakers() external view returns (uint256) {
        // Implementation in future
        return 0;
    }

    // Check if can claim reward
    function canClaimReward(address user, address pool) external view returns (bool) {
        Pool storage poolInfo = pools[pool];
        Staker storage staker = stakers[user];
        if (poolInfo.token == address(0) || !poolInfo.isActive) return false;
        if (staker.amountStaked == 0) return false;
        return true;
    }

    // Get effective reward rate
    function getEffectiveRewardRate(address pool) external view returns (uint256) {
        Pool storage poolInfo = pools[pool];
        return poolInfo.rewardPerSecond;
    }

    // Get staking info
    function getStakingInfo(address user, address pool) external view returns (
        uint256 amountStaked,
        uint256 pendingRewards,
        uint256 totalRewardsReceived,
        uint256 firstStakeTime,
        uint256 lastClaimTime
    ) {
        Staker storage staker = stakers[user];
        return (
            staker.amountStaked,
            staker.pendingRewards,
            staker.totalRewardsReceived,
            staker.firstStakeTime,
            staker.lastClaimTime
        );
    }
    // Добавить структуры:
struct TokenType {
    string name;
    uint256 riskLevel;
    uint256 rewardMultiplier;
    uint256 maxStake;
    uint256 minStake;
    bool enabled;
    uint256 lockupPeriod;
    uint256 performanceFee;
    uint256 withdrawalFee;
    string description;
}

struct UserTokenType {
    address user;
    string tokenType;
    uint256 assignedTime;
    uint256 expirationTime;
    bool active;
}

// Добавить маппинги:
mapping(string => TokenType) public tokenTypes;
mapping(address => UserTokenType) public userTokenTypes;

// Добавить события:
event TokenTypeCreated(
    string indexed tokenType,
    uint256 riskLevel,
    uint256 rewardMultiplier,
    string description
);

event TokenTypeUpdated(
    string indexed tokenType,
    uint256 riskLevel,
    uint256 rewardMultiplier
);

event UserTokenTypeAssigned(
    address indexed user,
    string indexed tokenType,
    uint256 assignedTime
);

event TokenTypeRemoved(
    string indexed tokenType
);

// Добавить функции:
function createTokenType(
    string memory tokenTypeName,
    uint256 riskLevel,
    uint256 rewardMultiplier,
    uint256 maxStake,
    uint256 minStake,
    uint256 lockupPeriod,
    uint256 performanceFee,
    uint256 withdrawalFee,
    string memory description
) external onlyOwner {
    require(bytes(tokenTypeName).length > 0, "Token type name cannot be empty");
    require(riskLevel <= 10000, "Risk level too high");
    require(rewardMultiplier <= 10000, "Reward multiplier too high");
    require(maxStake >= minStake, "Invalid stake limits");
    
    tokenTypes[tokenTypeName] = TokenType({
        name: tokenTypeName,
        riskLevel: riskLevel,
        rewardMultiplier: rewardMultiplier,
        maxStake: maxStake,
        minStake: minStake,
        enabled: true,
        lockupPeriod: lockupPeriod,
        performanceFee: performanceFee,
        withdrawalFee: withdrawalFee,
        description: description
    });
    
    emit TokenTypeCreated(tokenTypeName, riskLevel, rewardMultiplier, description);
}

function updateTokenType(
    string memory tokenTypeName,
    uint256 riskLevel,
    uint256 rewardMultiplier,
    uint256 maxStake,
    uint256 minStake,
    uint256 lockupPeriod,
    uint256 performanceFee,
    uint256 withdrawalFee
) external onlyOwner {
    require(tokenTypes[tokenTypeName].name.length > 0, "Token type not found");
    require(riskLevel <= 10000, "Risk level too high");
    require(rewardMultiplier <= 10000, "Reward multiplier too high");
    require(maxStake >= minStake, "Invalid stake limits");
    
    TokenType storage tokenType = tokenTypes[tokenTypeName];
    tokenType.riskLevel = riskLevel;
    tokenType.rewardMultiplier = rewardMultiplier;
    tokenType.maxStake = maxStake;
    tokenType.minStake = minStake;
    tokenType.lockupPeriod = lockupPeriod;
    tokenType.performanceFee = performanceFee;
    tokenType.withdrawalFee = withdrawalFee;
    
    emit TokenTypeUpdated(tokenTypeName, riskLevel, rewardMultiplier);
}

function assignUserTokenType(
    address user,
    string memory tokenTypeName,
    uint256 duration
) external onlyOwner {
    require(tokenTypes[tokenTypeName].name.length > 0, "Token type not found");
    require(tokenTypes[tokenTypeName].enabled, "Token type not enabled");
    
    UserTokenType storage userToken = userTokenTypes[user];
    userToken.user = user;
    userToken.tokenType = tokenTypeName;
    userToken.assignedTime = block.timestamp;
    userToken.expirationTime = block.timestamp + duration;
    userToken.active = true;
    
    emit UserTokenTypeAssigned(user, tokenTypeName, block.timestamp);
}

function removeUserTokenType(address user) external {
    require(userTokenTypes[user].user == user, "No token type assigned");
    
    UserTokenType storage userToken = userTokenTypes[user];
    userToken.active = false;
    
    emit UserTokenTypeAssigned(user, userToken.tokenType, block.timestamp);
}

function getTokenTypeInfo(string memory tokenTypeName) external view returns (TokenType memory) {
    return tokenTypes[tokenTypeName];
}

function getUserTokenType(address user) external view returns (UserTokenType memory) {
    return userTokenTypes[user];
}

function getActiveTokenTypes() external view returns (string[] memory) {
    // Implementation would return all active token types
    return new string[](0);
}

function validateUserTokenType(address user, string memory tokenTypeName) external view returns (bool) {
    UserTokenType storage userToken = userTokenTypes[user];
    TokenType storage tokenType = tokenTypes[tokenTypeName];
    
    if (!userToken.active || !tokenType.enabled) {
        return false;
    }
    
    if (block.timestamp > userToken.expirationTime) {
        return false;
    }
    
    return keccak256(abi.encodePacked(userToken.tokenType)) == keccak256(abi.encodePacked(tokenTypeName));
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract StakingProtocol is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    // Существующие структуры и функции...
    
    // Новые структуры для NFT-базированного стейкинга
    struct NFTStake {
        uint256 tokenId;
        address staker;
        address nftContract;
        uint256 stakeTime;
        uint256 stakingDuration;
        bool isStaked;
        uint256 rewardMultiplier;
        uint256 stakingPower;
        uint256 lastRewardTime;
        uint256 totalRewardsEarned;
        uint256 firstStakeTime;
        uint256 lastClaimTime;
        uint256 pendingRewards;
        uint256[] stakingHistory;
        string nftType;
        uint256 nftRarity;
        uint256 lockupPeriod;
        uint256 performanceFee;
        uint256 withdrawalFee;
        uint256 rewardDebt;
    }
    
    struct NFTStakingTier {
        string tierName;
        uint256 minStakingPower;
        uint256 maxStakingPower;
        uint256 rewardMultiplier;
        uint256 lockupPeriod;
        uint256 performanceFee;
        uint256 withdrawalFee;
        bool enabled;
        uint256 maxStakers;
        uint256 currentStakers;
        uint256 maxStakeAmount;
        uint256 minStakeAmount;
    }
    
    struct NFTStakingConfig {
        address nftContract;
        uint256 defaultRewardMultiplier;
        uint256 defaultLockupPeriod;
        uint256 defaultPerformanceFee;
        uint256 defaultWithdrawalFee;
        bool enabled;
        uint256 maxStakers;
        uint256 lastUpdateTime;
    }
    
    struct NFTStakingStats {
        uint256 totalStakedNFTs;
        uint256 totalStakers;
        uint256 totalRewardsDistributed;
        uint256 averageStakingPower;
        uint256 totalValueLocked;
        uint256 stakingDuration;
        uint256 successRate;
    }
    
    // Новые маппинги
    mapping(address => mapping(uint256 => NFTStake)) public nftStakes;
    mapping(address => NFTStakingTier) public nftStakingTiers;
    mapping(address => NFTStakingConfig) public nftStakingConfigs;
    mapping(address => mapping(uint256 => uint256[])) public userNFTStakes;
    mapping(address => NFTStakingStats) public nftStakingStats;
    
    // Новые события
    event NFTStaked(
        address indexed staker,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 stakingPower,
        uint256 rewardMultiplier,
        uint256 stakingDuration,
        uint256 timestamp
    );
    
    event NFTUnstaked(
        address indexed staker,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 rewards,
        uint256 timestamp
    );
    
    event NFTStakingTierCreated(
        string indexed tierName,
        uint256 minStakingPower,
        uint256 maxStakingPower,
        uint256 rewardMultiplier,
        uint256 lockupPeriod,
        uint256 performanceFee,
        uint256 withdrawalFee
    );
    
    event NFTStakingConfigUpdated(
        address indexed nftContract,
        uint256 defaultRewardMultiplier,
        uint256 defaultLockupPeriod,
        uint256 defaultPerformanceFee,
        uint256 defaultWithdrawalFee,
        bool enabled
    );
    
    event NFTStakingTierUpdated(
        string indexed tierName,
        uint256 minStakingPower,
        uint256 maxStakingPower,
        uint256 rewardMultiplier,
        uint256 lockupPeriod,
        uint256 performanceFee,
        uint256 withdrawalFee
    );
    
    event NFTStakingRewardsClaimed(
        address indexed staker,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 rewards,
        uint256 timestamp
    );
    
    event NFTStakingPowerUpdated(
        address indexed staker,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 oldPower,
        uint256 newPower,
        uint256 timestamp
    );
    
    // Новые функции для NFT-базированного стейкинга
    function createNFTStakingTier(
        string memory tierName,
        uint256 minStakingPower,
        uint256 maxStakingPower,
        uint256 rewardMultiplier,
        uint256 lockupPeriod,
        uint256 performanceFee,
        uint256 withdrawalFee,
        uint256 maxStakers,
        uint256 maxStakeAmount,
        uint256 minStakeAmount
    ) external onlyOwner {
        require(bytes(tierName).length > 0, "Tier name cannot be empty");
        require(minStakingPower <= maxStakingPower, "Invalid staking power range");
        require(rewardMultiplier >= 1000, "Reward multiplier too low");
        require(lockupPeriod > 0, "Lockup period must be greater than 0");
        require(performanceFee <= 10000, "Performance fee too high");
        require(withdrawalFee <= 10000, "Withdrawal fee too high");
        require(maxStakers > 0, "Max stakers must be greater than 0");
        require(maxStakeAmount >= minStakeAmount, "Invalid stake amount range");
        
        nftStakingTiers[tierName] = NFTStakingTier({
            tierName: tierName,
            minStakingPower: minStakingPower,
            maxStakingPower: maxStakingPower,
            rewardMultiplier: rewardMultiplier,
            lockupPeriod: lockupPeriod,
            performanceFee: performanceFee,
            withdrawalFee: withdrawalFee,
            enabled: true,
            maxStakers: maxStakers,
            currentStakers: 0,
            maxStakeAmount: maxStakeAmount,
            minStakeAmount: minStakeAmount
        });
        
        emit NFTStakingTierCreated(
            tierName,
            minStakingPower,
            maxStakingPower,
            rewardMultiplier,
            lockupPeriod,
            performanceFee,
            withdrawalFee
        );
    }
    
    function updateNFTStakingTier(
        string memory tierName,
        uint256 minStakingPower,
        uint256 maxStakingPower,
        uint256 rewardMultiplier,
        uint256 lockupPeriod,
        uint256 performanceFee,
        uint256 withdrawalFee
    ) external onlyOwner {
        require(bytes(tierName).length > 0, "Tier name cannot be empty");
        require(nftStakingTiers[tierName].tierName.length > 0, "Tier not found");
        require(minStakingPower <= maxStakingPower, "Invalid staking power range");
        require(rewardMultiplier >= 1000, "Reward multiplier too low");
        require(lockupPeriod > 0, "Lockup period must be greater than 0");
        require(performanceFee <= 10000, "Performance fee too high");
        require(withdrawalFee <= 10000, "Withdrawal fee too high");
        
        NFTStakingTier storage tier = nftStakingTiers[tierName];
        tier.minStakingPower = minStakingPower;
        tier.maxStakingPower = maxStakingPower;
        tier.rewardMultiplier = rewardMultiplier;
        tier.lockupPeriod = lockupPeriod;
        tier.performanceFee = performanceFee;
        tier.withdrawalFee = withdrawalFee;
        
        emit NFTStakingTierUpdated(
            tierName,
            minStakingPower,
            maxStakingPower,
            rewardMultiplier,
            lockupPeriod,
            performanceFee,
            withdrawalFee
        );
    }
    
    function setNFTStakingConfig(
        address nftContract,
        uint256 defaultRewardMultiplier,
        uint256 defaultLockupPeriod,
        uint256 defaultPerformanceFee,
        uint256 defaultWithdrawalFee,
        bool enabled,
        uint256 maxStakers
    ) external onlyOwner {
        require(nftContract != address(0), "Invalid NFT contract");
        require(defaultRewardMultiplier >= 1000, "Reward multiplier too low");
        require(defaultLockupPeriod > 0, "Lockup period must be greater than 0");
        require(defaultPerformanceFee <= 10000, "Performance fee too high");
        require(defaultWithdrawalFee <= 10000, "Withdrawal fee too high");
        require(maxStakers > 0, "Max stakers must be greater than 0");
        
        nftStakingConfigs[nftContract] = NFTStakingConfig({
            nftContract: nftContract,
            defaultRewardMultiplier: defaultRewardMultiplier,
            defaultLockupPeriod: defaultLockupPeriod,
            defaultPerformanceFee: defaultPerformanceFee,
            defaultWithdrawalFee: defaultWithdrawalFee,
            enabled: enabled,
            maxStakers: maxStakers,
            lastUpdateTime: block.timestamp
        });
        
        emit NFTStakingConfigUpdated(
            nftContract,
            defaultRewardMultiplier,
            defaultLockupPeriod,
            defaultPerformanceFee,
            defaultWithdrawalFee,
            enabled
        );
    }
    
    function stakeNFT(
        address nftContract,
        uint256 tokenId,
        uint256 stakingDuration,
        string memory nftType,
        uint256 nftRarity,
        uint256 stakingPower
    ) external {
        require(nftStakingConfigs[nftContract].enabled, "NFT staking not enabled");
        require(ERC721(nftContract).ownerOf(tokenId) == msg.sender, "Not NFT owner");
        require(stakingDuration > 0, "Staking duration must be greater than 0");
        require(stakingPower > 0, "Staking power must be greater than 0");
        
        // Проверка, что NFT не находится в стейкинге
        require(nftStakes[nftContract][tokenId].tokenId != tokenId, "NFT already staked");
        
        // Проверка ставки по тайеру
        uint256 tierIndex = 0;
        bool tierFound = false;
        string[] memory tierNames = new string[](100); // Максимум 100 тайеров
        uint256 tierCount = 0;
        
        // Простой поиск тайера (в реальной реализации нужно более сложный механизм)
        for (uint256 i = 0; i < 100; i++) {
            if (bytes(nftStakingTiers[bytes32(i)].tierName).length > 0) {
                tierNames[tierCount] = string(abi.encodePacked(bytes32(i)));
                tierCount++;
                if (stakingPower >= nftStakingTiers[bytes32(i)].minStakingPower &&
                    stakingPower <= nftStakingTiers[bytes32(i)].maxStakingPower) {
                    tierIndex = i;
                    tierFound = true;
                    break;
                }
            }
        }
        
        NFTStakingTier storage tier = nftStakingTiers[bytes32(tierIndex)];
        if (!tierFound) {
            // Использовать базовый тайер
            tier = nftStakingTiers[bytes32(0)];
        }
        
        // Проверка ограничений тайера
        require(stakingPower >= tier.minStakingPower, "Staking power below minimum");
        require(stakingPower <= tier.maxStakingPower, "Staking power above maximum");
        require(tier.currentStakers < tier.maxStakers, "Tier full");
        
        // Проверка количества стейкеров
        if (nftStakingStats[nftContract].totalStakers >= nftStakingConfigs[nftContract].maxStakers) {
            revert("NFT staking limit reached");
        }
        
        // Создание стейкинг записи
        uint256 stakeId = uint256(keccak256(abi.encodePacked(nftContract, tokenId, block.timestamp)));
        
        nftStakes[nftContract][tokenId] = NFTStake({
            tokenId: tokenId,
            staker: msg.sender,
            nftContract: nftContract,
            stakeTime: block.timestamp,
            stakingDuration: stakingDuration,
            isStaked: true,
            rewardMultiplier: tier.rewardMultiplier,
            stakingPower: stakingPower,
            lastRewardTime: block.timestamp,
            totalRewardsEarned: 0,
            firstStakeTime: block.timestamp,
            lastClaimTime: 0,
            pendingRewards: 0,
            stakingHistory: new uint256[](1),
            nftType: nftType,
            nftRarity: nftRarity,
            lockupPeriod: tier.lockupPeriod,
            performanceFee: tier.performanceFee,
            withdrawalFee: tier.withdrawalFee,
            rewardDebt: 0
        });
        
        // Добавить в историю пользователя
        userNFTStakes[msg.sender][nftContract].push(tokenId);
        
        // Обновить статистику
        nftStakingStats[nftContract].totalStakedNFTs++;
        nftStakingStats[nftContract].totalStakers++;
        nftStakingStats[nftContract].totalValueLocked = nftStakingStats[nftContract].totalValueLocked.add(stakingPower);
        nftStakingStats[nftContract].averageStakingPower = nftStakingStats[nftContract].averageStakingPower.add(stakingPower);
        
        // Обновить статистику тайера
        tier.currentStakers++;
        
        // Передача NFT в контракт
        ERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);
        
        emit NFTStaked(
            msg.sender,
            nftContract,
            tokenId,
            stakingPower,
            tier.rewardMultiplier,
            stakingDuration,
            block.timestamp
        );
    }
    
    function unstakeNFT(
        address nftContract,
        uint256 tokenId
    ) external {
        NFTStake storage stake = nftStakes[nftContract][tokenId];
        require(stake.isStaked, "NFT not staked");
        require(stake.staker == msg.sender, "Not staker");
        require(block.timestamp >= stake.stakeTime + stake.lockupPeriod, "Lockup period not expired");
        
        // Расчет наград
        uint256 rewards = calculateNFTStakingRewards(nftContract, tokenId);
        
        // Применить комиссию
        uint256 feeAmount = rewards.mul(stake.withdrawalFee).div(10000);
        uint256 amountAfterFee = rewards.sub(feeAmount);
        
        // Обновить статистику
        nftStakingStats[nftContract].totalRewardsDistributed = nftStakingStats[nftContract].totalRewardsDistributed.add(amountAfterFee);
        
        // Возврат NFT пользователю
        ERC721(nftContract).transferFrom(address(this), msg.sender, tokenId);
        
        // Передача награды
        if (amountAfterFee > 0) {
            // Передача награды (в реальной реализации токены)
        }
        
        // Деактивировать стейкинг
        stake.isStaked = false;
        stake.totalRewardsEarned = stake.totalRewardsEarned.add(amountAfterFee);
        stake.lastClaimTime = block.timestamp;
        
        emit NFTUnstaked(
            msg.sender,
            nftContract,
            tokenId,
            amountAfterFee,
            block.timestamp
        );
    }
    
    function claimNFTStakingRewards(
        address nftContract,
        uint256 tokenId
    ) external {
        NFTStake storage stake = nftStakes[nftContract][tokenId];
        require(stake.isStaked, "NFT not staked");
        require(stake.staker == msg.sender, "Not staker");
        
        // Расчет наград
        uint256 rewards = calculateNFTStakingRewards(nftContract, tokenId);
        require(rewards > 0, "No rewards to claim");
        
        // Обновить стейкинг
        stake.pendingRewards = stake.pendingRewards.add(rewards);
        stake.rewardDebt = stake.rewardDebt.add(rewards);
        stake.totalRewardsEarned = stake.totalRewardsEarned.add(rewards);
        stake.lastClaimTime = block.timestamp;
        
        // Передача награды
        if (rewards > 0) {
            // Передача награды (в реальной реализации токены)
        }
        
        emit NFTStakingRewardsClaimed(
            msg.sender,
            nftContract,
            tokenId,
            rewards,
            block.timestamp
        );
    }
    
    function calculateNFTStakingRewards(
        address nftContract,
        uint256 tokenId
    ) internal view returns (uint256) {
        NFTStake storage stake = nftStakes[nftContract][tokenId];
        if (!stake.isStaked || stake.stakingDuration == 0) return 0;
        
        uint256 timeElapsed = block.timestamp.sub(stake.lastRewardTime);
        uint256 baseReward = stake.stakingPower.mul(stake.rewardMultiplier).div(10000);
        uint256 timeBonus = timeElapsed.div(3600).mul(100000000000000000); // 0.1 ETH за час
        
        return baseReward.add(timeBonus);
    }
    
    function updateNFTStakingPower(
        address nftContract,
        uint256 tokenId,
        uint256 newStakingPower
    ) external {
        NFTStake storage stake = nftStakes[nftContract][tokenId];
        require(stake.isStaked, "NFT not staked");
        require(stake.staker == msg.sender, "Not staker");
        require(newStakingPower > 0, "Staking power must be greater than 0");
        
        uint256 oldPower = stake.stakingPower;
        stake.stakingPower = newStakingPower;
        stake.lastRewardTime = block.timestamp;
        
        // Обновить статистику
        nftStakingStats[nftContract].totalValueLocked = nftStakingStats[nftContract].totalValueLocked.sub(oldPower).add(newStakingPower);
        nftStakingStats[nftContract].averageStakingPower = nftStakingStats[nftContract].averageStakingPower.sub(oldPower).add(newStakingPower);
        
        emit NFTStakingPowerUpdated(
            msg.sender,
            nftContract,
            tokenId,
            oldPower,
            newStakingPower,
            block.timestamp
        );
    }
    
    function getNFTStakeInfo(address nftContract, uint256 tokenId) external view returns (NFTStake memory) {
        return nftStakes[nftContract][tokenId];
    }
    
    function getNFTStakingTier(string memory tierName) external view returns (NFTStakingTier memory) {
        return nftStakingTiers[tierName];
    }
    
    function getNFTStakingConfig(address nftContract) external view returns (NFTStakingConfig memory) {
        return nftStakingConfigs[nftContract];
    }
    
    function getNFTStakingStats(address nftContract) external view returns (NFTStakingStats memory) {
        return nftStakingStats[nftContract];
    }
    
    function getUserNFTStakes(address user, address nftContract) external view returns (uint256[] memory) {
        return userNFTStakes[user][nftContract];
    }
    
    function getNFTStakingTiers() external view returns (string[] memory) {
        // Возвращает список всех тайеров
        return new string[](0);
    }
    
    function getStakedNFTsByUser(address user) external view returns (address[] memory, uint256[] memory) {
        // Возвращает список всех NFT пользователя
        return (new address[](0), new uint256[](0));
    }
    
    function getNFTStakingRewards(address user, address nftContract, uint256 tokenId) external view returns (uint256) {
        NFTStake storage stake = nftStakes[nftContract][tokenId];
        if (!stake.isStaked) return 0;
        
        return calculateNFTStakingRewards(nftContract, tokenId);
    }
    
    function getNFTStakingPower(address nftContract, uint256 tokenId) external view returns (uint256) {
        NFTStake storage stake = nftStakes[nftContract][tokenId];
        return stake.stakingPower;
    }
    
    function getNFTStakingTierByPower(uint256 stakingPower) external view returns (string memory) {
        // Возвращает тайер по мощности
        return "";
    }
    
    function getNFTStakingHistory(address user) external view returns (NFTStake[] memory) {
        // Возвращает историю стейкинга пользователя
        return new NFTStake[](0);
    }
    
    function getActiveNFTStakes(address nftContract) external view returns (uint256[] memory) {
     
        return new uint256[](0);
    }
}
}
