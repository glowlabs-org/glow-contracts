import MerkleTree from 'merkletreejs';
import keccak256 from 'keccak256';
import * as fs from 'fs';
import { ethers } from 'hardhat';
// Function to extract leaves argument from the command line arguments
//store the process.argv in a variable

// const fullCommand = process.argv;
// fs.writeFileSync("fullCommand.txt", fullCommand.toString());
function getLeavesArg(): string[] {
  const leavesArgPrefix = '--leaves=';
  const arg = process.argv.find((arg) => arg.startsWith(leavesArgPrefix));
  if (!arg) {
    throw new Error('Leaves argument not provided.');
  }

  const jsonString = arg.slice(leavesArgPrefix.length);
  return JSON.parse(jsonString);
}

function getTargetLeafArg(): string {
  const targetLeafArgPrefix = '--targetLeaf=';
  const arg = process.argv.find((arg) => arg.startsWith(targetLeafArgPrefix));
  if (!arg) {
    throw new Error('Target leaf argument not provided.');
  }

  return arg.slice(targetLeafArgPrefix.length);
}

//leaves should already be hashed
const leaves = getLeavesArg();
const targetLeaf = getTargetLeafArg();
const tree = new MerkleTree(leaves, keccak256, { sort: true });

const proof = tree.getHexProof(targetLeaf);

const abiEncoder = new ethers.utils.AbiCoder();
const proofEncoded = abiEncoder.encode(['bytes32[]'], [proof]);
// fs.writeFileSync("proof.txt", JSON.stringify(proofEncoded));
console.log(proofEncoded);
// fs.writeFileSync("hexRoot.txt", tree.getHexRoot());
