
// base-staking-protocol/test/staking-protocol.test.js
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Base Staking Protocol", function () {
  let stakingProtocol;
  let stakingToken;
  let owner;
  let addr1;

  beforeEach(async function () {
    [owner, addr1] = await ethers.getSigners();
    
    // Деплой токена
    const StakingToken = await ethers.getContractFactory("ERC20Token");
    stakingToken = await StakingToken.deploy("Staking Token", "STK");
    await stakingToken.deployed();
    
    // Деплой Staking Protocol
    const StakingProtocol = await ethers.getContractFactory("StakingProtocolV2");
    stakingProtocol = await StakingProtocol.deploy(
      stakingToken.address,
      ethers.utils.parseEther("10"), // 10 tokens per second
      Math.floor(Date.now() / 1000), // Current timestamp
      Math.floor(Date.now() / 1000) + 365 * 24 * 60 * 60 // 1 year from now
    );
    await stakingProtocol.deployed();
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await stakingProtocol.owner()).to.equal(owner.address);
    });

    it("Should initialize with correct parameters", async function () {
      expect(await stakingProtocol.rewardToken()).to.equal(stakingToken.address);
      expect(await stakingProtocol.rewardPerSecond()).to.equal(ethers.utils.parseEther("10"));
    });
  });

  describe("Pool Creation", function () {
    it("Should create a pool", async function () {
      await expect(stakingProtocol.createPool(
        stakingToken.address,
        ethers.utils.parseEther("100"),
        Math.floor(Date.now() / 1000),
        Math.floor(Date.now() / 1000) + 3600,
        10000, // 100% APR
        ethers.utils.parseEther("100"),
        ethers.utils.parseEther("10000")
      )).to.emit(stakingProtocol, "PoolCreated");
    });
  });

  describe("Staking Operations", function () {
    beforeEach(async function () {
      await stakingProtocol.createPool(
        stakingToken.address,
        ethers.utils.parseEther("100"),
        Math.floor(Date.now() / 1000),
        Math.floor(Date.now() / 1000) + 3600,
        10000, // 100% APR
        ethers.utils.parseEther("100"),
        ethers.utils.parseEther("10000")
      );
    });

    it("Should stake tokens", async function () {
      await stakingToken.mint(addr1.address, ethers.utils.parseEther("1000"));
      await stakingToken.connect(addr1).approve(stakingProtocol.address, ethers.utils.parseEther("1000"));
      
      await expect(stakingProtocol.connect(addr1).stake(stakingToken.address, ethers.utils.parseEther("100")))
        .to.emit(stakingProtocol, "Staked");
    });
  });
});
