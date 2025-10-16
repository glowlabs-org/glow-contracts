import type { HardhatUserConfig } from "hardhat/config";

import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { configVariable } from "hardhat/config";
import hardhatViem from "@nomicfoundation/hardhat-viem";
import networkHelpers from "@nomicfoundation/hardhat-network-helpers";
const config: HardhatUserConfig = {
  plugins: [hardhatViem,hardhatToolboxViemPlugin,networkHelpers],
  paths: {
    sources: "./src/",
  },
  solidity: {
    profiles: {
      default: {
        version: "0.8.28",
      },
      production: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    },
  },
  networks: {
    hardhatMainnet: {
      type: "edr-simulated",
      chainType: "l1",
    
    },
    hardhatMainnetFork: {
      type: "edr-simulated",
      chainType: "l1",
      forking : {
        url: "https://eth-mainnet.g.alchemy.com/v2/dK_eaVLATMhv_n7dCGHZvqh8HOHuqE9u",
        blockNumber: 23549083,
      },
    },
    hardhatOp: {
      type: "edr-simulated",
      chainType: "op",
    },
    eth_mainnet: {
      type: "http",
      chainType: "l1",
      chainId:1,
      url: "https://eth-mainnet.g.alchemy.com/v2/dK_eaVLATMhv_n7dCGHZvqh8HOHuqE9u",
      accounts: ["0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"],
    },
    sepolia: {
      type: "http",
      chainType: "l1",
      url: configVariable("SEPOLIA_RPC_URL"),
      accounts: [configVariable("SEPOLIA_PRIVATE_KEY")],
    },
  },
};

export default config;
