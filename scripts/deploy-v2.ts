import { ethers } from "hardhat";

async function main() {
  // Get the contract factory
  const MagnifyWorldV2 = await ethers.getContractFactory("contracts/MagnifyWorldV2.sol:MagnifyWorldV2");

  // Get the V1 contract address from environment or configuration
  // Replace this with your actual V1 contract address
  const v1ContractAddress = "0x4E52d9e8d2F70aD1805084BA4fa849dC991E7c88";
  
  if (!v1ContractAddress) {
    throw new Error("V1 contract address not provided. Set MAGNIFY_WORLD_V1_ADDRESS in environment variables.");
  }

  console.log("Deploying MagnifyWorldV2...");
  console.log("V1 Contract Address:", v1ContractAddress);

  // Deploy the contract
  const magnifyWorldV2 = await MagnifyWorldV2.deploy(v1ContractAddress);
  await magnifyWorldV2.waitForDeployment();

  const address = await magnifyWorldV2.getAddress();
  console.log("MagnifyWorldV2 deployed to:", address);

  // Verify the deployment parameters
  console.log("\nVerifying deployment parameters:");
  const v1Address = await magnifyWorldV2.v1();
  const loanTokenAddress = await magnifyWorldV2.loanToken();
  const permit2Address = await magnifyWorldV2.PERMIT2();

  console.log("V1 Contract:", v1Address);
  console.log("Loan Token:", loanTokenAddress);
  console.log("PERMIT2:", permit2Address);
}

// Execute the deployment
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
