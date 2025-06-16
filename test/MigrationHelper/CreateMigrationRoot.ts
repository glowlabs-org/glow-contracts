// keccak256(abi.encodePacked(accounts[i], glowAmounts[i], gccAmounts[i], usdgAmounts[i]),nominations[i],impactPower[i]);

import * as fs from 'fs';
import { ethers } from 'ethers';
import {
  SimpleMerkleTree,
  StandardMerkleTree,
} from '@openzeppelin/merkle-tree';
import { parseUnits } from 'ethers/lib/utils';

const address1 = '0x28009e8a27Aa1836d6B4a2E005D35201Aa5269ea';
const glowAmount1 = parseUnits('1000', 18);
const gccAmount1 = parseUnits('1', 18);
const usdgAmount1 = parseUnits('1000', 6);
const nominations1 = parseUnits('4', 12);
const impactPower1 = parseUnits('5', 12);

const address2 = '0xD70823246D53EE41875B353Df2c7915608279de1';
const glowAmount2 = parseUnits('2000', 18);
const gccAmount2 = parseUnits('2', 18);
const usdgAmount2 = parseUnits('2000', 6);
const nominations2 = parseUnits('8', 12);
const impactPower2 = parseUnits('10', 12);

const address3 = '0x93ECA9F2dffc5f7Ab3830D413c43E7dbFF681867';
const glowAmount3 = parseUnits('3000', 18);
const gccAmount3 = parseUnits('3', 18);
const usdgAmount3 = parseUnits('3000', 6);
const nominations3 = parseUnits('12', 12);
const impactPower3 = parseUnits('15', 12);

const values = [
  [address1, glowAmount1, gccAmount1, usdgAmount1, nominations1, impactPower1],
  [address2, glowAmount2, gccAmount2, usdgAmount2, nominations2, impactPower2],
  [address3, glowAmount3, gccAmount3, usdgAmount3, nominations3, impactPower3],
];
const tree = StandardMerkleTree.of(values, [
  'address',
  'uint256',
  'uint256',
  'uint256',
  'uint256',
  'uint256',
]);

const root = tree.root;
console.log(`Root: ${root}`);

//proof 1
{
  const { proof, proofFlags, leaves } = tree.getMultiProof([0]);

  console.log(`Proof 1: ${proof}`);
  console.log(`Proof Flags 1: ${proofFlags}`);
}

//proof 2 {}
{
  const { proof, proofFlags, leaves } = tree.getMultiProof([1]);

  console.log(`Proof 2: ${proof}`);
  console.log(`Proof Flags 2: ${proofFlags}`);
}

//MultiProof with both indexes
{
  const { proof, proofFlags, leaves } = tree.getMultiProof([0, 1]);

  //Log the leaves to find the order
  console.log(`Leaves Multi: ${leaves}`);
  console.log(`Proof Multi: ${proof}`);
  console.log(`Proof Flags Multi: ${proofFlags}`);
}
{
}
//Multi
