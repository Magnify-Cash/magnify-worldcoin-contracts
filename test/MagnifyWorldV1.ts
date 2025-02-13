import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import hre from "hardhat";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";

describe("MagnifyWorld", function () {
  // Fixture to deploy contracts and set up initial state
  async function deployMagnifyWorldFixture() {
    // Get signers
    const [owner, user1, user2] = await ethers.getSigners();

    // Deploy mock ERC20 token for loans
    const MockToken = await ethers.getContractFactory("MockERC20");
    const mockToken = await MockToken.deploy("Mock Token", "MTK");

    // Deploy mock Permit2 contract
    const MockPermit2 = await ethers.getContractFactory("MockPermit2");
    const mockPermit2 = await MockPermit2.deploy();

    // Deploy MagnifyWorld
    const MagnifyWorld = await ethers.getContractFactory("MagnifyWorld");
    const magnifyWorld = await MagnifyWorld.deploy(
      await mockToken.getAddress(),
      await mockPermit2.getAddress()
    );

    // Mint some tokens to the contract for loans
    const mintAmount = ethers.parseUnits("1000", 6); // Assuming 6 decimals
    await mockToken.mint(await magnifyWorld.getAddress(), mintAmount);

    return { magnifyWorld, mockToken, mockPermit2, owner, user1, user2 };
  }

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      const { magnifyWorld, owner } = await loadFixture(
        deployMagnifyWorldFixture
      );
      expect(await magnifyWorld.owner()).to.equal(owner.address);
    });

    it("Should initialize with three default tiers", async function () {
      const { magnifyWorld } = await loadFixture(deployMagnifyWorldFixture);
      expect(await magnifyWorld.tierCount()).to.equal(3);

      // Check first tier details
      const tier1 = await magnifyWorld.tiers(1);
      expect(tier1.loanAmount).to.equal(1_000_000n); // 1 token with 6 decimals
      expect(tier1.interestRate).to.equal(250); // 2.5%
      expect(tier1.loanPeriod).to.equal(30 * 24 * 60 * 60); // 30 days in seconds
    });
  });

  describe("NFT Management", function () {
    it("Should allow owner to mint NFT", async function () {
      const { magnifyWorld, user1 } = await loadFixture(
        deployMagnifyWorldFixture
      );

      await expect(magnifyWorld.mintNFT(user1.address, 1))
        .to.emit(magnifyWorld, "NFTMinted")
        .withArgs(1, user1.address, 1);

      expect(await magnifyWorld.ownerOf(1)).to.equal(user1.address);
      expect(await magnifyWorld.nftToTier(1)).to.equal(1);
    });

    it("Should prevent non-owners from minting NFTs", async function () {
      const { magnifyWorld, user1 } = await loadFixture(
        deployMagnifyWorldFixture
      );

      await expect(
        magnifyWorld.connect(user1).mintNFT(user1.address, 1)
      ).to.be.revertedWithCustomError(
        magnifyWorld,
        "OwnableUnauthorizedAccount"
      );
    });

    it("Should prevent users from having multiple NFTs", async function () {
      const { magnifyWorld, user1 } = await loadFixture(
        deployMagnifyWorldFixture
      );

      await magnifyWorld.mintNFT(user1.address, 1);
      await expect(magnifyWorld.mintNFT(user1.address, 2)).to.be.revertedWith(
        "User already has an NFT"
      );
    });
  });

  describe("Loan Operations", function () {
    it("Should allow NFT owner to request a loan", async function () {
      const { magnifyWorld, mockToken, user1 } = await loadFixture(
        deployMagnifyWorldFixture
      );

      // Mint NFT to user1
      await magnifyWorld.mintNFT(user1.address, 1);

      // Request loan
      await expect(magnifyWorld.connect(user1).requestLoan())
        .to.emit(magnifyWorld, "LoanRequested")
        .withArgs(1, 1_000_000n, user1.address);

      // Check loan details
      const loan = await magnifyWorld.loans(1);
      expect(loan.amount).to.equal(1_000_000n);
      expect(loan.isActive).to.be.true;

      // Check token transfer
      expect(await mockToken.balanceOf(user1.address)).to.equal(1_000_000n);
    });

    it("Should allow loan repayment", async function () {
      const { magnifyWorld, mockToken, user1 } = await loadFixture(
        deployMagnifyWorldFixture
      );

      // Mint NFT and request loan
      await magnifyWorld.mintNFT(user1.address, 1);
      await magnifyWorld.connect(user1).requestLoan();

      // Calculate repayment amount (loan + 2.5% interest)
      const repayAmount = 1_025_000n; // 1,000,000 + 2.5%

      // Mint tokens to user for repayment
      await mockToken.mint(user1.address, repayAmount);
      await mockToken
        .connect(user1)
        .approve(magnifyWorld.getAddress(), repayAmount);

      // Repay loan
      await expect(magnifyWorld.connect(user1).repayLoan())
        .to.emit(magnifyWorld, "LoanRepaid")
        .withArgs(1, repayAmount, user1.address);

      // Verify loan is no longer active
      const loan = await magnifyWorld.loans(1);
      expect(loan.isActive).to.be.false;
    });
  });

  describe("Tier Management", function () {
    it("Should allow owner to add new tier", async function () {
      const { magnifyWorld } = await loadFixture(deployMagnifyWorldFixture);

      const newTierAmount = 20_000_000n; // 20 tokens
      const newTierRate = 100; // 1%
      const newTierPeriod = 120 * 24 * 60 * 60; // 120 days

      await expect(
        magnifyWorld.addTier(newTierAmount, newTierRate, newTierPeriod)
      )
        .to.emit(magnifyWorld, "TierAdded")
        .withArgs(4, newTierAmount, newTierRate, newTierPeriod);

      expect(await magnifyWorld.tierCount()).to.equal(4);
    });

    it("Should allow owner to update existing tier", async function () {
      const { magnifyWorld } = await loadFixture(deployMagnifyWorldFixture);

      const updatedAmount = 2_000_000n;
      const updatedRate = 300;
      const updatedPeriod = 45 * 24 * 60 * 60;

      await expect(
        magnifyWorld.updateTier(1, updatedAmount, updatedRate, updatedPeriod)
      )
        .to.emit(magnifyWorld, "TierUpdated")
        .withArgs(1, updatedAmount, updatedRate, updatedPeriod);

      const tier = await magnifyWorld.tiers(1);
      expect(tier.loanAmount).to.equal(updatedAmount);
      expect(tier.interestRate).to.equal(updatedRate);
      expect(tier.loanPeriod).to.equal(updatedPeriod);
    });
  });
});
