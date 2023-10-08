import { expect } from 'chai';
import { ethers } from 'hardhat';
import * as dotenv from 'dotenv';
import { BigNumber } from 'ethers';
dotenv.config();
import * as fs from 'fs';
import { CCC } from '../../typechain-types';

//-------- ENVIRONMENT VARIABLES ------------
const FUZZ_RUNS: number = parseInt(process.env.CARBON_CREDIT_AUCTION_NUM_RUNS || "2");
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
//   it('Testing Linked List', async function () {
//     //Setup the number of fuzz runs counter
//     let numRunsCounter: number = 0;

//     //While loop to run the fuzzing tests
//     while (numRunsCounter < FUZZ_RUNS) {
//       //Stage the contracts on each run
//       const { signer, ccc } = await stage();

//       //Generate 500 random bids
//       const bids = generateBids(500);

//       const promises = [];

//       for (const bid of bids) {
//         const tx =  ccc.bid(bid,0,0);
//         promises.push(tx);
//     }

//     await Promise.all(promises);

//     const fullList = await ccc.constructSortedList();
//     const fullListJsonFormat = fullList.map((bid) => {
//         return {
//             id: bid.id.toString(),
//             bid: bid.value.toString(),
//         }
//     });


//     fs.writeFileSync("fullList.json", JSON.stringify(fullListJsonFormat,null,4));


//     //   for (let i = 0; i < DEPTH_PER_RUN; ++i) {
        
//     //   } 

   

//       //Increment the number of runs counter
//       ++numRunsCounter;
//     }
//   });
  it('Testing Linked List', async function () {

     //Setup the number of fuzz runs counter
     let numRunsCounter: number = 0;

     //While loop to run the fuzzing tests
     while (numRunsCounter < FUZZ_RUNS) {
       //Stage the contracts on each run
       const { signer, ccc } = await stage();
        
       const minimum = ethers.utils.parseEther("1");
       //Generate 250 random bids
       const bids = generateBids(250,minimum);
       
       let i = 0;
       for (const bid of bids) {    
           const tx =  await ccc.bid(bid.maxPrice,0,0,bid.amountToBid);
           await tx.wait();
           ++i;
           
        }
        const sortedBids = await ccc.constructSortedList();
        const sortedBidsJsonFormat = sortedBids.map((bid) => {
            return {
                id: bid.id.toString(),
                amount: bid.amount.toString(),
                maxPrice: bid.maxPrice.toString(),
            }
        });
        fs.writeFileSync("sortedBids.json", JSON.stringify(sortedBidsJsonFormat,null,4));

 
    const close = await ccc.close();
    await close.wait();
    const closingPrice = await ccc.closingPrice();

    console.log(`closing price = ${ethers.utils.formatEther(closingPrice)}`)

    const pointers = await ccc.pointers();
    let head = pointers.head;

    //uint32 max 
    const NULL:number =  4294967295;
    let totalSold = BigNumber.from(0);
     let iter = 0;
    while(head != NULL){
        console.log(`iter = ${iter}`);
        const bid = await ccc.bids(head);
        if(bid.maxPrice.lt(closingPrice)) {
            console.log(`breaking max price = ${ethers.utils.formatEther(bid.maxPrice)}`);
            break;
        }
        const amountOwedToSeller = await ccc.amountOwed(head);
        console.log(`amount owed to seller = ${ethers.utils.formatEther(amountOwedToSeller)}`);
        totalSold = totalSold.add(amountOwedToSeller);
        head = bid.prev;
        ++iter;
    }

    
    console.log(`total sold = ${ethers.utils.formatEther(totalSold)}`)

    const lastLegibilePointer = await ccc.lastPointerLegibleForClaim();
    console.log(`last legible pointer = ${lastLegibilePointer.toString()}`);
     //   for (let i = 0; i < DEPTH_PER_RUN; ++i) {
         
     //   } 
 
    
 
       //Increment the number of runs counter
       ++numRunsCounter;
     }
    
  });
});

//----------------- HELPER FUNCTIONS -----------------

const TOTAL_SUPPLY = ethers.utils.parseEther("1000");
const MIN_BID = ethers.utils.parseEther("1");
/// @dev 1 million GLOW
const LARGEST_BID = ethers.utils.parseEther("10000000000000");
const MINIMUM_PRICE = ethers.utils.parseEther(".0000001");
const ONE_E18 = ethers.utils.parseEther("1");
//1000 GLW / GCC
const MAXIMUM_PRICE = ethers.utils.parseEther("1000");
type Bid = {
    maxPrice: BigNumber;
    amountToBid: BigNumber;
}
function generateBids(numBids:number,minimum:BigNumber) {
    const bids: Bid[] = [];
    let minBidAmount = minimum;
    for(let i = 0; i < numBids; ++i) {
        let price = getRandomBigNumber(MINIMUM_PRICE,MAXIMUM_PRICE);
        let amountToBid = getRandomBigNumber(minBidAmount,LARGEST_BID);
        let totalToPurchase = amountToBid.mul(ONE_E18).div(price);
        while(totalToPurchase.gt(TOTAL_SUPPLY)) {
            amountToBid = amountToBid.div(2);
            if(amountToBid.lt(minBidAmount)) {
                amountToBid = minBidAmount;
            }

            price = price.mul(2);
            totalToPurchase = amountToBid.mul(ONE_E18).div(price);
        }
        bids.push({
            maxPrice: price,
            amountToBid: amountToBid
        });
        minBidAmount = minBidAmount.mul(110).div(100)
    }
    
    
    return bids;
}


function getRandomBigNumber(min: BigNumber, max: BigNumber): BigNumber {
    if(min.gt(max)) throw new Error("Min should be less than or equal to Max");
    
    const difference = max.sub(min);
    const randomFactor = BigNumber.from(
      '0x' + Math.random().toString(16).substring(2)
    );
  
    return min.add(difference.mul(randomFactor).div(BigNumber.from('0x' + 'f'.repeat(64))));
  }


// //----------------- HELPER FUNCTIONS -----------------

// function findPrevAndNextBid(bids: BigNumber[], bid: BigNumber) {
//     let prevBid: BigNumber = BigNumber.from(0);
//     let nextBid: BigNumber = BigNumber.from(0);
//     bids = bids.sort();
//     for(let i = 0; i < bids.length; ++i) {
//         if(bids[i].gt(bid)) {
//             nextBid = bids[i];
//             break;
//         }
//         prevBid = bids[i];
//     }
//     return {prevBid, nextBid};
// }
