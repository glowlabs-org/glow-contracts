import { expect } from 'chai';
import { ethers } from 'hardhat';
import * as dotenv from 'dotenv';
import { BigNumber } from 'ethers';
dotenv.config();
import * as fs from 'fs';

//-------- ENVIRONMENT VARIABLES ------------
const FUZZ_RUNS: number = parseInt(process.env.CARBON_CREDIT_AUCTION_NUM_RUNS || "1");
const DEPTH_PER_RUN = parseInt(process.env.CARBON_CREDIT_AUCTION_DEPTH_PER_RUN || "1");
const SAVE_EARLY_LIQUIDITY_RUNS =
  (process.env.SAVE_CARBON_CREDIT_RUNS || "false").toLowerCase() === 'true';

//---- CONSTANTS ------
const USDC_DECIMALS = 6;
const STARTING_USDC_BALANCE = BigNumber.from(10)
  .pow(USDC_DECIMALS)
  .mul(1_000_000_000_000);
const MAX_DIVERGENCE_PERCENT_E5 = 100.0; //.01% , 1% would be 10000

// //--- CSV HEADERS ---
// /**
//  * @dev only applicable if SAVE_EARLY_LIQUIDITY_RUNS is true
//  */
// const csvHeaders = [
//   'totalTokensSoldBefore',
//   'tokensToBuy',
//   'totalCostFromContract',
//   'totalCostLocal',
//   'diverges',
//   'divergenceAmount',
//   'divergencePercent',
// ];

/***
 * @dev staging function to deploy contracts and mint USDC to the signer.
 * @dev useful when running fuzzing tests to reset the state of the contracts on each run.
 */

async function stage() {
  const [signer, other] = await ethers.getSigners();

  //Deploy contracts
  const CCC = await ethers.getContractFactory('CCC');
  const ccc = await await CCC.deploy();
  await ccc.deployed();

  
  return { ccc, signer, other };
}

//--- TESTS ----
describe('Test: Carbon Credit Auction', function () {
  it('Testing Linked List', async function () {
    //Setup the number of fuzz runs counter
    let numRunsCounter: number = 0;

    //While loop to run the fuzzing tests
    while (numRunsCounter < FUZZ_RUNS) {
      //Stage the contracts on each run
      const { signer, ccc } = await stage();

      //Generate 500 random bids
      const bids = generateBids(500);

      const promises = [];

      for (const bid of bids) {
        const tx =  ccc.bid(bid,0,0);
        promises.push(tx);
    }

    await Promise.all(promises);

    const fullList = await ccc.constructSortedList();
    const fullListJsonFormat = fullList.map((bid) => {
        return {
            id: bid.id.toString(),
            bid: bid.value.toString(),
        }
    });


    fs.writeFileSync("fullList.json", JSON.stringify(fullListJsonFormat,null,4));


    //   for (let i = 0; i < DEPTH_PER_RUN; ++i) {
        
    //   } 

   

      //Increment the number of runs counter
      ++numRunsCounter;
    }
  });
});

//----------------- HELPER FUNCTIONS -----------------

function generateBids(numBids:number) {
    const bids: BigNumber[] = [];
    for(let i = 0; i < numBids; ++i) {
        bids.push(generateRandomBid());
    }
    return bids;
}

function findPrevAndNextBid(bids: BigNumber[], bid: BigNumber) {
    let prevBid: BigNumber = BigNumber.from(0);
    let nextBid: BigNumber = BigNumber.from(0);
    bids = bids.sort();
    for(let i = 0; i < bids.length; ++i) {
        if(bids[i].gt(bid)) {
            nextBid = bids[i];
            break;
        }
        prevBid = bids[i];
    }
    return {prevBid, nextBid};
}


function generateRandomBid() {
    const UINT96_MAX = BigNumber.from(2).pow(96).sub(1);
    //Give a number between 1, UINT96_MAX
    const randomNumberBigNumber = BigNumber.from( Math.floor(Math.random() * 100))
    let randomBid = randomNumberBigNumber.mul(UINT96_MAX).div(100);
    while (randomBid.isZero()) {
        randomBid = generateRandomBid();
    }
    return randomBid;
}
