import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import dotenv from "dotenv";

dotenv.config();

if (!process.env.WALLET_PRIVATE_KEY) {
  console.error("WALLET_PRIVATE_KEY is not set");
  throw new Error("WALLET_PRIVATE_KEY is not set");
}

const config: HardhatUserConfig = {
  solidity: "0.8.28",
  networks: {
    worldChainTestnet: {
      chainId: 4801,
      url: "https://worldchain-sepolia.g.alchemy.com/public",
      accounts: [process.env.WALLET_PRIVATE_KEY],
    },
  },
};

export default config;
