const fs = require("fs");
const path = require("path");
require("dotenv").config();

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  // stake token, if not provided deploy RewardDistributor as ERC20 helper if present
  let stakeToken = process.env.STAKE_TOKEN || "";

  if (!stakeToken) {
    const Token = await ethers.getContractFactory("RewardDistributor");
    const t = await Token.deploy("StakeToken", "STK", 18);
    await t.deployed();
    stakeToken = t.address;
    console.log("Deployed StakeToken (RewardDistributor):", stakeToken);
  }

  const Staking = await ethers.getContractFactory("StakingProtocol");
  const staking = await Staking.deploy(stakeToken);
  await staking.deployed();

  console.log("StakingProtocol:", staking.address);

  const out = {
    network: hre.network.name,
    chainId: (await ethers.provider.getNetwork()).chainId,
    deployer: deployer.address,
    contracts: {
      StakeToken: stakeToken,
      StakingProtocol: staking.address
    }
  };

  const outPath = path.join(__dirname, "..", "deployments.json");
  fs.writeFileSync(outPath, JSON.stringify(out, null, 2));
  console.log("Saved:", outPath);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
