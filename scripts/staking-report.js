// base-staking-protocol/scripts/report.js
const { ethers } = require("hardhat");

async function generateStakingReport() {
  console.log("Generating Base Staking Protocol Report...");
  
  const stakingAddress = "0x...";
  const staking = await ethers.getContractAt("StakingProtocolV2", stakingAddress);
  
  // Получение статистики
  const stats = await staking.getStakingStats();
  console.log("Staking Stats:", {
    totalStaked: stats.totalStaked.toString(),
    totalRewards: stats.totalRewards.toString(),
    totalUsers: stats.totalUsers.toString(),
    totalPools: stats.totalPools.toString(),
    avgAPR: stats.avgAPR.toString()
  });
  
  // Получение информации о пулах
  const poolInfo = await staking.getPoolInfo();
  console.log("Pool Info:", {
    totalPools: poolInfo.totalPools.toString(),
    activePools: poolInfo.activePools.toString(),
    totalStaked: poolInfo.totalStaked.toString()
  });
  
  // Получение информации о пользователях
  const userStats = await staking.getUserStats();
  console.log("User Stats:", {
    totalUsers: userStats.totalUsers.toString(),
    activeUsers: userStats.activeUsers.toString(),
    avgStaked: userStats.avgStaked.toString()
  });
  
  // Генерация отчета
  const fs = require("fs");
  const report = {
    timestamp: new Date().toISOString(),
    stakingAddress: stakingAddress,
    report: {
      stats: stats,
      poolInfo: poolInfo,
      userStats: userStats
    }
  };
  
  fs.writeFileSync("./reports/staking-report.json", JSON.stringify(report, null, 2));
  
  console.log("Staking report generated successfully!");
}

generateStakingReport()
  .catch(error => {
    console.error("Report generation error:", error);
    process.exit(1);
  });
