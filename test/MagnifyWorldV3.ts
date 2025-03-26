import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers, upgrades } from "hardhat";

const NFT_NAME = "Magnify World Soulbound NFT";
const NFT_SYMBOL = "MAGNFT";
const NAME = "MagnifyWorldV3";
const SYMBOL = "MAGV3";
const SECONDS_PER_DAY = 60 * 60 * 24;
const startTimestamp = Math.round(Date.now() / 1000) + SECONDS_PER_DAY;
const endTimestamp = startTimestamp + SECONDS_PER_DAY * 30; // 30 days
const loanAmount = ethers.parseUnits("10", 6); // 10 USDC
const loanDuration = SECONDS_PER_DAY * 7; // 7 days
const loanInterest = 1000; // 10%
const tier = 3;

// https://docs.openzeppelin.com/contracts/2.x/api/token/erc20#IERC20
// https://docs.openzeppelin.com/contracts/4.x/api/token/erc20#ERC4626
describe("MagnifyWorldV3", function () {
  // Fixture to deploy all contracts and set up initial state
  async function deployMagnifyWorldV3Fixture() {
    // Get signers
    const [owner, user1, treasury, ...users] = await ethers.getSigners();

    // Deploy mock ERC20 token
    const MockToken = await ethers.getContractFactory("MockERC20");
    const mockToken = await MockToken.deploy("Mock Token", "MTK");

    // Deploy mock Permit2
    const MockPermit2 = await ethers.getContractFactory("MockPermit2");
    const mockPermit2 = await MockPermit2.deploy();

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
      await treasury.getAddress(),
    ]);

    await magnifyWorldV3.setup(
      startTimestamp,
      endTimestamp,
      loanAmount,
      loanDuration,
      loanInterest,
      tier
    );

    // Mint tokens to both contracts for loans
    const mintAmount = ethers.parseUnits("1000", 6); // Assuming 6 decimals
    await mockToken.mint(await owner.getAddress(), mintAmount);
    await mockToken.mint(await user1.getAddress(), mintAmount);
    await magnifyWorldSoulboundNFT.mintNFT(await owner.getAddress(), tier);
    await magnifyWorldSoulboundNFT.mintNFT(await user1.getAddress(), tier - 1);

    return {
      magnifyWorldV3,
      magnifyWorldSoulboundNFT,
      mockToken,
      mockPermit2,
      owner,
      user1,
      treasury,
      users,
    };
  }

  describe("Vault Operations", function () {
    describe("Deposits", function () {
      it("Should allow deposits and mint correct shares", async function () {
        const { magnifyWorldV3, mockToken, user1 } = await loadFixture(
          deployMagnifyWorldV3Fixture
        );

        const depositAmount = ethers.parseUnits("100", 6);

        // Approve tokens
        await mockToken.connect(user1).approve(magnifyWorldV3, depositAmount);

        // Initial deposit should mint equal shares (1:1)
        await expect(
          magnifyWorldV3.connect(user1).deposit(depositAmount, user1)
        )
          .to.emit(magnifyWorldV3, "Deposit")
          .withArgs(user1.address, user1.address, depositAmount, depositAmount);

        expect(await magnifyWorldV3.balanceOf(user1)).to.equal(depositAmount);
      });

      it("Should allow minting shares directly", async function () {
        const { magnifyWorldV3, mockToken, user1 } = await loadFixture(
          deployMagnifyWorldV3Fixture
        );

        const shareAmount = ethers.parseUnits("100", 6);

        // Approve tokens
        await mockToken.connect(user1).approve(magnifyWorldV3, shareAmount);

        // Mint shares directly
        await expect(magnifyWorldV3.connect(user1).mint(shareAmount, user1))
          .to.emit(magnifyWorldV3, "Deposit")
          .withArgs(user1.address, user1.address, shareAmount, shareAmount);

        expect(await magnifyWorldV3.balanceOf(user1)).to.equal(shareAmount);
      });

      it("Should not allow deposits during cooldown period", async function () {
        const { magnifyWorldV3, mockToken, user1 } = await loadFixture(
          deployMagnifyWorldV3Fixture
        );

        // Move time to cooldown period (endTimestamp - loanPeriod)
        await time.increaseTo(endTimestamp - loanDuration);

        const depositAmount = ethers.parseUnits("100", 6);
        await mockToken.connect(user1).approve(magnifyWorldV3, depositAmount);

        await expect(
          magnifyWorldV3.connect(user1).deposit(depositAmount, user1)
        ).to.be.revertedWithCustomError(magnifyWorldV3, "PoolNotActive");
      });
    });

    describe("Withdrawals", function () {
      it("Should allow withdrawals before start time with early exit fee", async function () {
        const { magnifyWorldV3, mockToken, user1, treasury } =
          await loadFixture(deployMagnifyWorldV3Fixture);

        const depositAmount = ethers.parseUnits("100", 6);
        await mockToken.connect(user1).approve(magnifyWorldV3, depositAmount);
        await magnifyWorldV3.connect(user1).deposit(depositAmount, user1);

        // Early exit fee is 1% (100 basis points)
        const expectedFee = (depositAmount * BigInt(100)) / BigInt(10000);
        const expectedWithdraw = depositAmount - expectedFee;

        await expect(
          magnifyWorldV3.connect(user1).withdraw(depositAmount, user1, user1)
        ).to.changeTokenBalances(
          mockToken,
          [user1, treasury],
          [expectedWithdraw, expectedFee]
        );
      });

      it("Should allow redemption after pool ends", async function () {
        const { magnifyWorldV3, mockToken, user1 } = await loadFixture(
          deployMagnifyWorldV3Fixture
        );

        const depositAmount = ethers.parseUnits("100", 6);
        await mockToken.connect(user1).approve(magnifyWorldV3, depositAmount);
        await magnifyWorldV3.connect(user1).deposit(depositAmount, user1);

        // Move time past end timestamp
        await time.increaseTo(endTimestamp + 1);

        await expect(
          magnifyWorldV3.connect(user1).redeem(depositAmount, user1, user1)
        ).to.changeTokenBalance(mockToken, user1, depositAmount);
      });

      it("Should not allow withdrawals during active period", async function () {
        const { magnifyWorldV3, mockToken, user1 } = await loadFixture(
          deployMagnifyWorldV3Fixture
        );

        const depositAmount = ethers.parseUnits("100", 6);
        await mockToken.connect(user1).approve(magnifyWorldV3, depositAmount);
        await magnifyWorldV3.connect(user1).deposit(depositAmount, user1);

        // Move time to active period
        await time.increaseTo(startTimestamp + 1);

        await expect(
          magnifyWorldV3.connect(user1).withdraw(depositAmount, user1, user1)
        ).to.be.revertedWithCustomError(magnifyWorldV3, "NoWithdrawWhenActive");
      });

      it("Should handle withdrawals with permit2", async function () {
        const { magnifyWorldV3, mockToken, mockPermit2, user1 } =
          await loadFixture(deployMagnifyWorldV3Fixture);

        const depositAmount = ethers.parseUnits("100", 6);

        // Create mock permit data
        const permitTransferFrom = {
          permitted: {
            token: await mockToken.getAddress(),
            amount: depositAmount,
          },
          nonce: 0,
          deadline: ethers.MaxUint256,
        };

        const transferDetails = {
          to: await magnifyWorldV3.getAddress(),
          requestedAmount: depositAmount,
        };

        // Mock signature (in real scenario this would be signed by the user)
        const signature = "0x";

        await expect(
          magnifyWorldV3
            .connect(user1)
            .depositWithPermit2(
              depositAmount,
              user1,
              permitTransferFrom,
              transferDetails,
              signature
            )
        )
          .to.emit(magnifyWorldV3, "Deposit")
          .withArgs(user1.address, user1.address, depositAmount, depositAmount);
      });
    });
  });

  describe("Loan Operations", function () {
    describe("Request Loan", function () {
      it("Should allow eligible users to request a loan", async function () {
        const { magnifyWorldV3, mockToken, owner } = await loadFixture(
          deployMagnifyWorldV3Fixture
        );

        // Move to start time
        await time.increaseTo(startTimestamp + 1);

        // Fund the contract
        await mockToken
          .connect(owner)
          .approve(magnifyWorldV3, loanAmount * BigInt(2));
        await magnifyWorldV3
          .connect(owner)
          .deposit(loanAmount * BigInt(2), owner);

        await expect(magnifyWorldV3.connect(owner).requestLoan())
          .to.emit(magnifyWorldV3, "LoanRequested")
          .withArgs(anyValue, owner.address, 0);

        // Verify loan state
        const loan = await magnifyWorldV3.getActiveLoan(owner.address);
        expect(loan.borrower).to.equal(owner.address);
        expect(loan.isActive).to.be.true;
        expect(loan.isDefault).to.be.false;
      });

      it("Should not allow loans during warmup period", async function () {
        const { magnifyWorldV3, owner } = await loadFixture(
          deployMagnifyWorldV3Fixture
        );

        await expect(
          magnifyWorldV3.connect(owner).requestLoan()
        ).to.be.revertedWithCustomError(magnifyWorldV3, "PoolNotActive");
      });

      it("Should not allow loans with insufficient tier", async function () {
        const { magnifyWorldV3, mockToken, user1 } = await loadFixture(
          deployMagnifyWorldV3Fixture
        );

        await time.increaseTo(startTimestamp + 1);

        await expect(
          magnifyWorldV3.connect(user1).requestLoan()
        ).to.be.revertedWithCustomError(magnifyWorldV3, "TierInsufficient");
      });
    });

    describe("Repay Loan", function () {
      it("Should allow loan repayment with permit2", async function () {
        const { magnifyWorldV3, mockToken, mockPermit2, owner } =
          await loadFixture(deployMagnifyWorldV3Fixture);

        // Setup and request loan
        await time.increaseTo(startTimestamp + 1);
        await mockToken
          .connect(owner)
          .approve(magnifyWorldV3, loanAmount * BigInt(2));
        await magnifyWorldV3
          .connect(owner)
          .deposit(loanAmount * BigInt(2), owner);
        await magnifyWorldV3.connect(owner).requestLoan();

        // Calculate repayment amount (loan + interest)
        const interest = (loanAmount * BigInt(loanInterest)) / BigInt(10000);
        const totalDue = loanAmount + interest;

        // Move time past loan period
        await time.increaseTo(startTimestamp + loanDuration + 1);

        // Create permit data
        const permitTransferFrom = {
          permitted: {
            token: await mockToken.getAddress(),
            amount: totalDue,
          },
          nonce: 0,
          deadline: ethers.MaxUint256,
        };

        const transferDetails = {
          to: await magnifyWorldV3.getAddress(),
          requestedAmount: totalDue,
        };

        const signature = "0x"; // Mock signature

        await expect(
          magnifyWorldV3
            .connect(owner)
            .repayLoanWithPermit2(
              permitTransferFrom,
              transferDetails,
              signature
            )
        )
          .to.emit(magnifyWorldV3, "LoanRepaid")
          .withArgs(anyValue, owner.address, 0);

        // Verify loan state
        const loan = await magnifyWorldV3.getActiveLoan(owner.address);
        expect(loan.isActive).to.be.false;
      });
    });

    describe("Process Outdated Loans", function () {
      it("Should mark expired loans as defaulted", async function () {
        const { magnifyWorldV3, mockToken, owner } = await loadFixture(
          deployMagnifyWorldV3Fixture
        );

        // Setup and request loan
        await time.increaseTo(startTimestamp + 1);
        await mockToken
          .connect(owner)
          .approve(magnifyWorldV3, loanAmount * BigInt(2));
        await magnifyWorldV3
          .connect(owner)
          .deposit(loanAmount * BigInt(2), owner);
        await magnifyWorldV3.connect(owner).requestLoan();

        // Move time past loan period
        await time.increaseTo(startTimestamp + loanDuration + SECONDS_PER_DAY);

        await expect(magnifyWorldV3.processOutdatedLoans())
          .to.emit(magnifyWorldV3, "LoanDefaulted")
          .withArgs(anyValue, owner.address, 0);

        // Verify loan state
        const loanHistory = await magnifyWorldV3.getLoanHistory(owner.address);
        expect(loanHistory[0].isDefault).to.be.true;
        expect(loanHistory[0].isActive).to.be.false;
      });

      it("Should handle multiple expired loans", async function () {
        const {
          magnifyWorldV3,
          magnifyWorldSoulboundNFT,
          mockToken,
          owner,
          users,
        } = await loadFixture(deployMagnifyWorldV3Fixture);

        // Setup for multiple users
        await time.increaseTo(startTimestamp + 1);
        const testUser = users[0];
        await magnifyWorldSoulboundNFT
          .connect(owner)
          .mintNFT(testUser.address, tier);

        // Fund contract
        await mockToken
          .connect(owner)
          .approve(magnifyWorldV3, loanAmount * BigInt(4));
        await magnifyWorldV3
          .connect(owner)
          .deposit(loanAmount * BigInt(4), owner);

        // Request loans
        await magnifyWorldV3.connect(owner).requestLoan();
        await magnifyWorldV3.connect(testUser).requestLoan();

        // Move time past loan period
        await time.increaseTo(startTimestamp + loanDuration + SECONDS_PER_DAY);

        // Process defaults
        await magnifyWorldV3.processOutdatedLoans();

        // Verify both loans are defaulted
        const activeLoans = await magnifyWorldV3.getAllActiveLoans();
        expect(activeLoans.length).to.equal(0);
      });
    });

    describe("Repay Defaulted Loan", function () {
      it("Should allow repayment of defaulted loan with permit2", async function () {
        const { magnifyWorldV3, mockToken, owner } = await loadFixture(
          deployMagnifyWorldV3Fixture
        );

        // Setup and request loan
        await time.increaseTo(startTimestamp + 1);
        await mockToken
          .connect(owner)
          .approve(magnifyWorldV3, loanAmount * BigInt(2));
        await magnifyWorldV3
          .connect(owner)
          .deposit(loanAmount * BigInt(2), owner);
        await magnifyWorldV3.connect(owner).requestLoan();

        // Move time past loan period and process default
        await time.increaseTo(startTimestamp + loanDuration + SECONDS_PER_DAY);
        await magnifyWorldV3.processOutdatedLoans();

        // Calculate total due (loan + interest + penalty)
        const interest = (loanAmount * BigInt(loanInterest)) / BigInt(10000);
        const penalty = (loanAmount * BigInt(1000)) / BigInt(10000); // 10% penalty
        const totalDue = loanAmount + interest + penalty;

        // Create permit data
        const permitTransferFrom = {
          permitted: {
            token: await mockToken.getAddress(),
            amount: totalDue,
          },
          nonce: 0,
          deadline: ethers.MaxUint256,
        };

        const transferDetails = {
          to: await magnifyWorldV3.getAddress(),
          requestedAmount: totalDue,
        };

        const signature = "0x"; // Mock signature

        await expect(
          magnifyWorldV3
            .connect(owner)
            .repayDefaultedLoanWithPermit2(
              0,
              permitTransferFrom,
              transferDetails,
              signature
            )
        )
          .to.emit(magnifyWorldV3, "LoanDefaultRepaid")
          .withArgs(anyValue, owner.address, 0);
      });
    });
  });
});
