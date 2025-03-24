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
const OWNER = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
const TREASURY_ADDRESS = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
const startTimestamp = Math.round(Date.now() / 1000) + 60;
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

  // Deploy mock Permit2
  const MockPermit2 = await ethers.getContractFactory("MockPermit2");
  const mockPermit2 = await MockPermit2.deploy();

  // Get the contract factory
  const MagnifyWorldV1 = await ethers.getContractFactory(
    "contracts/MagnifyWorldV1.sol:MagnifyWorld"
  );
  const magnifyWorldV1 = await MagnifyWorldV1.deploy(
    await mockToken.getAddress(),
    await mockPermit2.getAddress()
  );
  await magnifyWorldV1.waitForDeployment();

  // Deploy MagnifyWorldSoulboundNFT contract
  const MagnifyWorldSoulboundNFT = await ethers.getContractFactory(
    "MagnifyWorldSoulboundNFT"
  );
  const magnifyWorldSoulboundNFT = await upgrades.deployProxy(
    MagnifyWorldSoulboundNFT,
    [NFT_NAME, NFT_SYMBOL]
  );
  await magnifyWorldSoulboundNFT.waitForDeployment();
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

  await magnifyWorldV3.setup(
    startTimestamp,
    endTimestamp,
    loanAmount,
    loanDuration,
    loanInterest,
    tier
  );

  console.log("MockToken deployed to:", await mockToken.getAddress());
  console.log("MockPermit2 deployed to:", await mockPermit2.getAddress());
  console.log("MagnifyWorldV1 deployed to:", await magnifyWorldV1.getAddress());
  console.log(
    "MagnifyWorld SoulboundNFT deployed to:",
    await magnifyWorldSoulboundNFT.getAddress()
  );
  console.log("MagnifyWorldV3 deployed to:", await magnifyWorldV3.getAddress());
  return {
    magnifyWorldV1,
    magnifyWorldV3,
    magnifyWorldSoulboundNFT,
    mockToken,
    mockPermit2,
  };
}

async function setup(
  magnifyWorldV1: BaseContract,
  magnifyWorldV3: MagnifyWorldV3,
  magnifyWorldSoulboundNFT: MagnifyWorldSoulboundNFT,
  mockToken: MockERC20,
  mockPermit2: MockPermit2
) {
  // Mint tokens to user
  const mintAmount = ethers.parseUnits("1000", 6); // Assuming 6 decimals
  await mockToken.mint(OWNER, mintAmount);

  // mint owner nft
  await magnifyWorldSoulboundNFT.mintNFT(OWNER, 99);

  await mockToken.approve(await mockPermit2.getAddress(), ethers.MaxUint256);
  const { permitTransfer, transferDetails } = await getPermit2Params(
    mockToken,
    await magnifyWorldV3.getAddress(),
    mintAmount.toString()
  );
  await magnifyWorldV3.depositWithPermit2(
    mintAmount,
    OWNER,
    permitTransfer,
    transferDetails,
    "0x0001"
  );

  console.log("balance of loan lp:", await magnifyWorldV3.balanceOf(OWNER));
  console.log(
    "value of loan lp:",
    await magnifyWorldV3.convertToAssets(await magnifyWorldV3.balanceOf(OWNER))
  );
  await mockToken.mint(await magnifyWorldV3.getAddress(), mintAmount);
  console.log(
    "value of loan lp:",
    await magnifyWorldV3.convertToAssets(await magnifyWorldV3.balanceOf(OWNER))
  );
}

async function getPermit2Params(token: MockERC20, to: string, amount: string) {
  const deadline = Math.floor((Date.now() + 30 * 60 * 1000) / 1000).toString();

  const permitTransfer = {
    permitted: {
      token: await token.getAddress(),
      amount: amount,
    },
    nonce: Date.now().toString(),
    deadline,
  };

  const transferDetails = {
    to: to,
    requestedAmount: amount,
  };

  return { permitTransfer, transferDetails };
}

async function main() {
  const {
    magnifyWorldV1,
    magnifyWorldV3,
    magnifyWorldSoulboundNFT,
    mockToken,
    mockPermit2,
  } = await deploy();

  await setup(
    magnifyWorldV1,
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
