import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import dotenv from "dotenv";

dotenv.config();

if (!process.env.WALLET_PRIVATE_KEY) {
  console.error("WALLET_PRIVATE_KEY is not set");
  throw new Error("WALLET_PRIVATE_KEY is not set");
}

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 20000,
          },
        },
      }
    ],
  },
  networks: {
    worldChainTestnet: {
      chainId: 4801,
      url: "https://worldchain-sepolia.g.alchemy.com/public",
      accounts: [process.env.WALLET_PRIVATE_KEY],
    },
    worldChainMainnet: {
      chainId: 480,
      url: "https://worldchain-mainnet.g.alchemy.com/v2/Gpk_py-r1-t6krNnNdpMntaAxXb3GfUq",
      accounts: [process.env.WALLET_PRIVATE_KEY],
    },
  },
};

export default config;
