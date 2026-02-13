

const { ethers } = require("hardhat");

async function main() {
  console.log("Deploying Base Staking Protocol...");
  
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", (await deployer.getBalance()).toString());


  const StakingToken = await ethers.getContractFactory("ERC20Token");
  const stakingToken = await StakingToken.deploy("Staking Token", "STK");
  await stakingToken.deployed();


  const StakingProtocol = await ethers.getContractFactory("StakingProtocolV2");
  const stakingProtocol = await StakingProtocol.deploy(
    stakingToken.address,
    ethers.utils.parseEther("10"), 
    Math.floor(Date.now() / 1000), // Current timestamp
    Math.floor(Date.now() / 1000) + 365 * 24 * 60 * 60 // 1 year from now
  );

  await stakingProtocol.deployed();

  console.log("Base Staking Protocol deployed to:", stakingProtocol.address);
  console.log("Staking Token deployed to:", stakingToken.address);
  
  // Сохраняем адреса
  const fs = require("fs");
  const data = {
    stakingProtocol: stakingProtocol.address,
    stakingToken: stakingToken.address,
    owner: deployer.address
  };
  
  fs.writeFileSync("./config/deployment.json", JSON.stringify(data, null, 2));
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
