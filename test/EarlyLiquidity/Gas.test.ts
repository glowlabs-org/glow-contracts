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
    const minerPool = await MinerPool.deploy(earlyLiquidity.address,mockGlow.address);
    await minerPool.deployed();
    await earlyLiquidity.setMinerPool(minerPool.address);
  await earlyLiquidity.setGlowToken(mockGlow.address);
  return { earlyLiquidity, mockUSDC, mockGlow, signer, other };
}

//--- TESTS ----
describe('Test: Early Liquidity', function () {
  it('Geometric series should not diverge past .01%', async function () {

      const { signer, earlyLiquidity, mockUSDC, mockGlow } = await stage();

        const ff = Array.from({length: 40}, () => 'f').join('');
        const maxUint128 = BigNumber.from(1).shl(128).sub(1)
        const arrayWith1000 = Array.from({length: 1000}, (_, i) => {
          return {
            address:  `0x${ff}`,
            w1: maxUint128,
            w2: maxUint128,
            
          }
        })

        const uint256Max = BigNumber.from(1).shl(256).sub(1)
        const arrSimple = Array.from({length: 1000}, (_, i) => uint256Max);
        
        //92 bytes


        await earlyLiquidity.emitEvent(arrSimple);
        
  });
});

