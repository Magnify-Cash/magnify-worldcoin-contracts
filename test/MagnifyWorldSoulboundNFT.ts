import {
    time,
    loadFixture,
  } from "@nomicfoundation/hardhat-toolbox/network-helpers";
  import { expect } from "chai";
  import { ethers, upgrades } from "hardhat";
  
  const NFT_NAME = "Magnify World Soulbound NFT";
  const NFT_SYMBOL = "MAGNFT";
  
  describe("MagnifyWorldSoulboundNFT", function () {
    // Fixture to deploy contract and set up initial state
    async function deploySoulboundNFTFixture() {
      const [owner, user1, user2, admin, ...users] = await ethers.getSigners();
  
      const MagnifyWorldSoulboundNFT = await ethers.getContractFactory(
        "MagnifyWorldSoulboundNFT"
      );
      const soulboundNFT = await upgrades.deployProxy(MagnifyWorldSoulboundNFT, [
        NFT_NAME,
        NFT_SYMBOL,
      ]);
  
      return { soulboundNFT, owner, user1, user2, admin, users };
    }
  
    describe("Initialization", function () {
      it("Should initialize with correct name and symbol", async function () {
        const { soulboundNFT } = await loadFixture(deploySoulboundNFTFixture);
  
        expect(await soulboundNFT.name()).to.equal(NFT_NAME);
        expect(await soulboundNFT.symbol()).to.equal(NFT_SYMBOL);
      });
  
      it("Should set deployer as admin", async function () {
        const { soulboundNFT, owner } = await loadFixture(deploySoulboundNFTFixture);
  
        expect(await soulboundNFT.admins(owner.address)).to.be.true;
      });
    });
  
    describe("Admin Management", function () {
      it("Should allow owner to set new admin", async function () {
        const { soulboundNFT, owner, admin } = await loadFixture(
          deploySoulboundNFTFixture
        );
  
        await soulboundNFT.connect(owner).setAdmin(admin.address, true);
        expect(await soulboundNFT.admins(admin.address)).to.be.true;
      });
  
      it("Should allow owner to remove admin", async function () {
        const { soulboundNFT, owner, admin } = await loadFixture(
          deploySoulboundNFTFixture
        );
  
        await soulboundNFT.connect(owner).setAdmin(admin.address, true);
        await soulboundNFT.connect(owner).setAdmin(admin.address, false);
        expect(await soulboundNFT.admins(admin.address)).to.be.false;
      });
  
      it("Should not allow non-owner to set admin", async function () {
        const { soulboundNFT, user1, admin } = await loadFixture(
          deploySoulboundNFTFixture
        );
  
        await expect(
          soulboundNFT.connect(user1).setAdmin(admin.address, true)
        ).to.be.revertedWithCustomError(soulboundNFT, "OwnableUnauthorizedAccount");
      });
    });
  
    describe("NFT Minting", function () {
      it("Should allow admin to mint NFT", async function () {
        const { soulboundNFT, owner, user1 } = await loadFixture(
          deploySoulboundNFTFixture
        );
  
        await soulboundNFT.connect(owner).mintNFT(user1.address, 1);
        expect(await soulboundNFT.balanceOf(user1.address)).to.equal(1);
        expect(await soulboundNFT.userToId(user1.address)).to.equal(1);
      });
  
      it("Should not allow non-admin to mint NFT", async function () {
        const { soulboundNFT, user1 } = await loadFixture(deploySoulboundNFTFixture);
  
        await expect(
          soulboundNFT.connect(user1).mintNFT(user1.address, 1)
        ).to.be.revertedWithCustomError(soulboundNFT, "CallerNotAdmin");
      });
  
      it("Should not allow minting multiple NFTs to same address", async function () {
        const { soulboundNFT, owner, user1 } = await loadFixture(
          deploySoulboundNFTFixture
        );
  
        await soulboundNFT.connect(owner).mintNFT(user1.address, 1);
        await expect(
          soulboundNFT.connect(owner).mintNFT(user1.address, 1)
        ).to.be.revertedWithCustomError(soulboundNFT, "AlreadyOwnedNFT");
      });
    });
  
    describe("NFT Data Management", function () {
      it("Should correctly store and retrieve NFT data", async function () {
        const { soulboundNFT, owner, user1 } = await loadFixture(
          deploySoulboundNFTFixture
        );
  
        await soulboundNFT.connect(owner).mintNFT(user1.address, 2);
        const tokenId = await soulboundNFT.userToId(user1.address);
        
        const nftData = await soulboundNFT.getNFTData(tokenId);
        expect(nftData.tier).to.equal(2);
        expect(nftData.owner).to.equal(user1.address);
        expect(nftData.loansRepaid).to.equal(0);
        expect(nftData.loansDefaulted).to.equal(0);
        expect(nftData.ongoingLoan).to.be.false;
      });
  
      it("Should allow admin to upgrade tier", async function () {
        const { soulboundNFT, owner, user1 } = await loadFixture(
          deploySoulboundNFTFixture
        );
  
        await soulboundNFT.connect(owner).mintNFT(user1.address, 1);
        const tokenId = await soulboundNFT.userToId(user1.address);
        
        await soulboundNFT.connect(owner).upgradeTier(tokenId, 2);
        const nftData = await soulboundNFT.getNFTData(tokenId);
        expect(nftData.tier).to.equal(2);
      });
  
      it("Should track loan repayments correctly", async function () {
        const { soulboundNFT, owner, user1 } = await loadFixture(
          deploySoulboundNFTFixture
        );
  
        await soulboundNFT.connect(owner).mintNFT(user1.address, 1);
        const tokenId = await soulboundNFT.userToId(user1.address);
        
        await soulboundNFT.connect(owner).increaseloanRepayment(tokenId, 1000);
        const nftData = await soulboundNFT.getNFTData(tokenId);
        expect(nftData.loansRepaid).to.equal(1);
        expect(nftData.interestPaid).to.equal(1000);
      });
  
      it("Should track loan defaults correctly", async function () {
        const { soulboundNFT, owner, user1 } = await loadFixture(
          deploySoulboundNFTFixture
        );
  
        await soulboundNFT.connect(owner).mintNFT(user1.address, 1);
        const tokenId = await soulboundNFT.userToId(user1.address);
        
        await soulboundNFT.connect(owner).increaseLoanDefault(tokenId, 1000);
        let nftData = await soulboundNFT.getNFTData(tokenId);
        expect(nftData.loansDefaulted).to.equal(1000);
  
        await soulboundNFT.connect(owner).decreaseLoanDefault(tokenId, 500);
        nftData = await soulboundNFT.getNFTData(tokenId);
        expect(nftData.loansDefaulted).to.equal(500);
      });
    });
  
    describe("Soulbound Functionality", function () {
      it("Should not allow NFT transfer", async function () {
        const { soulboundNFT, owner, user1, user2 } = await loadFixture(
          deploySoulboundNFTFixture
        );
  
        await soulboundNFT.connect(owner).mintNFT(user1.address, 1);
        const tokenId = await soulboundNFT.userToId(user1.address);
  
        await expect(
          soulboundNFT.connect(user1).transferFrom(user1.address, user2.address, tokenId)
        ).to.be.revertedWithCustomError(soulboundNFT, "SoulboundTransferNotAllowed");
      });
    });
  
    describe("Pool Management", function () {
      it("Should allow admin to add magnify pool", async function () {
        const { soulboundNFT, owner } = await loadFixture(deploySoulboundNFTFixture);
  
        // Deploy mock pool
        const MockPool = await ethers.getContractFactory("MockMagnifyWorldV3");
        const mockPool = await MockPool.deploy();
  
        await soulboundNFT.connect(owner).addMagnifyPool(await mockPool.getAddress());
        
        const pools = await soulboundNFT.getMagnifyPools();
        expect(pools.length).to.equal(1);
        expect(pools[0]).to.equal(await mockPool.getAddress());
      });
  
      it("Should not allow non-admin to add pool", async function () {
        const { soulboundNFT, user1 } = await loadFixture(deploySoulboundNFTFixture);
  
        const MockPool = await ethers.getContractFactory("MockMagnifyWorldV3");
        const mockPool = await MockPool.deploy();
  
        await expect(
          soulboundNFT.connect(user1).addMagnifyPool(await mockPool.getAddress())
        ).to.be.revertedWithCustomError(soulboundNFT, "CallerNotAdmin");
      });
    });
  });
  