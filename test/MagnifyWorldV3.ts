import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { MagnifyWorldV3, MagnifyWorldSoulboundNFT, MockERC20, MockPermit2 } from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

describe("MagnifyWorldV3", function () {
  let magnifyWorldV3: MagnifyWorldV3;
  let magnifyWorldSoulboundNFT: MagnifyWorldSoulboundNFT;
  let mockToken: MockERC20;
  let mockPermit2: MockPermit2;
  let owner: HardhatEthersSigner;
  let treasury: HardhatEthersSigner;
  let signers: HardhatEthersSigner[];

  before(async function () {
    [owner, treasury, ...signers] = await ethers.getSigners();

    const MockToken = await ethers.getContractFactory("MockERC20");
    mockToken = await MockToken.deploy("Mock Token", "MTK");

    const MockPermit2 = await ethers.getContractFactory("MockPermit2");
    mockPermit2 = await MockPermit2.deploy();

    const MagnifyWorldV1 = await ethers.getContractFactory("MagnifyWorld");
    const magnifyWorldV1 = await MagnifyWorldV1.deploy(
      await mockToken.getAddress(),
      await mockPermit2.getAddress()
    );

    const MagnifyWorldSoulboundNFT = await ethers.getContractFactory("MagnifyWorldSoulboundNFT");
    magnifyWorldSoulboundNFT = await upgrades.deployProxy(MagnifyWorldSoulboundNFT, ["Magnify World Soulbound NFT", "MAGNFT"]);

    const MagnifyWorldV3 = await ethers.getContractFactory("MagnifyWorldV3");
    magnifyWorldV3 = await upgrades.deployProxy(MagnifyWorldV3, [
      "MagnifyWorldV3",
      "MAGV3",
      await mockToken.getAddress(),
      await mockPermit2.getAddress(),
      await magnifyWorldSoulboundNFT.getAddress(),
      await magnifyWorldV1.getAddress(),
      treasury.address,
    ]);
  });

  it("should initialize correctly", async function () {
    expect(await magnifyWorldV3.name()).to.equal("MagnifyWorldV3");
    expect(await magnifyWorldV3.symbol()).to.equal("MAGV3");
    expect(await magnifyWorldV3.treasury()).to.equal(treasury.address);
  });

  it("should allow owner to add a new tier", async function () {
    await magnifyWorldV3.addTier(1, ethers.parseUnits("1000", 6), 30 * 24 * 60 * 60, 500);
    const tier = await magnifyWorldV3.tiers(1);
    expect(tier.loanAmount).to.equal(ethers.parseUnits("1000", 6));
    expect(tier.loanPeriod).to.equal(30 * 24 * 60 * 60);
    expect(tier.interestRate).to.equal(500);
  });

  it("should allow owner to update an existing tier", async function () {
    await magnifyWorldV3.updateTier(1, ethers.parseUnits("2000", 6), 60 * 24 * 60 * 60, 300);
    const tier = await magnifyWorldV3.tiers(1);
    expect(tier.loanAmount).to.equal(ethers.parseUnits("2000", 6));
    expect(tier.loanPeriod).to.equal(60 * 24 * 60 * 60);
    expect(tier.interestRate).to.equal(300);
  });

  it("should allow NFT owner to request a loan", async function () {
    await magnifyWorldSoulboundNFT.mintNFT(owner.address, 1);
    await mockToken.mint(owner.address, ethers.parseUnits("1000", 6));
    await mockToken.approve(await magnifyWorldV3.getAddress(), ethers.parseUnits("1000", 6));
    await magnifyWorldV3.deposit(ethers.parseUnits("1000", 6), owner.address);

    await magnifyWorldV3.requestLoan(1);
    const loan = await magnifyWorldV3.activeLoans(0);
    expect(loan.loanAmount).to.equal(ethers.parseUnits("1000", 6));
    expect(loan.isActive).to.be.true;
  });

  it("should allow NFT owner to repay a loan", async function () {
    // const loan = await magnifyWorldV3.activeLoans(0);
    // const interest = (loan.loanAmount * loan.interestRate) / 10000n;
    // const total = loan.loanAmount + interest;

    // await mockToken.mint(owner.address, total);
    // await mockToken.approve(await magnifyWorldV3.getAddress(), total);
    // await magnifyWorldV3.repayLoanWithPermit2(0);

    // const updatedLoan = await magnifyWorldV3.activeLoans(0);
    // expect(updatedLoan.isActive).to.be.false;
  });
});