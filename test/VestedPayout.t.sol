// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.13;

// import "forge-std/Test.sol";
// import "../src/temp/VestingAlgo.sol";
// import "forge-std/console.sol";

// contract TokenTest is Test {
//     uint256 constant ONE_WEEK = 1 weeks;
//     address simon = address(1);
//     address david = address(2);
//     VestingAlgo v;

//     function increaseTimeByWeeks(uint256 numWeeks) internal {
//         vm.warp(block.timestamp + numWeeks * ONE_WEEK);
//     }

//     function setUp() public {
//         v = new VestingAlgo();
//     }

//     function testVestingPayout() public {
//         (uint256 amt_vested,) = v.calculateVested(1e18, 365, 0);
//         console.log("vested %s", amt_vested);
//     }
// }
