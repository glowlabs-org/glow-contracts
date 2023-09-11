// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/console.sol";
import "@/MinerPoolAndGCA/BucketSubmission.sol";
contract MD2 is BucketSubmission {
    
    function addToCurrentBucket(address grcToken,uint amount) external {
        _addToCurrentBucket(grcToken,amount);
    }
}
