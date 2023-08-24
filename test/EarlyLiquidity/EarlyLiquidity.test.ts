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
    //Setup the number of fuzz runs counter
    let numRunsCounter: number = 0;

    //While loop to run the fuzzing tests
    while (numRunsCounter < FUZZ_RUNS) {
      //Stage the contracts on each run
      const { signer, earlyLiquidity, mockUSDC, mockGlow } = await stage();

      //Approve spending of USDC
      await mockUSDC.approve(earlyLiquidity.address, STARTING_USDC_BALANCE);

      //Setup CSV data, only applicable if SAVE_EARLY_LIQUIDITY_RUNS is true
      const csvData = [];

      //Setup the total tokens sold counter
      let totalTokensSold = 0;

      for (let i = 0; i < DEPTH_PER_RUN; ++i) {
        //Find the balance before
        //We use this to ensure that the fuzz value doesen't surpass the balance of the contract
        const earlyLiquidityGlowBalanceBN = await mockGlow.balanceOf(
          earlyLiquidity.address,
        );

        //ensure mod 1e18 is 0 to make sure all inputs are correct
        expect(
          earlyLiquidityGlowBalanceBN.mod(BigNumber.from(10).pow(18)),
        ).to.equal(0);

        //Divide by 1e18 to ensure that floating point math doesen't break in the contract
        const earlyLiquidityGlowBalanceDiv1e18 =
          earlyLiquidityGlowBalanceBN.div(BigNumber.from(10).pow(18));

        ///If all tokens have been sold, we can exit
        if (earlyLiquidityGlowBalanceBN.eq(0)) {
          break;
        }
        /// Get the fuzz input from the random number generator
        const tokensToBuy = getRandomBigNumberWithUpperBound(
          earlyLiquidityGlowBalanceDiv1e18,
        );

        //Get the price from the contract
        const totalCostFromContract =
          await earlyLiquidity.getPrice(tokensToBuy);

        //Get the price from the local function
        const totalCostLocal = getPriceOfTokens(
          totalTokensSold,
          tokensToBuy.toNumber(),
        );

        //Expect the abs(difference) of the difference to be less than the max diverence
        const diverges = divergeMoreThanDivergencePercent(
          totalCostFromContract,
          totalCostLocal,
        );
        if (diverges) {
          console.log(`expected ${totalCostLocal.toString()} USDC`);
          console.log(`got ${totalCostFromContract.toString()} USDC`);
          console.log(
            `Diverged by ${totalCostFromContract
              .sub(totalCostLocal)
              .abs()
              .toString()} USDC`,
          );
        }
        const message = `Diverged by ${totalCostFromContract}`;
        //We should never diverge more than the max divergence percent
        expect(diverges).to.equal(false, message);

        const signerGlowBalanceBefore = await mockGlow.balanceOf(
          signer.address,
        );
        const signerUSDCBalanceBefore = await mockUSDC.balanceOf(
          signer.address,
        );
        const earlyLiquidityGlowBalanceBefore = await mockGlow.balanceOf(
          earlyLiquidity.address,
        );
        //This should be sent to the miner pool
        // const earlyLiquidityUSDCBalanceBefore = await mockUSDC.balanceOf(earlyLiquidity.address);

        const divergenceValue = totalCostFromContract
          .sub(totalCostLocal)
          .abs()
          .toNumber();
        let expectedValue = totalCostLocal.toNumber();
        if (expectedValue === 0) {
          expectedValue = 1;
        }
        const divergencePercent = divergenceValue / expectedValue;
        if (SAVE_EARLY_LIQUIDITY_RUNS) {
          //Save the data to the csv
          csvData.push([
            totalTokensSold,
            tokensToBuy.toString(),
            totalCostFromContract.toString(),
            totalCostLocal.toString(),
            diverges,
            totalCostFromContract.sub(totalCostLocal).abs().toString(),
            //divergence percent
            `${divergencePercent}%`,
          ]);
        }
        //Purchase the tokens
        await earlyLiquidity.buy(
          ethers.utils.parseEther(`${tokensToBuy}`),
          totalCostFromContract,
        );
        totalTokensSold += tokensToBuy.toNumber();
        const signerGlowBalanceAfter = await mockGlow.balanceOf(signer.address);
        const signerUSDCBalanceAfter = await mockUSDC.balanceOf(signer.address);
        const earlyLiquidityGlowBalanceAfter = await mockGlow.balanceOf(
          earlyLiquidity.address,
        );

        //Reconvert the tokens to 1e18 to readjust for the floating point math adjustment
        expect(signerGlowBalanceAfter.sub(signerGlowBalanceBefore)).to.equal(
          tokensToBuy.mul(BigNumber.from(10).pow(18)),
        );
        expect(signerUSDCBalanceBefore.sub(signerUSDCBalanceAfter)).to.equal(
          totalCostFromContract,
        );
        expect(
          earlyLiquidityGlowBalanceBefore.sub(earlyLiquidityGlowBalanceAfter),
        ).to.equal(tokensToBuy.mul(BigNumber.from(10).pow(18)));
      }

      const allEvents  = await earlyLiquidity.queryFilter(earlyLiquidity.filters['Purchase(address,uint256,uint256)']());
      // console.log(allEvents);
      fs.writeFileSync("events.json", JSON.stringify(allEvents, null, 4));
      if (SAVE_EARLY_LIQUIDITY_RUNS) {
        //Generate a random id to save the data to
        const RANDOM_ID = Math.floor(Math.random() * 1000000);
        //Save the data from the run to a csv
        fs.writeFileSync(
          `./test/EarlyLiquidity/data/${RANDOM_ID}.csv`,
          csvHeaders.join(',') +
            '\n' +
            csvData.map((row) => row.join(',')).join('\n'),
        );
      }

      //Increment the number of runs counter
      ++numRunsCounter;
    }
  });
});

