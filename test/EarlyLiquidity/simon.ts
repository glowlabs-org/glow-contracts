//----------------- HELPER FUNCTIONS -----------------

import { BigNumber } from 'ethers';

function getPriceOfToken(totalTokensSold: number): number {
  return Math.floor(600_000 * 2 ** ((totalTokensSold + 1) / 1_000_000));
}
/**
   * @notice grabs the actual price of all the tokens by looping through each token and adding the price
              - this is not possible on-chain due to gas fees, so we use integral calculus in the contacts to get the price
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

function testGeometricSeries(tokens: number) {
  const RATIO = 1.000000693;
  return (600_000 * (1 - RATIO ** tokens)) / (1 - RATIO);
}

console.log(getPriceOfTokens(0, 1000).toString());
console.log(testGeometricSeries(12000000).toString());
