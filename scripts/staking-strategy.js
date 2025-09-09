// base-staking-protocol/scripts/strategy.js
const { ethers } = require("hardhat");
const fs = require("fs");

async function generateStakingStrategy() {
  console.log("Generating staking strategy for Base Staking Protocol...");
  
  const stakingAddress = "0x...";
  const staking = await ethers.getContractAt("StakingProtocolV2", stakingAddress);
  
  // Получение стратегии
  const strategy = {
    timestamp: new Date().toISOString(),
    stakingAddress: stakingAddress,
    currentStrategy: {},
    performanceMetrics: {},
    riskProfile: {},
    recommendation: {},
    strategyTimeline: []
  };
  
  // Текущая стратегия
  const currentStrategy = await staking.getCurrentStrategy();
  strategy.currentStrategy = {
    apr: currentStrategy.apr.toString(),
    stakingPeriod: currentStrategy.stakingPeriod.toString(),
    rewardDistribution: currentStrategy.rewardDistribution.toString(),
    lockupPeriod: currentStrategy.lockupPeriod.toString()
  };
  
  // Показатели производительности
  const performanceMetrics = await staking.getPerformanceMetrics();
  strategy.performanceMetrics = {
    totalStaked: performanceMetrics.totalStaked.toString(),
    totalRewards: performanceMetrics.totalRewards.toString(),
    userGrowth: performanceMetrics.userGrowth.toString(),
    retentionRate: performanceMetrics.retentionRate.toString()
  };
  
  // Профиль рисков
  const riskProfile = await staking.getRiskProfile();
  strategy.riskProfile = {
    marketRisk: riskProfile.marketRisk.toString(),
    liquidityRisk: riskProfile.liquidityRisk.toString(),
    smartContractRisk: riskProfile.smartContractRisk.toString(),
    operationalRisk: riskProfile.operationalRisk.toString()
  };
  
  // Рекомендации
  const recommendation = await staking.getRecommendation();
  strategy.recommendation = {
    action: recommendation.action,
    timing: recommendation.timing.toString(),
    expectedOutcome: recommendation.expectedOutcome
  };
  
  // Хронология стратегии
  const strategyTimeline = await staking.getStrategyTimeline(5);
  strategy.strategyTimeline = strategyTimeline.map(entry => ({
    timestamp: entry.timestamp.toString(),
    strategy: entry.strategy,
    performance: entry.performance.toString(),
    changes: entry.changes
  }));
  
  // Сохранение стратегии
  const fileName = `staking-strategy-${Date.now()}.json`;
  fs.writeFileSync(`./strategy/${fileName}`, JSON.stringify(strategy, null, 2));
  
  console.log("Staking strategy generated successfully!");
  console.log("File saved:", fileName);
}

generateStakingStrategy()
  .catch(error => {
    console.error("Strategy error:", error);
    process.exit(1);
  });
