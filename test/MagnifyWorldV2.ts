import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";

describe("MagnifyWorldV2", function () {
  // Fixture to deploy all contracts and set up initial state
  async function deployMagnifyWorldV2Fixture() {
    // Get signers
    const [owner, user1, user2] = await ethers.getSigners();

    // Deploy mock ERC20 token
    const MockToken = await ethers.getContractFactory("MockERC20");
    const mockToken = await MockToken.deploy("Mock Token", "MTK");

    // Deploy mock Permit2
    const MockPermit2 = await ethers.getContractFactory("MockPermit2");
    const mockPermit2 = await MockPermit2.deploy();

    // Deploy V1 contract
    const MagnifyWorldV1 = await ethers.getContractFactory("MagnifyWorld");
    const magnifyWorldV1 = await MagnifyWorldV1.deploy(
      await mockToken.getAddress(),
      await mockPermit2.getAddress()
    );

    // Deploy V2 contract
    const MagnifyWorldV2 = await ethers.getContractFactory("MagnifyWorldV2");
    const magnifyWorldV2 = await MagnifyWorldV2.deploy(await magnifyWorldV1.getAddress());

    // Mint tokens to both contracts for loans
    const mintAmount = ethers.parseUnits("1000", 6); // Assuming 6 decimals
    await mockToken.mint(await magnifyWorldV1.getAddress(), mintAmount);
    await mockToken.mint(await magnifyWorldV2.getAddress(), mintAmount);

    return { 
      magnifyWorldV1, 
      magnifyWorldV2, 
      mockToken, 
      mockPermit2, 
      owner, 
      user1, 
      user2 
    };
  }

  describe("Deployment", function () {
    it("Should correctly initialize with V1 contract address", async function () {
      const { magnifyWorldV2, magnifyWorldV1 } = await loadFixture(
        deployMagnifyWorldV2Fixture
      );
      expect(await magnifyWorldV2.v1()).to.equal(await magnifyWorldV1.getAddress());
    });

    it("Should inherit loan token from V1", async function () {
      const { magnifyWorldV2, mockToken } = await loadFixture(
        deployMagnifyWorldV2Fixture
      );
      expect(await magnifyWorldV2.loanToken()).to.equal(await mockToken.getAddress());
    });

    it("Should inherit PERMIT2 from V1", async function () {
      const { magnifyWorldV2, mockPermit2 } = await loadFixture(
        deployMagnifyWorldV2Fixture
      );
      expect(await magnifyWorldV2.PERMIT2()).to.equal(await mockPermit2.getAddress());
    });
  });

  describe("V2 Loan Operations", function () {
    it("Should allow NFT owner to request a loan in their tier", async function () {
      const { magnifyWorldV2, magnifyWorldV1, mockToken, user1 } = await loadFixture(
        deployMagnifyWorldV2Fixture
      );

      // Mint NFT to user1 with tier 2
      await magnifyWorldV1.mintNFT(user1.address, 2);
      
      // Request loan in tier 2
      await expect(magnifyWorldV2.connect(user1).requestLoan(2))
        .to.emit(magnifyWorldV2, "LoanRequested")
        .withArgs(1, 5_000_000n, user1.address); // Tier 2 amount is 5 tokens

      // Check loan details
      const loan = await magnifyWorldV2.v2Loans(1);
      expect(loan.amount).to.equal(5_000_000n);
      expect(loan.isActive).to.be.true;

      // Verify token transfer
      expect(await mockToken.balanceOf(user1.address)).to.equal(5_000_000n);
    });

    it("Should allow NFT owner to request a loan in a lower tier", async function () {
      const { magnifyWorldV2, magnifyWorldV1, user1 } = await loadFixture(
        deployMagnifyWorldV2Fixture
      );

      // Mint NFT to user1 with tier 2
      await magnifyWorldV1.mintNFT(user1.address, 2);
      
      // Request loan in tier 1
      await expect(magnifyWorldV2.connect(user1).requestLoan(1))
        .to.emit(magnifyWorldV2, "LoanRequested")
        .withArgs(1, 1_000_000n, user1.address); // Tier 1 amount is 1 token
    });

    it("Should prevent requesting loan in higher tier", async function () {
      const { magnifyWorldV2, magnifyWorldV1, user1 } = await loadFixture(
        deployMagnifyWorldV2Fixture
      );

      // Mint NFT to user1 with tier 1
      await magnifyWorldV1.mintNFT(user1.address, 1);
      
      // Attempt to request loan in tier 2
      await expect(
        magnifyWorldV2.connect(user1).requestLoan(2)
      ).to.be.revertedWith("Tier not allowed");
    });

    it("Should prevent multiple active loans", async function () {
      const { magnifyWorldV2, magnifyWorldV1, user1 } = await loadFixture(
        deployMagnifyWorldV2Fixture
      );

      // Mint NFT and get first loan
      await magnifyWorldV1.mintNFT(user1.address, 1);
      await magnifyWorldV2.connect(user1).requestLoan(1);

      // Attempt second loan
      await expect(
        magnifyWorldV2.connect(user1).requestLoan(1)
      ).to.be.revertedWith("Active loan on V2");
    });

    it("Should prevent loan if active in V1", async function () {
      const { magnifyWorldV2, magnifyWorldV1, user1 } = await loadFixture(
        deployMagnifyWorldV2Fixture
      );

      // Mint NFT and get V1 loan
      await magnifyWorldV1.mintNFT(user1.address, 1);
      await magnifyWorldV1.connect(user1).requestLoan();

      // Attempt V2 loan
      await expect(
        magnifyWorldV2.connect(user1).requestLoan(1)
      ).to.be.revertedWith("Active loan on V1");
    });
  });

  describe("Loan Queries", function () {
    it("Should correctly return V1 loan details", async function () {
      const { magnifyWorldV2, magnifyWorldV1, user1 } = await loadFixture(
        deployMagnifyWorldV2Fixture
      );

      // Mint NFT and get V1 loan
      await magnifyWorldV1.mintNFT(user1.address, 1);
      await magnifyWorldV1.connect(user1).requestLoan();

      const [hasLoan, loanDetails] = await magnifyWorldV2.fetchLoanByAddress(user1.address);
      expect(hasLoan).to.be.true;
      expect(loanDetails.amount).to.equal(1_000_000n);
      expect(loanDetails.isActive).to.be.true;
    });

    it("Should correctly return V2 loan details", async function () {
      const { magnifyWorldV2, magnifyWorldV1, user1 } = await loadFixture(
        deployMagnifyWorldV2Fixture
      );

      // Mint NFT and get V2 loan
      await magnifyWorldV1.mintNFT(user1.address, 1);
      await magnifyWorldV2.connect(user1).requestLoan(1);

      const [hasLoan, loanDetails] = await magnifyWorldV2.fetchLoanByAddress(user1.address);
      expect(hasLoan).to.be.true;
      expect(loanDetails.amount).to.equal(1_000_000n);
      expect(loanDetails.isActive).to.be.true;
    });

    it("Should return no loan when none active", async function () {
      const { magnifyWorldV2, user1 } = await loadFixture(
        deployMagnifyWorldV2Fixture
      );

      const [hasLoan, loanDetails] = await magnifyWorldV2.fetchLoanByAddress(user1.address);
      expect(hasLoan).to.be.false;
      expect(loanDetails.amount).to.equal(0n);
      expect(loanDetails.isActive).to.be.false;
    });
  });

  describe("Token Management", function () {
    it("Should allow owner to withdraw loan tokens", async function () {
      const { magnifyWorldV2, mockToken, owner } = await loadFixture(
        deployMagnifyWorldV2Fixture
      );

      const initialBalance = await mockToken.balanceOf(owner.address);
      const contractBalance = await mockToken.balanceOf(await magnifyWorldV2.getAddress());

      await expect(magnifyWorldV2.withdrawLoanToken())
        .to.emit(magnifyWorldV2, "LoanTokensWithdrawn")
        .withArgs(contractBalance);

      expect(await mockToken.balanceOf(owner.address)).to.equal(
        initialBalance + contractBalance
      );
    });

    it("Should prevent non-owner from withdrawing tokens", async function () {
      const { magnifyWorldV2, user1 } = await loadFixture(
        deployMagnifyWorldV2Fixture
      );

      await expect(
        magnifyWorldV2.connect(user1).withdrawLoanToken()
      ).to.be.revertedWithCustomError(magnifyWorldV2, "OwnableUnauthorizedAccount");
    });

    it("Should prevent withdrawal when balance is zero", async function () {
      const { magnifyWorldV2, mockToken } = await loadFixture(
        deployMagnifyWorldV2Fixture
      );

      // Transfer all tokens out of contract
      const balance = await mockToken.balanceOf(await magnifyWorldV2.getAddress());
      await mockToken.transfer(await magnifyWorldV2.owner(), balance);

      await expect(
        magnifyWorldV2.withdrawLoanToken()
      ).to.be.revertedWith("No funds available");
    });
  });
});