//----------------- HELPER FUNCTIONS -----------------

function getPriceOfToken(totalTokensSold: number): number {
  return Math.floor(600_000 * 2 ** ((totalTokensSold + 1) / 1_000_000));
}
/**
 * @notice grabs the actual price of all the tokens by looping through each token and adding the price
            - this is not possible on-chain due to gas fees, so we use the sum of a geometric series in the contacts to get the price
 * @param totalTokensSold - the total number of tokens sold so far
 * @param totalToBuy - the total number of tokens to buy
 * @returns - the actual price of the tokens by looping through each token and adding the price
 */
function getPriceOfTokens(
  totalTokensSold: number,
  totalToBuy: number,
): BigNumber {
  let price = BigNumber.from(0);
  for (let i = 0; i < totalToBuy; ++i) {
    // price += getPriceOfToken(totalTokensSold + i);
    price = price.add(
      BigNumber.from(`${getPriceOfToken(totalTokensSold + i)}`),
    );
  }
  return price;
}

/**
 * @notice returns a random number between 0 and upperBound.
 * @param upperBound - the upper bound of the random number to generate
 * @returns
 */
function getRandomBigNumberWithUpperBound(upperBound: BigNumber) {
  //If upperbound is 1 return 1, this is to ensure all tokens are sold
  if (upperBound.eq(1)) return BigNumber.from(1);
  //We set the max upper bound to be 5% of the total supply to ensure we get enough fuzzing
  const maxVal = 0.05 * 12_000_000;
  const upperBoundRevised = upperBound.gt(maxVal)
    ? BigNumber.from(`${maxVal}`)
    : upperBound;
  let random = Math.floor(Math.random() * upperBoundRevised.toNumber());
  return BigNumber.from(`${random}`);
}

/***
 * @notice returns true if the actual value diverges more than the max divergence percent
 * @param actual - the actual value frrom the geometric series that the contract returned as the price
 * @param expected - the expected value returned from looping manually
 * @return true if the actual value diverges more than the max divergence percent
 */
function divergeMoreThanDivergencePercent(
  actual: BigNumber,
  expected: BigNumber,
): boolean {
  //Handle edge case of 0 to avoid division by zero
  if (expected.eq(0)) {
    if (!actual.eq(0)) throw new Error('Expected is 0 but actual is not');
    return false;
  }
  const diff = actual.sub(expected).abs();
  const percentDiff = diff.mul(BigNumber.from(10).pow(5)).div(expected);
  return percentDiff.gt(MAX_DIVERGENCE_PERCENT_E5);
}
