import { expect } from 'chai';
import { ethers } from 'hardhat';
import * as dotenv from 'dotenv';
import { BigNumber } from 'ethers';
dotenv.config();
import * as fs from 'fs';

//-------- ENVIRONMENT VARIABLES ------------
const FUZZ_RUNS: number = parseInt(process.env.EARLY_LIQUIDITY_NUM_RUNS!);
const DEPTH_PER_RUN = parseInt(process.env.EARLY_LIQUIDITY_DEPTH_PER_RUN!);
const SAVE_EARLY_LIQUIDITY_RUNS =
  process.env.SAVE_EARLY_LIQUIDITY_RUNS!.toLowerCase() === 'true';

//---- CONSTANTS ------
const USDC_DECIMALS = 6;
const STARTING_USDC_BALANCE = BigNumber.from(10)
  .pow(USDC_DECIMALS)
  .mul(1_000_000_000_000);
const MAX_DIVERGENCE_PERCENT_E5 = 100.0; //.01% , 1% would be 10000

//--- CSV HEADERS ---
/**
 * @dev only applicable if SAVE_EARLY_LIQUIDITY_RUNS is true
 */
const csvHeaders = [
  'totalTokensSoldBefore',
  'tokensToBuy',
  'totalCostFromContract',
  'totalCostLocal',
  'diverges',
  'divergenceAmount',
  'divergencePercent',
];


type ClaimLeaf = {
  address:string,
  w1:string,
  w2:string,
}

/***
 * @dev staging function to deploy contracts and mint USDC to the signer.
 * @dev useful when running fuzzing tests to reset the state of the contracts on each run.
 */

async function stage() {
  const [signer, other] = await ethers.getSigners();

  //Deploy contracts
  const MockUSDC = await ethers.getContractFactory('MockUSDC');
  const mockUSDC = await MockUSDC.deploy();
  await mockUSDC.deployed();

  // Mint USDC to signer
  await mockUSDC.mint(signer.address, STARTING_USDC_BALANCE);
  const EarlyLiquidity = await ethers.getContractFactory('EarlyLiquidity');
  const earlyLiquidity = await EarlyLiquidity.deploy(mockUSDC.address);
  await earlyLiquidity.deployed();
  const MockGlow = await ethers.getContractFactory('TestGLOW');
  //Random vesting contract address
  const vestingContractPlaceholderAddress =
  '0x591749484BFb1737473bf1E7Bb453257BdA452A9';
  const mockGlow = await MockGlow.deploy(
    earlyLiquidity.address,
    vestingContractPlaceholderAddress,
    );
    await mockGlow.deployed();

    //----------------- DEPLOY MINER POOL -----------------
    const MinerPool = await ethers.getContractFactory('EarlyLiquidityMockMinerPool');
    const minerPool = await MinerPool.deploy(earlyLiquidity.address,mockGlow.address,mockUSDC.address);
    await minerPool.deployed();
    await earlyLiquidity.setMinerPool(minerPool.address);
  await earlyLiquidity.setGlowToken(mockGlow.address);
  return { earlyLiquidity, mockUSDC, mockGlow, signer, other,minerPool };
}

//--- TESTS ----
describe('Verifying Typed Data', function () {
  it('Typed data in ethers should match', async function () {
      const {minerPool,signer,mockUSDC} = await stage();
      const chainId = await signer.getChainId();
      console.log(`ChainId: ${chainId}`)
    const domain = {
      name: 'GCA and MinerPool',
      version: '1',
      chainId: chainId,
      verifyingContract: minerPool.address,
    };

    const types = {
        ClaimRewardFromBucket: [
            {
                "name": "bucketId",
                "type": "uint256"
            },
            {
                "name":"glwWeight",
                "type":"uint256"
            },
            {
                "name":"grcWeight",
                "type":"uint256"
            },
            {
                "name":"index",
                "type":"uint256"
            },
            {
                "name":"grcTokens",
                "type":"address[]"
            },
            {
                "name":"claimFromInflation",
                "type":"bool"
            }
        ]
    }
    
    const data = {
        bucketId:1,
        glwWeight:1,
        grcWeight:1,
        index:1,
        grcTokens:[mockUSDC.address],
        claimFromInflation:true
    }
    const signatureFromEthers = await signer._signTypedData(domain, types, data);
    console.log(signatureFromEthers);
    const hashFromContract = await minerPool.createClaimRewardFromBucketDigest(
        data.bucketId,
        data.glwWeight,
        data.grcWeight,
        data.index,
        data.grcTokens,
        data.claimFromInflation
    );

  });
});

//From Ethers: 0x707a693f3f53ea7d9618f238578b86e228f1a6c79ef995830ed91420c24dca1c5c61a611177a45857c79848fd6092263a9191dcc31a02668ddbd82b2838ad3561b
