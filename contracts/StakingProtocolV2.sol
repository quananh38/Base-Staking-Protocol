// base-staking-protocol/contracts/StakingProtocolV2.sol
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
    
    // События
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

    // Создание нового пула
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

    // Обновление параметров пула
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

    // Добавление тарифных планов
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

    // Установка комиссий
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

    // Установка lockup периода
    function setLockupPeriod(
        address pool,
        uint256 lockupPeriod
    ) external onlyOwner {
        require(pools[pool].token != address(0), "Pool does not exist");
        require(lockupPeriod <= MAX_LOCKUP_PERIOD, "Lockup period too long");
        
        pools[pool].lockupPeriod = lockupPeriod;
        emit LockupPeriodUpdated(pool, lockupPeriod);
    }

    // Стейкинг
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
        
        // Добавление в историю
        staker.stakingHistory.push(amount);
        
        emit Staked(msg.sender, pool, amount, amount, block.timestamp);
    }

    // Вывод стейкинга
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
        
        // Проверка lockup периода
        uint256 feeAmount = 0;
        if (block.timestamp < staker.firstStakeTime.add(poolInfo.lockupPeriod)) {
            feeAmount = amount.mul(poolInfo.withdrawalFee).div(10000);
        }
        
        uint256 amountAfterFee = amount.sub(feeAmount);
        
        staker.amountStaked = staker.amountStaked.sub(amountAfterFee);
        poolInfo.totalStaked = poolInfo.totalStaked.sub(amountAfterFee);
        
        // Применение комиссии
        if (feeAmount > 0) {
            poolInfo.token.transfer(owner(), feeAmount);
        }
        
        poolInfo.token.transfer(msg.sender, amountAfterFee);
        staker.lastUpdateTime = block.timestamp;
        
        emit Unstaked(msg.sender, pool, amountAfterFee, amountAfterFee, block.timestamp);
    }

    // Получение награды
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
        
        // Применение performance fee
        uint256 performanceFeeAmount = pending.mul(poolInfo.performanceFee).div(10000);
        uint256 amountAfterFee = pending.sub(performanceFeeAmount);
        
        if (performanceFeeAmount > 0) {
            rewardToken.transfer(owner(), performanceFeeAmount);
        }
        
        // Перевод награды
        rewardToken.transfer(msg.sender, amountAfterFee);
        
        // Обновление статистики
        staker.rewardDebt = staker.rewardDebt.add(amountAfterFee);
        staker.totalRewardsReceived = staker.totalRewardsReceived.add(amountAfterFee);
        staker.lastClaimTime = block.timestamp;
        staker.pendingRewards = staker.pendingRewards.sub(amountAfterFee);
        
        emit RewardClaimed(msg.sender, pool, amountAfterFee, block.timestamp);
    }

    // Обновление пула
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

    // Расчет ожидаемой награды
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

    // Получение информации о пуле
    function getPoolInfo(address pool) external view returns (Pool memory) {
        return pools[pool];
    }

    // Получение информации о пользователе
    function getUserInfo(address user) external view returns (Staker memory) {
        return stakers[user];
    }

    // Получение информации о наградах
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

    // Получение тарифных планов
    function getRewardTiers(address pool) external view returns (RewardTier[] memory) {
        return rewardTiers[pool];
    }

    // Получение статистики пула
    function getPoolStats(address pool) external view returns (
        uint256 totalStaked,
        uint256 totalRewards,
        uint256 apr,
        uint256 activeUsers
    ) {
        Pool storage poolInfo = pools[pool];
        uint256 activeUsersCount = 0;
        
        // Подсчет активных пользователей (упрощенная реализация)
        // В реальном случае нужно использовать mapping или другую структуру
        
        return (
            poolInfo.totalStaked,
            0, // totalRewards
            poolInfo.apr,
            activeUsersCount
        );
    }

    // Включение пула
    function activatePool(address pool) external onlyOwner {
        Pool storage poolInfo = pools[pool];
        require(poolInfo.token != address(0), "Pool does not exist");
        poolInfo.isActive = true;
        emit PoolActivated(pool);
    }

    // Отключение пула
    function deactivatePool(address pool) external onlyOwner {
        Pool storage poolInfo = pools[pool];
        require(poolInfo.token != address(0), "Pool does not exist");
        poolInfo.isActive = false;
        emit PoolDeactivated(pool);
    }

    // Получение истории стейкинга пользователя
    function getUserStakingHistory(address user) external view returns (uint256[] memory) {
        return stakers[user].stakingHistory;
    }

    // Получение общего количества пользователей
    function getTotalStakers() external view returns (uint256) {
        // Реализация в будущем
        return 0;
    }

    // Проверка возможности получения награды
    function canClaimReward(address user, address pool) external view returns (bool) {
        Pool storage poolInfo = pools[pool];
        Staker storage staker = stakers[user];
        if (poolInfo.token == address(0) || !poolInfo.isActive) return false;
        if (staker.amountStaked == 0) return false;
        return true;
    }

    // Получение эффективной ставки награды
    function getEffectiveRewardRate(address pool) external view returns (uint256) {
        Pool storage poolInfo = pools[pool];
        return poolInfo.rewardPerSecond;
    }

    // Получение информации о стейкинге
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
}
