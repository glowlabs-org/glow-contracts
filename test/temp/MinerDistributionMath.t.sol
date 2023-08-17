// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import {MinerDistributionMath} from "@/temp/MinerDistributionMath.sol";
import "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract TokenTest is Test {
    MinerDistributionMath minerMath;

    function setUp() public {
        minerMath = new MinerDistributionMath();
    }

    function logWeeklyReward(uint256 id, MinerDistributionMath.WeeklyReward memory reward) public {
        console.logString("---------------------------------");
        console.log("id %s", id);
        console.log("inheritedFromLastWeek %s", reward.inheritedFromLastWeek);
        console.log("amountInBucket %s", reward.amountInBucket);
        console.log("amountToDeduct %s", reward.amountToDeduct);
        console.logString("---------------------------------");
    }

    function logBuckets(uint256 start, uint256 finish) public {
        for (uint256 i = start; i <= finish; i++) {
            logWeeklyReward(i, minerMath.reward(i));
        }
    }

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

        showGraph();
    }

    function deleteFile() public {
        string[] memory deleteFileCommands = new string[](2);
        deleteFileCommands[0] = "py";
        deleteFileCommands[1] = "./py-utils/miner-pool/delete_file_if_exists.py";
        vm.ffi(deleteFileCommands);
    }

    function showGraph() public {
        string[] memory graphCommands = new string[](2);
        graphCommands[0] = "py";
        graphCommands[1] = "./py-utils/miner-pool/graph_buckets.py";
        vm.ffi(graphCommands);
    }

    function test_MinerPoolFFI() public {
        uint256 amountToAdd = 192_000;
        // minerMath.addToCurrentBucket(amountToAdd);
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

        saveBucketsToFile(0, 340, "py-utils/miner-pool/data/buckets.json");
    }
}