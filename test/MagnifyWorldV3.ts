import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { Contract, Signer } from "ethers";

const NFT_NAME = "Magnify World Soulbound NFT";
const NFT_SYMBOL = "MAGNFT";
const NAME = "MagnifyWorldV3";
const SYMBOL = "MAGV3";
const OWNER = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
const TREASURY_ADDRESS = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
const SECONDS_PER_DAY = 60 * 60 * 24;

// https://docs.openzeppelin.com/contracts/2.x/api/token/erc20#IERC20
// https://docs.openzeppelin.com/contracts/4.x/api/token/erc20#ERC4626
describe("MagnifyWorldV3", function () {
  // Fixture to deploy all contracts and set up initial state
  async function deployMagnifyWorldV3Fixture() {
    // Get signers
    const [owner, user1, user2] = await ethers.getSigners();

    // Deploy mock ERC20 token
    const MockToken = await ethers.getContractFactory("MockERC20");
    const mockToken = await MockToken.deploy("Mock Token", "MTK");

    // Deploy mock Permit2
    const MockPermit2 = await ethers.getContractFactory("MockPermit2");
    const mockPermit2 = await MockPermit2.deploy();

    // Deploy V1 contract
    const MagnifyWorldV1 = await ethers.getContractFactory(
      "MagnifyWorld"
    );
    const magnifyWorldV1 = await MagnifyWorldV1.deploy(
      await mockToken.getAddress(),
      await mockPermit2.getAddress()
    );

    // Deploy MagnifyWorldSoulboundNFT contract
    const MagnifyWorldSoulboundNFT = await ethers.getContractFactory(
      "MagnifyWorldSoulboundNFT"
    );
    const magnifyWorldSoulboundNFT = await upgrades.deployProxy(
      MagnifyWorldSoulboundNFT,
      [NFT_NAME, NFT_SYMBOL]
    );

    // Deploy V3 contract
    const MagnifyWorldV3 = await ethers.getContractFactory("MagnifyWorldV3");
    const magnifyWorldV3 = await upgrades.deployProxy(MagnifyWorldV3, [
      NAME,
      SYMBOL,
      await mockToken.getAddress(),
      await mockPermit2.getAddress(),
      await magnifyWorldSoulboundNFT.getAddress(),
      await magnifyWorldV1.getAddress(),
      await (user1.getAddress()),
    ]);

    // Mint tokens to both contracts for loans
    const mintAmount = ethers.parseUnits("1000", 6); // Assuming 6 decimals
    await mockToken.mint(await magnifyWorldV1.getAddress(), mintAmount);
    await mockToken.mint(await magnifyWorldV3.getAddress(), mintAmount);


    await magnifyWorldV3.addTier(3, ethers.parseUnits("10", 6), 30 * SECONDS_PER_DAY, 200);
    return {
      magnifyWorldV1,
      magnifyWorldV3,
      mockToken,
      mockPermit2,
      owner,
      user1,
      user2,
    };
  }

  describe("Deployment", function () {
    it("Should correctly initialize with V1 contract address", async function () {
      const { magnifyWorldV3, magnifyWorldV1 } = await loadFixture(
        deployMagnifyWorldV3Fixture
      );
      expect(await magnifyWorldV3.v1()).to.equal(
        await magnifyWorldV1.getAddress()
      );
    });

    it("Should inherit loan token from V1", async function () {
      const { magnifyWorldV3, mockToken } = await loadFixture(
        deployMagnifyWorldV3Fixture
      );
      expect(await magnifyWorldV3.asset()).to.equal(
        await mockToken.getAddress()
      );
    });

    it("Should inherit PERMIT2 from V1", async function () {
      const { magnifyWorldV3, mockPermit2 } = await loadFixture(
        deployMagnifyWorldV3Fixture
      );
      expect(await magnifyWorldV3.permit2()).to.equal(
        await mockPermit2.getAddress()
      );
    });
  });

  describe("V3 Loan Operations", function () {
    it("Should allow NFT owner to request a loan in their tier", async function () {
      const { magnifyWorldV3, magnifyWorldV1, mockToken, user1 } =
        await loadFixture(deployMagnifyWorldV3Fixture);

      // Mint NFT to user1 with tier 2
      await magnifyWorldV1.mintNFT(user1.address, 2);

      // Request loan in tier 2
      await expect(magnifyWorldV3.connect(user1).requestLoan(2))
        .to.emit(magnifyWorldV3, "LoanRequested")
        .withArgs(1, 5_000_000n, user1.address); // Tier 2 amount is 5 tokens

      // Check loan details
      const loan = await magnifyWorldV3.V3Loans(1);
      expect(loan.amount).to.equal(5_000_000n);
      expect(loan.isActive).to.be.true;

      // Verify token transfer
      expect(await mockToken.balanceOf(user1.address)).to.equal(5_000_000n);
    });

    it("Should allow NFT owner to request a loan in a lower tier", async function () {
      const { magnifyWorldV3, magnifyWorldV1, user1 } = await loadFixture(
        deployMagnifyWorldV3Fixture
      );

      // Mint NFT to user1 with tier 2
      await magnifyWorldV1.mintNFT(user1.address, 2);

      // Request loan in tier 1
      await expect(magnifyWorldV3.connect(user1).requestLoan(1))
        .to.emit(magnifyWorldV3, "LoanRequested")
        .withArgs(1, 1_000_000n, user1.address); // Tier 1 amount is 1 token
    });

    it("Should prevent requesting loan in higher tier", async function () {
      const { magnifyWorldV3, magnifyWorldV1, user1 } = await loadFixture(
        deployMagnifyWorldV3Fixture
      );

      // Mint NFT to user1 with tier 1
      await magnifyWorldV1.mintNFT(user1.address, 1);

      // Attempt to request loan in tier 2
      await expect(
        magnifyWorldV3.connect(user1).requestLoan(2)
      ).to.be.revertedWith("Tier not allowed");
    });

    it("Should prevent multiple active loans", async function () {
      const { magnifyWorldV3, magnifyWorldV1, user1 } = await loadFixture(
        deployMagnifyWorldV3Fixture
      );

      // Mint NFT and get first loan
      await magnifyWorldV1.mintNFT(user1.address, 1);
      await magnifyWorldV3.connect(user1).requestLoan(1);

      // Attempt second loan
      await expect(
        magnifyWorldV3.connect(user1).requestLoan(1)
      ).to.be.revertedWith("Active loan on V3");
    });

    it("Should prevent loan if active in V1", async function () {
      const { magnifyWorldV3, magnifyWorldV1, user1 } = await loadFixture(
        deployMagnifyWorldV3Fixture
      );

      // Mint NFT and get V1 loan
      await magnifyWorldV1.mintNFT(user1.address, 1);
      await magnifyWorldV1.connect(user1).requestLoan();

      // Attempt V3 loan
      await expect(
        magnifyWorldV3.connect(user1).requestLoan(1)
      ).to.be.revertedWith("Active loan on V1");
    });
  });

  describe("Loan Queries", function () {
    it("Should correctly return V1 loan details", async function () {
      const { magnifyWorldV3, magnifyWorldV1, user1 } = await loadFixture(
        deployMagnifyWorldV3Fixture
      );

      // Mint NFT and get V1 loan
      await magnifyWorldV1.mintNFT(user1.address, 1);
      await magnifyWorldV1.connect(user1).requestLoan();

      const [hasLoan, loanDetails] = await magnifyWorldV3.fetchLoanByAddress(
        user1.address
      );
      expect(hasLoan).to.be.true;
      expect(loanDetails.amount).to.equal(1_000_000n);
      expect(loanDetails.isActive).to.be.true;
    });

    it("Should correctly return V3 loan details", async function () {
      const { magnifyWorldV3, magnifyWorldV1, user1 } = await loadFixture(
        deployMagnifyWorldV3Fixture
      );

      // Mint NFT and get V3 loan
      await magnifyWorldV1.mintNFT(user1.address, 1);
      await magnifyWorldV3.connect(user1).requestLoan(1);

      const [hasLoan, loanDetails] = await magnifyWorldV3.fetchLoanByAddress(
        user1.address
      );
      expect(hasLoan).to.be.true;
      expect(loanDetails.amount).to.equal(1_000_000n);
      expect(loanDetails.isActive).to.be.true;
    });

    it("Should return no loan when none active", async function () {
      const { magnifyWorldV3, user1 } = await loadFixture(
        deployMagnifyWorldV3Fixture
      );

      const [hasLoan, loanDetails] = await magnifyWorldV3.fetchLoanByAddress(
        user1.address
      );
      expect(hasLoan).to.be.false;
      expect(loanDetails.amount).to.equal(0n);
      expect(loanDetails.isActive).to.be.false;
    });
  });

  describe("Token Management", function () {
    it("Should allow owner to withdraw loan tokens", async function () {
      const { magnifyWorldV3, mockToken, owner } = await loadFixture(
        deployMagnifyWorldV3Fixture
      );

      const initialBalance = await mockToken.balanceOf(owner.address);
      const contractBalance = await mockToken.balanceOf(
        await magnifyWorldV3.getAddress()
      );

      await expect(magnifyWorldV3.withdrawLoanToken())
        .to.emit(magnifyWorldV3, "LoanTokensWithdrawn")
        .withArgs(contractBalance);

      expect(await mockToken.balanceOf(owner.address)).to.equal(
        initialBalance + contractBalance
      );
    });

    it("Should prevent non-owner from withdrawing tokens", async function () {
      const { magnifyWorldV3, user1 } = await loadFixture(
        deployMagnifyWorldV3Fixture
      );

      await expect(
        magnifyWorldV3.connect(user1).withdrawLoanToken()
      ).to.be.revertedWithCustomError(
        magnifyWorldV3,
        "OwnableUnauthorizedAccount"
      );
    });

    it("Should prevent withdrawal when balance is zero", async function () {
      const { magnifyWorldV3, mockToken } = await loadFixture(
        deployMagnifyWorldV3Fixture
      );

      // Transfer all tokens out of contract
      const balance = await mockToken.balanceOf(
        await magnifyWorldV3.getAddress()
      );
      await mockToken.transfer(await magnifyWorldV3.owner(), balance);

      await expect(magnifyWorldV3.withdrawLoanToken()).to.be.revertedWith(
        "No funds available"
      );
    });
  });
});
