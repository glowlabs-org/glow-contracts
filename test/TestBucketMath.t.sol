// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.13;

// import "forge-std/Test.sol";
// import "../src/temp/TestBucketMath.sol";
// import "forge-std/console.sol";

// contract TokenTest is Test {
//     uint256 constant ONE_WEEK = 1 weeks;
//     address simon = address(1);
//     address david = address(2);
//     TestBucketMath t;
    
//     function increaseTimeByWeeks(uint numWeeks) internal  {
//         vm.warp(block.timestamp + numWeeks * ONE_WEEK);
//     }
//     function setUp() public {
//         t = new TestBucketMath();
//     }

//     function testBucketMath() public {
//         // t.depositGRC(26_000);
//         // assertEq(26_000,t.totalGRCDeposited());

//         // uint currentBucket = t.getCurrentBucket();
//         // assertEq(0,currentBucket);

//         // increaseTimeByWeeks(1);

//         // t.depositGRC(26_000);

//         // assertEq(52_000,t.totalGRCDeposited());
//         // currentBucket = t.getCurrentBucket();
//         // assertEq(1,currentBucket);
//         // for(uint i; i<26;++i) {
//         //     t.deposit(2000);
//         //     increaseTimeByWeeks(1);

//         // }
//         // uint currentBucket;
//         // uint totalRewardsAvailableForCurrentWeek;
//         // currentBucket = t.getCurrentBucket();
//         // assertEq(26,currentBucket);
        
//         // // console.log("totalRewardsAvailableForCurrentWeek: %s", totalRewardsAvailableForCurrentWeek);
        
//         // for(uint i; i<52;++i) {
//         //     increaseTimeByWeeks(1);
//         //     t.deposit(2000);
//         //     // console.log("totalRewardsAvailableForCurrentWeek %s", totalRewardsAvailableForCurrentWeek);
//         // }
//         //week 0, so 52+26 should have amounttodeduce = 
//         t.deposit(52_000);
//         assertEq(52_000,t.totalToDeduce(78));
//         increaseTimeByWeeks(1);

//         t.deposit(52_000);
//         assertEq(52_000,t.totalToDeduce(79));
//         increaseTimeByWeeks(1);
        
//         t.deposit(104_000);
//         assertEq(104_000,t.totalToDeduce(80));
//         increaseTimeByWeeks(78);
//         for(uint i; i<77 ; ++i) {
//             uint id = i+26;
//             // uint totalDeposit = t.total3Deposit(id);
//             // console.log("total deposit %s" , totalDeposit);
//             if(id == 78){
//                 // console.log("total to deduce for week 78 %s" , t.totalToDeduce(78));
//             }
//             if(id == 79){
//                 // console.log("total to deduce for week 79 %s" , t.totalToDeduce(79));
//             }
//             uint amtInWeek = t.getBucketValue(id);
//             // console.log("Week %s", id);
//             // console.log("amt = %s", amtInWeek);
            
//         }
//         // console.log("total to deduce for week 77 %s" , t.totalToDeduce(77));


        
//     }

// }
