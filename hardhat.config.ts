import { HardhatUserConfig } from "hardhat/config";
import '@openzeppelin/hardhat-upgrades';
import 'solidity-docgen';
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
      url: process.env.WORLD_CHAIN_SEPOLIA_RPC,
      accounts: [process.env.WALLET_PRIVATE_KEY],
      gasPrice: 1100250,
    },
    worldChainMainnet: {
      chainId: 480,
      url: process.env.WORLD_CHAIN_RPC,
      accounts: [process.env.WALLET_PRIVATE_KEY],
    },
  },
  docgen: {
    pages: 'files'
  },
  etherscan: {
    apiKey: {
      worldchainSepolia: process.env.WORLD_SCAN_KEY || "",
      worldchain: process.env.WORLD_SCAN_KEY || "",
    },
    customChains: [
      {
        network: "worldchainSepolia",
        chainId: 4801,
        urls: {
          apiURL: "https://api-sepolia.worldscan.org/api",
          browserURL: "https://sepolia.worldscan.org/"
        }
      },
      {
        network: "worldchain",
        chainId: 480,
        urls: {
          apiURL: "https://api.worldscan.org/api",
          browserURL: "https://worldscan.org/"
        }
      }

    ]
  }
};

export default config;
