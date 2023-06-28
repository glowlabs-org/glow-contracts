// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.13;

// import "forge-std/Test.sol";
// import "../src/temp/GCAPayoutAlgo.sol";
// import "forge-std/console.sol";

// contract TokenTest is Test {
//     uint256 constant ONE_WEEK = 1 weeks;
//     address gca1 = address(1);
//     address gca2 = address(2);
//     address gca3 = address(3);
//     address gca4 = address(4);
//     address gca5 = address(5);
//     GCAPayoutAlgo algo;
    
//     function increaseTimeByWeeks(uint numWeeks) internal  {
//         vm.warp(block.timestamp + numWeeks * ONE_WEEK);
//     }

//     function increaseTimeBySeconds(uint numSeconds) internal  {
//         vm.warp(block.timestamp + numSeconds);
//     }
//     function setUp() public {
//         algo = new GCAPayoutAlgo();
//     }

//     function createCompensationPlan(uint80 shares,address gca) internal pure returns(CompensationI memory) {
//         return CompensationI({shares:shares, agent:gca});
//     }

//     function logHelper(Helper memory h) internal {
//         console.log("last reward timestamp %s ", h.lastRewardTimestamp);
//         console.log("shares %s ", h.shares);
//         // console.log("is gca )
//     }
//     function testGCAPayoutAlgo() public {
//         uint startTimestamp = block.timestamp;
//         uint timeDiff;
//         uint totalShares;
//         {

//             uint rewardsPerSecond = algo.rewardsPerSecondForAll();
//             algo.addGCA(gca1);
//             algo.addGCA(gca2);
//             algo.addGCA(gca3);
//             algo.addGCA(gca4);
//             algo.addGCA(gca5);
            
//             vm.startPrank(gca1);
//             CompensationI[] memory compensationPlans = new CompensationI[](5);
//             compensationPlans[0] = createCompensationPlan(1000,gca1);
//             compensationPlans[1] = createCompensationPlan(2000,gca2);
//         compensationPlans[2] = createCompensationPlan(3000,gca3);
//         compensationPlans[3] = createCompensationPlan(3500,gca4);
//         compensationPlans[4] = createCompensationPlan(500,gca5);
        
//         algo.submitCompensationPlan(compensationPlans);
  
//         increaseTimeBySeconds(10);
        
//         uint reward1 = algo.nextReward(gca1);
//         totalShares = algo.totalShares();
//         Helper memory h1 = algo.helpers(gca1);
//         assertEq(1000,h1.shares);
//         assertEq(10_000,totalShares); 
//         timeDiff = block.timestamp - startTimestamp;
//         uint u1TimeDiff = block.timestamp - h1.lastRewardTimestamp;
//         assertEq(reward1,rewardsPerSecond * timeDiff  * h1.shares / totalShares);       
//         assertEq(reward1,rewardsPerSecond * u1TimeDiff  * h1.shares / totalShares);       
        
        
//         // add another compesnation plan.. from gca1 to see if values correctly update
//         compensationPlans[0] = createCompensationPlan(5000,gca1);
//         compensationPlans[1] = createCompensationPlan(1000,gca2);
//         compensationPlans[2] = createCompensationPlan(1000,gca3);
//         compensationPlans[3] = createCompensationPlan(2000,gca4);
//         compensationPlans[4] = createCompensationPlan(1000,gca5);
        
//         algo.submitCompensationPlan(compensationPlans);
//         uint balance1 = algo.balance(gca1);
//         console.log("balance 1 %s", balance1);
        
        
        
        
//         reward1 = algo.nextReward(gca1);
//         totalShares = algo.totalShares();
//         h1 = algo.helpers(gca1);
//         assertEq(5000,h1.shares);
//         assertEq(10_000,totalShares); 
//         timeDiff = block.timestamp - startTimestamp;
//         u1TimeDiff = block.timestamp - h1.lastRewardTimestamp;
//         assertEq(reward1,rewardsPerSecond * u1TimeDiff  * h1.shares / totalShares);       
//         vm.stopPrank();
        
//         increaseTimeBySeconds(10);
//         vm.startPrank(gca1);
//         reward1 = algo.nextReward(gca1);
//         totalShares = algo.totalShares();
//          h1 = algo.helpers(gca1);
//         assertEq(5000,h1.shares);
//         assertEq(10_000,totalShares);
//         u1TimeDiff = block.timestamp - h1.lastRewardTimestamp;
//         assertEq(reward1,rewardsPerSecond * u1TimeDiff  * h1.shares / totalShares);
//     }
//     {
//     uint rewardsPerSecond = algo.rewardsPerSecondForAll();
//         //Check all others
//     uint reward2 = algo.nextReward(gca2);
//     uint reward3 = algo.nextReward(gca3);
//     uint reward4 = algo.nextReward(gca4);
//     uint reward5 = algo.nextReward(gca5);
//     Helper memory h2 = algo.helpers(gca2);
//     Helper memory h3 = algo.helpers(gca3);
//     Helper memory h4 = algo.helpers(gca4);
//     Helper memory h5 = algo.helpers(gca5);
//     uint diffForOthers = block.timestamp - startTimestamp;
//     assertEq(reward2,rewardsPerSecond * diffForOthers  * h2.shares / totalShares);
//     assertEq(reward3,rewardsPerSecond * diffForOthers  * h3.shares / totalShares);
//     assertEq(reward4,rewardsPerSecond * diffForOthers  * h4.shares / totalShares);
//     assertEq(reward5,rewardsPerSecond * diffForOthers  * h5.shares / totalShares);
    
// }
//     algo.claimRewards();
//     vm.stopPrank();

//     //Claim rewards from all GCAs
//     vm.startPrank(gca2);
//     algo.claimRewards();
//     vm.stopPrank();
//     vm.startPrank(gca3);
//     algo.claimRewards();
//     vm.stopPrank();
//     vm.startPrank(gca4);
//     algo.claimRewards();
//     vm.stopPrank();
//     vm.startPrank(gca5);
//     algo.claimRewards();
//     vm.stopPrank();

//     //Let's find out how much each GCA has claimed
//     {
//         uint balance1 = algo.balance(gca1);
//         uint balance2 = algo.balance(gca2);
//         uint balance3 = algo.balance(gca3);
//         uint balance4 = algo.balance(gca4);
//         uint balance5 = algo.balance(gca5);

//         console.log("balance 1 %s ", balance1);
//         console.log("balance 2 %s ", balance2);
//         console.log("balance 3 %s ", balance3);
//         console.log("balance 4 %s ", balance4);
//         console.log("balance 5 %s ", balance5);


//     }


//     // algo.claimRewards();
        

    

        
//     }
// }
