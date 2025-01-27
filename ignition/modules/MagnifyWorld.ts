// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import dotenv from "dotenv";

dotenv.config();

const MagnifyWorldModule = buildModule("MagnifyWorldModule", (m) => {
  // Check for required environment variables
  if (!process.env.LOAN_TOKEN_ADDRESS) {
    console.error("Error: LOAN_TOKEN_ADDRESS environment variable is not set");
    throw new Error("LOAN_TOKEN_ADDRESS environment variable is required");
  }

  if (!process.env.PERMIT2_ADDRESS) {
    console.error("Error: PERMIT2_ADDRESS environment variable is not set");
    throw new Error("PERMIT2_ADDRESS environment variable is required");
  }

  const loanToken = m.getParameter("loanToken", process.env.LOAN_TOKEN_ADDRESS);
  const permit2 = m.getParameter("permit2", process.env.PERMIT2_ADDRESS);

  const magnifyWorld = m.contract("MagnifyWorld", [loanToken, permit2]);

  return { magnifyWorld };
});

export default MagnifyWorldModule;
