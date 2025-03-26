import { BaseContract, ContractTransactionResponse } from "ethers";
import { ethers, upgrades } from "hardhat";
import { mock } from "node:test";
import {
  MagnifyWorldV3,
  MagnifyWorldSoulboundNFT,
  MockERC20,
  MockPermit2,
} from "../typechain-types";

const NFT_NAME = "Magnify World Soulbound NFT";
const NFT_SYMBOL = "MAGNFT";
const NAME = "MagnifyWorldV3";
const SYMBOL = "MAGV3";
const OWNER = "0x6835939032900e5756abFF28903d8A5E68CB39dF";
const TREASURY_ADDRESS = "0x6835939032900e5756abFF28903d8A5E68CB39dF";
const DEV1 = "0x52d8e7777FFb0527C9181C386E183A0E5533401f";
const DEV2 = "0x6856355aA4321B88EaaECaD2dB05Ff9c92e69731";
const startTimestamp = Math.round(Date.now() / 1000) + (60 * 60 * 24); // 1 day
const endTimestamp = startTimestamp + 60 * 60 * 24 * 30; // 30 days
const loanAmount = ethers.parseUnits("10", 6); // 10 USDC
const loanDuration = 60 * 60 * 24 * 7; // 7 days
const loanInterest = 1000; // 10%
const tier = 3;

// https://docs.openzeppelin.com/contracts/2.x/api/token/erc20#IERC20
// https://docs.openzeppelin.com/contracts/4.x/api/token/erc20#ERC4626

async function deploy() {
  const MockToken = await ethers.getContractFactory("MockERC20");
  const mockToken = await MockToken.deploy("Mock Token", "MTK");
  await mockToken.waitForDeployment();
  console.log("MockToken deployed to:", await mockToken.getAddress());

  // Deploy mock Permit2
  const MockPermit2 = await ethers.getContractFactory("MockPermit2");
  const mockPermit2 = await MockPermit2.deploy();
  await mockPermit2.waitForDeployment();
  console.log("MockPermit2 deployed to:", await mockPermit2.getAddress());


  // Deploy MagnifyWorldSoulboundNFT contract
  const MagnifyWorldSoulboundNFT = await ethers.getContractFactory(
    "MagnifyWorldSoulboundNFT"
  );
  const magnifyWorldSoulboundNFT = await upgrades.deployProxy(
    MagnifyWorldSoulboundNFT,
    [NFT_NAME, NFT_SYMBOL]
  );
  await magnifyWorldSoulboundNFT.waitForDeployment();

  console.log(
    "MagnifyWorld SoulboundNFT deployed to:",
    await magnifyWorldSoulboundNFT.getAddress()
  );
  // Deploy V3 contract
  const MagnifyWorldV3 = await ethers.getContractFactory("MagnifyWorldV3");
  const magnifyWorldV3 = await upgrades.deployProxy(MagnifyWorldV3, [
    NAME,
    SYMBOL,
    await mockToken.getAddress(),
    await mockPermit2.getAddress(),
    await magnifyWorldSoulboundNFT.getAddress(),
    TREASURY_ADDRESS,
  ]);
  await magnifyWorldV3.waitForDeployment();
  console.log("MagnifyWorldV3 deployed to:", await magnifyWorldV3.getAddress());

  await (await magnifyWorldV3.setup(
    startTimestamp,
    endTimestamp,
    loanAmount,
    loanDuration,
    loanInterest,
    tier
  )).wait();

  console.log("Setup completed");
  return {
    magnifyWorldV3,
    magnifyWorldSoulboundNFT,
    mockToken,
    mockPermit2,
  };
}

async function setup(
  magnifyWorldV3: MagnifyWorldV3,
  magnifyWorldSoulboundNFT: MagnifyWorldSoulboundNFT,
  mockToken: MockERC20,
  mockPermit2: MockPermit2
) {
  // Mint tokens to user
  const mintAmount = ethers.parseUnits("1000", 6); // Assuming 6 decimals
  await (await mockToken.mint(OWNER, mintAmount)).wait();

  // mint owner nft
  await (await magnifyWorldSoulboundNFT.mintNFT(OWNER, 99)).wait();
  await (await magnifyWorldSoulboundNFT.mintNFT(DEV1, 3)).wait();
  await (await magnifyWorldSoulboundNFT.mintNFT(DEV2, 3)).wait();

  // set admins
  await (await magnifyWorldSoulboundNFT.setAdmin(DEV1, true)).wait();
  await (await magnifyWorldSoulboundNFT.setAdmin(DEV2, true)).wait();

  await (await mockToken.approve(await magnifyWorldV3.getAddress(), mintAmount)).wait();
  await (await magnifyWorldV3.deposit(mintAmount, OWNER)).wait();

  console.log("balance of loan lp:", await magnifyWorldV3.balanceOf(OWNER));
  console.log("value of loan lp:", await magnifyWorldV3.convertToAssets(await magnifyWorldV3.balanceOf(OWNER)));
  await (await mockToken.mint(await magnifyWorldV3.getAddress(), mintAmount)).wait();
  console.log("value of loan lp:", await magnifyWorldV3.convertToAssets(await magnifyWorldV3.balanceOf(OWNER)));

}

async function main() {
  const {
    magnifyWorldV3,
    magnifyWorldSoulboundNFT,
    mockToken,
    mockPermit2,
  } = await deploy();

  await setup(
    magnifyWorldV3,
    magnifyWorldSoulboundNFT,
    mockToken,
    mockPermit2
  );
}

// Execute the deployment
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
