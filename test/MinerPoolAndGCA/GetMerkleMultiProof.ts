import * as fs from 'fs';
import { ethers } from 'ethers';
import { SimpleMerkleTree } from '@openzeppelin/merkle-tree';

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

function getTargetLeafArg(): { weightsLeaf: string; tokensLeaf: string } {
  const targetLeafArgPrefix = '--targetLeaves=';
  const arg = process.argv.find((arg) => arg.startsWith(targetLeafArgPrefix));
  if (!arg) {
    throw new Error('Target leaf argument not provided.');
  }

  const leavesString = arg.slice(targetLeafArgPrefix.length);
  //write the leaves string
  fs.writeFileSync('leavesString.json', JSON.stringify(leavesString, null, 4));
  const leaves = leavesString.split(',');
  const weightsLeaf = leaves[0];
  const tokensLeaf = leaves[1];
  const l = { weightsLeaf, tokensLeaf };
  fs.writeFileSync('leaves.json', JSON.stringify(l, null, 4));
  return l;
}

//leaves should already be hashed
const leaves = getLeavesArg();
const { weightsLeaf, tokensLeaf } = getTargetLeafArg();

// // const proofLeaves = [weightsLeaf, tokensLeaf].sort(Buffer.compare);
// let proofLeaves = [weightsLeaf, tokensLeaf].sort((a, b) =>
//   BigNumber.from(a).gt(BigNumber.from(b)) ? 1 : -1,
// );

// const weightsLeafDoubleHashed = eK.keccak256(weightsLeaf);
// const tokensLeafDoubleHashed = eK.keccak256(tokensLeaf);

// const doubleHashedLeaves = leaves.map((leaf) => eK.keccak256(leaf));
// const weightsLeafIndex = doubleHashedLeaves.indexOf(weightsLeafDoubleHashed);
// const tokensLeafIndex = doubleHashedLeaves.indexOf(tokensLeafDoubleHashed);
// const requestedProofIndeces = [weightsLeafIndex, tokensLeafIndex];

const claimIndex = leaves.indexOf(weightsLeaf);
const tokenIndex = leaves.indexOf(tokensLeaf);
const requestedProofIndeces = [claimIndex, tokenIndex];
// const hashedAgain = leaves.map((leaf) => eK.keccak256(leaf));
const tree = SimpleMerkleTree.of(leaves); //laeves are already double hashes

const {
  proof,
  leaves: proofOrderedLeaves,
  proofFlags,
} = tree.getMultiProof(requestedProofIndeces);

const state = {
  leaves: leaves,
  requestedProofIndeces,
  proof,
  proofOrderedLeaves,
};
fs.writeFileSync('state.json', JSON.stringify(state, null, 4));

const encoder = new ethers.utils.AbiCoder();
const proofEncoded = encoder.encode(
  ['bytes32[]', 'bool[]'],
  [proof, proofFlags],
);

console.log(proofEncoded);
