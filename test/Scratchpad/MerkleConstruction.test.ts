import { expect } from 'chai';
import { ethers } from 'hardhat';
import * as dotenv from 'dotenv';
import { BigNumber } from 'ethers';
dotenv.config();
import { keccak256 } from 'ethers/lib/utils';
import MerkleTree from 'merkletreejs';
import * as fs from 'fs';
import { StandardMerkleTree } from '@openzeppelin/merkle-tree';
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

  const MerkleConstruction = await ethers.getContractFactory("MerkleConstruction");
    const merkleConstruction = await MerkleConstruction.deploy();
    await merkleConstruction.deployed();

    return {merkleConstruction, signer, other};
}

//--- TESTS ----
describe('Merkle Construction', function () {
    //@ts-ignore
    const runs = [];
  it('Should Build The Parent Root', async function () {
    for(let i =0; i<20;++i) {
    const {merkleConstruction, signer, other} = await stage();

    const randomHash =  ethers.utils.hexlify(ethers.utils.randomBytes(32));
    const randomHash2 = ethers.utils.hexlify(ethers.utils.randomBytes(32));

    const tx1 = await merkleConstruction.addLeaf(randomHash);
    const tx2 = await merkleConstruction.addLeaf(randomHash2);
    await tx1.wait();
    await tx2.wait();
    

    const stateRoot = await merkleConstruction.merkleRoot();
    
    const tree = new MerkleTree([randomHash, randomHash2], keccak256, {sort: false});
    const root = tree.getHexRoot();
    // const ozTree =  StandardMerkleTree.of([[randomHash], [randomHash2]],["bytes32"])
    // const ozRoot = ozTree.root;
    // expect(root).to.equal(ozRoot, "root should equal ozRoot");

    const rootFromContract = await merkleConstruction.calculateMerkleRoot([randomHash, randomHash2]);
    
    expect(rootFromContract).to.equal(root, "rootFromContract should equal root");
    expect(rootFromContract).to.equal(stateRoot, "rootFromContract should equal stateRoot");

    
    let proof = tree.getHexProof(randomHash)
    const proof2 = tree.getHexProof(randomHash2)

    const r2Larger = !BigNumber.from(randomHash).gt(randomHash2);


    
 
    let success: boolean = true;
    // const verification = await merkleConstruction.verifyLeafFull(root, randomHash, proof);
    const isValidProofJS = tree.verify(proof, randomHash, root);
    const verificationOZ = await merkleConstruction.verifyLeafFullOZ(root, randomHash, proof);
    // expect(verification).to.equal(true,"verification");
    if(!verificationOZ) { success = false; }

    // expect(verificationOZ).to.equal(true,"verificationOZ");

    // const verification2 = await merkleConstruction.verifyLeafFull(root, randomHash2, proof2);
    const verificationOZ2 = await merkleConstruction.verifyLeafFullOZ(root, randomHash2, proof2);
    // expect(verificationOZ2).to.equal(true,"verification2");
    // expect(verificationOZ2).to.equal(true,"verificationOZ2");


    const results = {
        root,
        rootFromContract,
        stateRoot,
        proof,
        proof2,
        randomHash,
        randomHash2,
        success,
        success2:verificationOZ2,
        r2Larger,
        isValidProofJS,
    }

    runs.push(results);


  }
  //@ts-ignore
  fs.writeFileSync('runs.json', JSON.stringify(runs,null,4));

    
  });
});
