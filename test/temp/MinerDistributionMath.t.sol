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
    
    function logWeeklyReward(uint id,MinerDistributionMath.WeeklyReward memory reward) public {
        console.logString("---------------------------------");
        console.log("id %s", id);
        console.log("inheritedFromLastWeek %s", reward.inheritedFromLastWeek);
        console.log("amountInBucket %s", reward.amountInBucket);
        console.log("amountToDeduct %s", reward.amountToDeduct);
        console.logString("---------------------------------");
    }

    function logBuckets(uint start,uint finish) public {
        for(uint i = start; i <= finish; i++) {
            logWeeklyReward(i,minerMath.reward(i));
        }
    }

    function saveBucketsToFile(uint start,uint end,string memory fileName) public {
        // deleteFile(fileName);
        vm.writeLine(fileName,"[");

        for(uint i = start; i <= end; i++) {
            MinerDistributionMath.WeeklyReward memory reward = minerMath.reward(i);
            string memory key1 = vm.serializeUint(string(abi.encodePacked(Strings.toString(i))),"id",i);
            string memory key2 = vm.serializeBool(string(abi.encodePacked(Strings.toString(i))),"inheritedFromLastWeek",reward.inheritedFromLastWeek);
            string memory key3 = vm.serializeUint(string(abi.encodePacked(Strings.toString(i))),"amountInBucket",reward.amountInBucket);
            //also add amountToDeduct
            string memory key4 = vm.serializeUint(string(abi.encodePacked(Strings.toString(i))),"amountToDeduct",reward.amountToDeduct);
            // string memory finalJson = vm.serializeString("","finalJson",jsonString);
            vm.writeLine(fileName, key4);
            if(i == end) break;
            vm.writeLine(fileName,",");
        }
        vm.writeLine(fileName,"]");

        showGraph();

    }

    function deleteFile(string memory fileName) public {
        string[] memory deleteFileCommands = new string[](2);
        deleteFileCommands[0] = "rm";
        deleteFileCommands[1] = fileName;
        vm.ffi(deleteFileCommands);
    }

    function showGraph() public {
        string[] memory graphCommands = new string[](2);
        graphCommands[0] = "py";
        graphCommands[1] = "graph_buckets.py";
        vm.ffi(graphCommands);
    }
    function test_Do() public {

        uint amountToAdd = 192_000;
        // minerMath.addToCurrentBucket(amountToAdd);
        uint oneWeek = uint(7 days);
        
        string memory jsonString;
        uint weeksToLoop = 210;
        for(uint i = 0; i < weeksToLoop; i++) {
            if(i>=20) {
                minerMath.addToCurrentBucket(0);
            } else {

                minerMath.addToCurrentBucket(amountToAdd);
            }
            vm.warp(block.timestamp + oneWeek);
        }

        for(uint i = 0; i < weeksToLoop; i++) {
            if(i==0){
                console.log("FIRST ID WE ARE PUSHING ON",minerMath.currentBucket());
            }
            if(i>=20) {
                minerMath.addToCurrentBucket(0);
            } else {

                minerMath.addToCurrentBucket(amountToAdd);
            }
            vm.warp(block.timestamp + oneWeek);
        }

        saveBucketsToFile(0, 310, "z_buckets.json");



    }
}