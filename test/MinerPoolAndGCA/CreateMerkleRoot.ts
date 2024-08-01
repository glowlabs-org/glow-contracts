import MerkleTree from 'merkletreejs';
import keccak256 from 'keccak256';
// import * as fs from "fs";
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

const leaves = getLeavesArg();
leaves.forEach((leaf) => {
  if (leaf.length != 66) {
    throw new Error('Leaves must be 32 bytes long');
  }
});

const tree = new MerkleTree(leaves, keccak256, { sort: true });

const hexRoot = tree.getHexRoot();

console.log(hexRoot);
