// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {MinerDistributionMath} from "@glow/temp/MinerDistributionMath.sol";
import "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MinerDistributionHandler} from "./Handlers/MinerDistributionHandler.t.sol";

contract MinerDistributionMathTest is Test {
    MinerDistributionMath minerMath;
    MinerDistributionHandler handler;

    //------------- SETUP -------------
    /**
     * @dev we create all the contracts
     *         -   and assign fuzzing and invariant targets
     *         -   we only test the addRewardsToBucket function inside the handler
     */
    function setUp() public {
        minerMath = new MinerDistributionMath();
        handler = new MinerDistributionHandler(address(minerMath));
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = MinerDistributionHandler.addRewardsToBucket.selector;
        selectors[1] = MinerDistributionHandler.addRewardsToBucketNoWarp.selector;
        FuzzSelector memory fs = FuzzSelector({selectors: selectors, addr: address(handler)});
        targetContract(address(handler));
    }

    //-----------------INVARIANTS-----------------

    /**
     * @dev we test that all ghost buckets match the manual array
     */
    function invariant_bucketMath_shouldMatchManualArray() public {
        uint256[] memory allGhostBucketIds = handler.allGhostBucketIds();
        for (uint256 i; i < allGhostBucketIds.length; ++i) {
            uint256 rewardInGhostMapping = handler.ghost_amountInBucket(allGhostBucketIds[i]);
            MinerDistributionMath.WeeklyReward memory reward = minerMath.reward(allGhostBucketIds[i]);
            assertTrue(reward.amountInBucket == rewardInGhostMapping);
        }
    }

    //----------------- TESTS  -----------------

    /**
     * @dev function to test the addRewardsToBucket function
     *         -   we loop over 300 weeks,
     *         -   and add 192,000 to the current bucket
     *             - the 192,000 should be equally divided between 192 weeks
     *                 -   the first week being {currentBucket + 16}, and the last week
     *                 -   being {currentBucket + 208}
     *         -   we then save the bucket data to a file
     *         -   and then show the graph
     * @dev we only add rewards to the first 20 buckets, and then
     *             -   we add 0 to the other buckets to see if they correctly inherit from the previous week
     *             -   this is all inspected in the py-utils/miner-pool/data/buckets.json file
     */
    function test_MinerPoolFFI() public {
        uint256 amountToAdd = 192_000;
        uint256 oneWeek = uint256(7 days);

        string memory jsonString;
        uint256 weeksToLoop = 300;
        for (uint256 i = 0; i < weeksToLoop; i++) {
            if (i >= 20) {
                if (i >= 200) {
                    minerMath.addToCurrentBucket(0);
                }
            } else {
                minerMath.addToCurrentBucket(amountToAdd);
            }
            vm.warp(block.timestamp + oneWeek);
        }

        saveBucketsToFile(0, 340, "./py-utils/miner-pool/data/buckets.json");
    }

    //-----------------UTILS-----------------

    /// @dev - helper function to log a reward for debug purposes
    function logWeeklyReward(uint256 id, MinerDistributionMath.WeeklyReward memory reward) public {
        console.logString("---------------------------------");
        console.log("id %s", id);
        console.log("inheritedFromLastWeek %s", reward.inheritedFromLastWeek);
        console.log("amountInBucket %s", reward.amountInBucket);
        console.log("amountToDeduct %s", reward.amountToDeduct);
        console.logString("---------------------------------");
    }

    /// @dev - helper function to log a group of rewards for debug purposes
    function logBuckets(uint256 start, uint256 finish) public {
        for (uint256 i = start; i <= finish; i++) {
            logWeeklyReward(i, minerMath.reward(i));
        }
    }

    /// @dev used to save the results of the bucket outputs to a file
    ///     -   we used this during testing to generate the graph
    ///     -   and to sanity check the results
    function saveBucketsToFile(uint256 start, uint256 end, string memory fileName) public {
        deleteFile();
        vm.writeLine(fileName, "[");

        for (uint256 i = start; i <= end; i++) {
            MinerDistributionMath.WeeklyReward memory reward = minerMath.reward(i);
            string memory key1 = vm.serializeUint(string(abi.encodePacked(Strings.toString(i))), "id", i);
            string memory key2 = vm.serializeBool(
                string(abi.encodePacked(Strings.toString(i))), "inheritedFromLastWeek", reward.inheritedFromLastWeek
            );
            string memory key3 =
                vm.serializeUint(string(abi.encodePacked(Strings.toString(i))), "amountInBucket", reward.amountInBucket);
            //also add amountToDeduct
            string memory key4 =
                vm.serializeUint(string(abi.encodePacked(Strings.toString(i))), "amountToDeduct", reward.amountToDeduct);
            // string memory finalJson = vm.serializeString("","finalJson",jsonString);
            vm.writeLine(fileName, key4);
            if (i == end) break;
            vm.writeLine(fileName, ",");
        }
        vm.writeLine(fileName, "]");

        // showGraph();
    }

    /// @dev - helper function to delete the json file that contains the bucket outputs
    function deleteFile() public {
        string[] memory deleteFileCommands = new string[](2);
        deleteFileCommands[0] = "python3";
        deleteFileCommands[1] = "./py-utils/miner-pool/delete_file_if_exists.py";
        vm.ffi(deleteFileCommands);
    }

    /// @dev - helper function that generates the json and then shows the distribution of the buckets
    function showGraph() public {
        string[] memory graphCommands = new string[](2);
        graphCommands[0] = "python3";
        graphCommands[1] = "./py-utils/miner-pool/graph_buckets.py";
        vm.ffi(graphCommands);
    }
}
