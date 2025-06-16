// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title MerkleRootPoster
 * @notice A contract for posting merkle roots to have PoH Verified
 */
contract MerkleRootPoster {
    error RootAlreadyPosted();

    struct RootData {
        uint64 timestamp;
        address poster;
    }

    mapping(bytes32 => RootData) private $roots;

    event RootPosted(bytes32 indexed root, uint64 timestamp, address poster);

    function postRoot(bytes32 root) external {
        if ($roots[root].timestamp != 0) {
            revert RootAlreadyPosted();
        }
        $roots[root] = RootData(uint64(block.timestamp), msg.sender);
        emit RootPosted(root, uint64(block.timestamp), msg.sender);
    }

    function getRoot(bytes32 root) external view returns (RootData memory) {
        return $roots[root];
    }
}
