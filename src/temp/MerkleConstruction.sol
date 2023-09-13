// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MerkleProofLib} from "@solady/utils/MerkleProofLib.sol";
// import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {MerkleProof} from "@/libraries/MerkleProof.sol";

contract MerkleConstruction {
    bytes32 public merkleRoot;

    bytes32[] public leaves;

    function addLeaf(bytes32 newLeaf) public {
        leaves.push(newLeaf);
        merkleRoot = calculateMerkleRoot(leaves);
    }

    function calculateMerkleRoot(bytes32[] memory nodes) public pure returns (bytes32) {
        require(nodes.length > 0, "No leaves to calculate root for");

        while (nodes.length > 1) {
            uint256 layerLength = nodes.length / 2;
            for (uint256 i = 0; i < layerLength; i++) {
                nodes[i] = keccak256(abi.encodePacked(nodes[i * 2], nodes[i * 2 + 1]));
            }
            if (nodes.length % 2 == 1) {
                nodes[layerLength] = nodes[nodes.length - 1];
                ++layerLength;
            }
            assembly {
                mstore(nodes, layerLength)
            }
        }
        return nodes[0];
    }

    function verifyLeaf(bytes32 leaf, bytes32[] calldata proof) external view returns (bool) {
        return MerkleProofLib.verifyCalldata(proof, merkleRoot, leaf);
    }

    function verifyLeafFull(bytes32 root, bytes32 leaf, bytes32[] calldata proof) external view returns (bool) {
        return MerkleProofLib.verifyCalldata(proof, root, leaf);
    }

    function verifyLeafFullOZ(bytes32 root, bytes32 leaf, bytes32[] calldata proof) external view returns (bool) {
        return MerkleProof.verifyCalldata(proof, root, leaf);
    }
}

// This contract stores a merkleRoot and an array of leaves. When you add a new leaf using the addLeaf function, it appends the leaf and recalculates the Merkle root.

// However, remember this approach is naive. As you add more leaves, the recalculation of the Merkle root becomes more gas intensive. Moreover, the above contract doesn't manage any kind of node structure beyond the leaves layer, so it's quite inefficient.

// In a more efficient setup, you would likely need to manage not just leaves but all intermediate nodes of the Merkle tree, and carefully design the addition and updating process to minimize gas costs.

// User
// can you break down the calculate merkleRoot function, i dont quite understand the math and logic behind it
// ChatGPT
// Of course! The calculateMerkleRoot function is responsible for constructing a Merkle root from a list of leaf nodes. This function uses the concept of a binary Merkle tree. The logic can be broken down into the following steps:

// Loop Until Root is Found: The while loop continues until the list of nodes is reduced to a single value, the Merkle root.

// Calculate Parent Nodes for Current Layer: For each pair of nodes in the current layer, the function computes the hash of the two nodes concatenated together. This newly computed hash becomes a node in the next layer up the tree.

// Specifically:

// solidity
// Copy code
// nodes[i] = keccak256(abi.encodePacked(nodes[i * 2], nodes[i * 2 + 1]));
// Here, nodes[i * 2] and nodes[i * 2 + 1] are two adjacent nodes in the current layer, and their combined hash becomes the i-th node of the next layer.

// Handle Odd Number of Nodes: If there's an odd number of nodes in the current layer, the last node is simply carried up to the next layer without being paired and hashed.

// This is done by:

// solidity
// Copy code
// if (nodes.length % 2 == 1) {
//     nodes[layerLength] = nodes[nodes.length - 1];
//     layerLength++;
// }
// Reduce Nodes Array to Next Layer: After processing all nodes of the current layer, the list of nodes is truncated to just include the next layer's nodes. This is done using inline assembly for efficiency:

// solidity
// Copy code
// assembly {
//     mstore(nodes, layerLength)
// }
// This line of code effectively changes the length of the dynamic array nodes to be layerLength. The purpose is to remove the nodes of the current layer that we just processed, leaving only the nodes of the next layer in the nodes array.

// Return the Merkle Root: Once the loop completes, the Merkle root is the only node left in the nodes array, and it's returned by the function.

// In essence, the function starts with a list of leaf nodes and progressively combines and hashes them together, layer by layer, until it's left with a single value, the Merkle root. The nature of Merkle trees ensures that this root is unique to the specific set and arrangement of leaf nodes provided.
