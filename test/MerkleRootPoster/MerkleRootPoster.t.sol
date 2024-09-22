// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";
import {MerkleRootPoster} from "@/MerkleRootPoster.sol";

contract MerkleRootPosterTest is Test {
    MerkleRootPoster poster;

    function setUp() public {
        poster = new MerkleRootPoster();
    }

    function test_postRoot() public {
        bytes32 root = keccak256(abi.encodePacked("root"));
        poster.postRoot(root);
        assert(poster.getRoot(root).timestamp == block.timestamp);
    }

    function test_postRoot_alreadyPosted() public {
        bytes32 root = keccak256(abi.encodePacked("root"));
        poster.postRoot(root);
        assert(poster.getRoot(root).timestamp == block.timestamp);

        vm.expectRevert(MerkleRootPoster.RootAlreadyPosted.selector);
        poster.postRoot(root);
    }
}
