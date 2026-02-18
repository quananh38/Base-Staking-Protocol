require("dotenv").config();
const fs = require("fs");
const path = require("path");

async function main() {
  const depPath = path.join(__dirname, "..", "deployments.json");
  const deployments = JSON.parse(fs.readFileSync(depPath, "utf8"));

  const stakingAddr = deployments.contracts.StakingProtocol;
  const stakeAddr = deployments.contracts.StakeToken;

  const [owner, user] = await ethers.getSigners();
  const staking = await ethers.getContractAt("StakingProtocol", stakingAddr);
  const stake = await ethers.getContractAt("RewardDistributor", stakeAddr);

  console.log("Staking:", stakingAddr);

  const amt = ethers.utils.parseUnits("10", 18);
  await (await stake.mint(user.address, amt)).wait();

  await (await stake.connect(user).approve(stakingAddr, amt)).wait();
  await (await staking.connect(user).stake(amt)).wait();
  console.log("Staked");

  await (await staking.pause()).wait();
  console.log("Paused");

  await (await staking.unpause()).wait();
  console.log("Unpaused");

  await (await staking.connect(user).unstake(amt)).wait();
  console.log("Unstaked");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

