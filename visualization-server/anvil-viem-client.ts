export const contracts = {
  gca: '0x610178dA211FEF7D417bC0e6FeD39F05609AD788',
  multicall3: '0xA51c1fc2f0D1a1b8494Ed1FE312d7C3a78Ed91C0',
};

export const ANVIL_URL = 'http://127.0.0.1:8545';

import {
  ChainContract,
  createTestClient,
  defineChain,
  http,
  publicActions,
  walletActions,
} from 'viem';
import { privateKeyToAccount } from 'viem/accounts';

export const foundry = /*#__PURE__*/ defineChain({
  id: 31_337,
  name: 'Foundry',
  contracts: {
    multicall3: {
      address: contracts.multicall3,
      blockCreated: 1,
    } as ChainContract,
  },
  nativeCurrency: {
    decimals: 18,
    name: 'Ether',
    symbol: 'ETH',
  },
  rpcUrls: {
    default: {
      http: ['http://127.0.0.1:8545'],
      webSocket: ['ws://127.0.0.1:8545'],
    },
  },
});

export const getAnvilClient = () => {
  const providerUrl = ANVIL_URL;
  const client = createTestClient({
    chain: foundry,
    mode: 'anvil',
    account: privateKeyToAccount(
      `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`,
    ),
    transport: http(providerUrl),
  })
    .extend(publicActions)
    .extend(walletActions);

  return client;
};
