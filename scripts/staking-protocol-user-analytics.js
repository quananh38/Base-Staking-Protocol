// base-staking-protocol/scripts/user-analytics.js
const { ethers } = require("hardhat");
const fs = require("fs");

async function analyzeStakingProtocolUserBehavior() {
  console.log("Analyzing user behavior for Base Staking Protocol...");
  
  const stakingAddress = "0x...";
  const staking = await ethers.getContractAt("StakingProtocolV2", stakingAddress);
  
  // Анализ пользовательского поведения
  const userAnalytics = {
    timestamp: new Date().toISOString(),
    stakingAddress: stakingAddress,
    userDemographics: {},
    engagementMetrics: {},
    stakingPatterns: {},
    userSegments: {},
    recommendations: []
  };
  
  try {
    // Демография пользователей
    const userDemographics = await staking.getUserDemographics();
    userAnalytics.userDemographics = {
      totalUsers: userDemographics.totalUsers.toString(),
      activeUsers: userDemographics.activeUsers.toString(),
      newUsers: userDemographics.newUsers.toString(),
      returningUsers: userDemographics.returningUsers.toString(),
      userDistribution: userDemographics.userDistribution
    };
    
    // Метрики вовлеченности
    const engagementMetrics = await staking.getEngagementMetrics();
    userAnalytics.engagementMetrics = {
      avgSessionTime: engagementMetrics.avgSessionTime.toString(),
      dailyActiveUsers: engagementMetrics.dailyActiveUsers.toString(),
      weeklyActiveUsers: engagementMetrics.weeklyActiveUsers.toString(),
      monthlyActiveUsers: engagementMetrics.monthlyActiveUsers.toString(),
      userRetention: engagementMetrics.userRetention.toString(),
      engagementScore: engagementMetrics.engagementScore.toString()
    };
    
    // Паттерны стейкинга
    const stakingPatterns = await staking.getStakingPatterns();
    userAnalytics.stakingPatterns = {
      avgStakeAmount: stakingPatterns.avgStakeAmount.toString(),
      stakingFrequency: stakingPatterns.stakingFrequency.toString(),
      popularStakingPeriods: stakingPatterns.popularStakingPeriods,
      peakStakingHours: stakingPatterns.peakStakingHours,
      averageStakingPeriod: stakingPatterns.averageStakingPeriod.toString(),
      withdrawalRate: stakingPatterns.withdrawalRate.toString()
    };
    
    // Сегментация пользователей
    const userSegments = await staking.getUserSegments();
    userAnalytics.userSegments = {
      casualStakers: userSegments.casualStakers.toString(),
      activeStakers: userSegments.activeStakers.toString(),
      longTermStakers: userSegments.longTermStakers.toString(),
      shortTermStakers: userSegments.shortTermStakers.toString(),
      highValueStakers: userSegments.highValueStakers.toString(),
      segmentDistribution: userSegments.segmentDistribution
    };
    
    // Анализ поведения
    if (parseFloat(userAnalytics.engagementMetrics.userRetention) < 70) {
      userAnalytics.recommendations.push("Low user retention - implement retention strategies");
    }
    
    if (parseFloat(userAnalytics.stakingPatterns.withdrawalRate) > 30) {
      userAnalytics.recommendations.push("High withdrawal rate - improve user retention");
    }
    
    if (parseFloat(userAnalytics.userSegments.highValueStakers) < 50) {
      userAnalytics.recommendations.push("Low high-value stakers - focus on premium user acquisition");
    }
    
    if (userAnalytics.userSegments.casualStakers > userAnalytics.userSegments.activeStakers) {
      userAnalytics.recommendations.push("More casual stakers than active stakers - consider staker engagement");
    }
    
    // Сохранение отчета
    const analyticsFileName = `staking-user-analytics-${Date.now()}.json`;
    fs.writeFileSync(`./analytics/${analyticsFileName}`, JSON.stringify(userAnalytics, null, 2));
    console.log(`User analytics report created: ${analyticsFileName}`);
    
    console.log("Staking protocol user analytics completed successfully!");
    console.log("Recommendations:", userAnalytics.recommendations);
    
  } catch (error) {
    console.error("User analytics error:", error);
    throw error;
  }
}

analyzeStakingProtocolUserBehavior()
  .catch(error => {
    console.error("User analytics failed:", error);
    process.exit(1);
  });
