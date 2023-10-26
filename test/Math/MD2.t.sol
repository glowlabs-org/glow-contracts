// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import {MD2} from "@/temp/MD2.sol";
import "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MD2Handler} from "./Handlers/MD2Handler.t.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";
import {MockUSDCTax} from "@/testing/MockUSDCTax.sol";
import {IMinerPool} from "@/interfaces/IMinerPool.sol";

contract MD2Test is Test {
    address[] public grcTokens;

    //-----------------CONTRACTS-----------------
    MD2 minerMath;
    MockUSDC mockUsdc1;
    MockUSDC mockUsdc2;
    MockUSDCTax mockUsdcTax1;
    MockUSDC notGrcToken;
    MD2Handler handler;

    //------------- SETUP -------------
    /**
     * @dev we create all the contracts
     *         -   and assign fuzzing andinvariant_bucketMath_shouldMatchManualArray_badInvariant invariant targets
     *         -   we only test the addRewardsToBucket function inside the handler
     */
    function setUp() public {
        minerMath = new MD2();
        mockUsdc1 = new MockUSDC();
        mockUsdc2 = new MockUSDC();
        mockUsdcTax1 = new MockUSDCTax();
        notGrcToken = new MockUSDC();
        minerMath.addGRCToken(address(mockUsdc1));
        minerMath.addGRCToken(address(mockUsdc2));
        minerMath.addGRCToken(address(mockUsdcTax1));
        grcTokens.push(address(mockUsdc1));
        grcTokens.push(address(mockUsdc2));
        grcTokens.push(address(mockUsdcTax1));

        handler = new MD2Handler(address(minerMath),grcTokens);
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = MD2Handler.addRewardsToBucket.selector;
        selectors[1] = MD2Handler.addRewardsToBucketNoWarp.selector;
        FuzzSelector memory fs = FuzzSelector({selectors: selectors, addr: address(handler)});
        targetContract(address(handler));
    }

    //-----------------INVARIANTS-----------------

    // /**
    //  * @dev we test that all ghost buckets match the manual array
    //  */
    // function invariant_paginatedGetRewards_shouldMatchSingleReward() public {
    //     for (uint256 i; i < grcTokens.length; ++i) {
    //         uint256[] memory allGhostBucketIds = handler.allGhostBucketIds(grcTokens[i]);
    //         address grcToken = grcTokens[i];
    //         for (uint256 j; j < allGhostBucketIds.length; ++j) {
    //             uint256 bucketId = allGhostBucketIds[j];
    //             uint256 rewardInGhostMapping = handler.ghost_amountInBucket(bucketId, grcToken);
    //             MD2.WeeklyReward memory reward = minerMath.reward(grcToken, bucketId);
    //             MD2.WeeklyReward memory rewardPaginated = minerMath.getRewards(bucketId, bucketId + 1, grcToken)[0];
    //             assert(rewardPaginated.inheritedFromLastWeek == reward.inheritedFromLastWeek);
    //             assert(rewardPaginated.amountInBucket == reward.amountInBucket);
    //             assert(rewardPaginated.amountToDeduct == reward.amountToDeduct);
    //         }
    //     }
    // }

    /**
     * @dev we test that all ghost buckets match the manual array
     */

    function invariant_bucketMath_shouldMatchManualArray() public {
        for (uint256 i; i < grcTokens.length; ++i) {
            uint256[] memory allGhostBucketIds = handler.allGhostBucketIds(grcTokens[i]);
            address grcToken = grcTokens[i];
            uint256 totalForToken;
            for (uint256 j; j < allGhostBucketIds.length; ++j) {
                string memory fileName = string(
                    abi.encodePacked(
                        "test/Math/data/MD2/", Strings.toString(j), "-", Strings.toHexString(grcToken), ".json"
                    )
                );
                if (j == 0) {
                    // vm.writeLine(fileName, "[");
                }

                uint256 bucketId = allGhostBucketIds[j];
                uint256 rewardInGhostMapping = handler.ghost_amountInBucket(bucketId, grcToken);
                MD2.WeeklyReward memory reward = minerMath.reward(grcToken, bucketId);
                // string memory keyAddress = vm.serializeAddress(string(abi.encodePacked(Strings.toString(j))), "grcToken", grcToken);
                // vm.writeLine(fileName, keyAddress);
                // string memory key0 = vm.serializeUint(string(abi.encodePacked(Strings.toString(j))), "bucketId", bucketId);
                // string memory key1 = vm.serializeUint(string(abi.encodePacked(Strings.toString(j))), "id", j);
                // vm.writeLine(fileName, key1);
                // string memory key2 = vm.serializeBool(
                //     string(abi.encodePacked(Strings.toString(j))), "inheritedFromLastWeek", reward.inheritedFromLastWeek
                // );
                // vm.writeLine(fileName, key2);
                // string memory key3 =
                //     vm.serializeUint(string(abi.encodePacked(Strings.toString(j))), "amountInBucket", reward.amountInBucket);
                // vm.writeLine(fileName, key3);
                // //also add amountToDeduct
                // string memory key4 =
                //     vm.serializeUint(string(abi.encodePacked(Strings.toString(j))), "amountToDeduct", reward.amountToDeduct);
                // // string memory finalJson = vm.serializeString("","finalJson",jsonString);
                // vm.writeLine(fileName, key4);
                // string memory key5 = vm.serializeUint(string(abi.encodePacked(Strings.toString(j))), "rewardInGhostMapping", rewardInGhostMapping);
                // vm.writeLine(fileName, key5);

                assertTrue(reward.amountInBucket == rewardInGhostMapping);
                totalForToken += reward.amountInBucket;
                if (j == allGhostBucketIds.length - 1) {
                    // vm.writeLine(fileName, "]");
                }
            }

            assertEq(totalForToken, handler.totalDeposited(grcToken));
        }
    }

    /**
     * @dev we test that all ghost buckets match the manual array
     * forge-config: default.invariant.runs = 2
     * forge-config: default.invariant.depth = 30
     */
    function invariant_bucketMath_shouldMatchManualArray_badInvariant() public {
        for (uint256 i; i < grcTokens.length; ++i) {
            uint256 totalForToken;
            uint256[] memory allGhostBucketIds = handler.allGhostBucketIds(grcTokens[i]);
            address grcToken = grcTokens[i];
            for (uint256 j; j < allGhostBucketIds.length; ++j) {
                uint256 bucketId = allGhostBucketIds[j];
                uint256 rewardInGhostMapping = handler.ghost_amountInBucket(bucketId, grcToken);
                MD2.WeeklyReward memory reward = minerMath.reward(grcToken, bucketId);
                totalForToken += reward.amountInBucket;
                assertFalse(reward.amountInBucket + 1 == rewardInGhostMapping);
            }
            // ++count;

            assertEq(totalForToken, handler.totalDeposited(grcToken));
        }
        //Make s
    }

    //----------------- TESTS  -----------------

    function test_M2_manualSanityCheck() public {
        //Forward 100 weeks
        //Make sure that amount %  vesting periods = 0 so we dont get rounding errors in tests
        uint256 amountForContract1a = 12903890128321 * minerMath.TOTAL_VESTING_PERIODS();
        handler.addRewardsToBucketWithToken(address(mockUsdc1), 100 * 7, amountForContract1a);
        uint256 amountForContract2a = 2131312312 * minerMath.TOTAL_VESTING_PERIODS();
        handler.addRewardsToBucketWithToken(address(mockUsdc2), 50 * 7, amountForContract2a);

        uint256[] memory allGhostBucketIdsUsdc1 = handler.allGhostBucketIds(address(mockUsdc1));
        uint256[] memory allGhostBucketIdsUsdc2 = handler.allGhostBucketIds(address(mockUsdc2));

        for (uint256 i; i < allGhostBucketIdsUsdc1.length; ++i) {
            uint256 bucketId = allGhostBucketIdsUsdc1[i];
            MD2.WeeklyReward memory reward = minerMath.reward(address(mockUsdc1), bucketId);
            uint256 rewardInGhostMapping = handler.ghost_amountInBucket(bucketId, address(mockUsdc1));
            assertTrue(reward.amountInBucket == rewardInGhostMapping);
        }
        uint256 totalDepositedUsdc1 = handler.totalDeposited(address(mockUsdc1));
        assertTrue(totalDepositedUsdc1 == amountForContract1a);

        uint256 totalDepositedUsdc2 = handler.totalDeposited(address(mockUsdc2));
        assertTrue(totalDepositedUsdc2 == amountForContract2a);

        for (uint256 i; i < allGhostBucketIdsUsdc2.length; ++i) {
            uint256 bucketId = allGhostBucketIdsUsdc2[i];
            MD2.WeeklyReward memory reward = minerMath.reward(address(mockUsdc2), bucketId);
            uint256 rewardInGhostMapping = handler.ghost_amountInBucket(bucketId, address(mockUsdc2));
            assertTrue(reward.amountInBucket == rewardInGhostMapping);
        }

        uint256 amountForContract1b = 543252545 * minerMath.TOTAL_VESTING_PERIODS();
        handler.addRewardsToBucketWithToken(address(mockUsdc1), 0, amountForContract1b);
        uint256 amountForContract2b = 2131312312 * minerMath.TOTAL_VESTING_PERIODS();
        handler.addRewardsToBucketWithToken(address(mockUsdc2), 0, amountForContract2b);
        allGhostBucketIdsUsdc1 = handler.allGhostBucketIds(address(mockUsdc1));
        allGhostBucketIdsUsdc2 = handler.allGhostBucketIds(address(mockUsdc2));

        //Contract uses round robin
        for (uint256 i; i < allGhostBucketIdsUsdc1.length; ++i) {
            uint256 bucketId = allGhostBucketIdsUsdc1[i];
            MD2.WeeklyReward memory reward = minerMath.reward(address(mockUsdc1), bucketId);
            uint256 rewardInGhostMapping = handler.ghost_amountInBucket(bucketId, address(mockUsdc1));
            assertTrue(reward.amountInBucket == rewardInGhostMapping);
            bool failed = reward.amountInBucket != rewardInGhostMapping;
        }

        for (uint256 i; i < allGhostBucketIdsUsdc2.length; ++i) {
            uint256 bucketId = allGhostBucketIdsUsdc2[i];
            MD2.WeeklyReward memory reward = minerMath.reward(address(mockUsdc2), bucketId);
            uint256 rewardInGhostMapping = handler.ghost_amountInBucket(bucketId, address(mockUsdc2));
            assertTrue(reward.amountInBucket == rewardInGhostMapping);
        }

        totalDepositedUsdc1 = handler.totalDeposited(address(mockUsdc1));
        assertTrue(totalDepositedUsdc1 == amountForContract1b + amountForContract1a);
        totalDepositedUsdc2 = handler.totalDeposited(address(mockUsdc2));
        assertTrue(totalDepositedUsdc2 == amountForContract2b + amountForContract2a);
    }

    function test_getAmountForTokenAndInitIfNot() public {
        //Add to bucker 16 (since 0 + 16)
        minerMath.addToCurrentBucket(address(mockUsdc1), 10 ether);
        //vested amt is divided by 192 for vesting purposes
        uint256 expectedAmount = uint256(10 ether) / uint256(192);
        //Read the raw reward from the contract
        (bool inherited, uint256 amtInBucket, uint256 amountToDeduct) =
            minerMath.rawRewardInStorage(address(mockUsdc1), 17);
        //Inherited should be false, since we havent technically gotten to bucket 17 yet
        assert(!inherited);

        //This call will actually init the bucket
        uint256 amountInBucket = minerMath.getAmountForTokenAndInitIfNot(address(mockUsdc1), 17);
        assert(amountInBucket == expectedAmount);
        (inherited, amtInBucket, amountToDeduct) = minerMath.rawRewardInStorage(address(mockUsdc1), 17);
        //The raw inherited should be true and the rest should match the `reward`
        assert(inherited);
        MD2.WeeklyReward memory rewardAfterInit = minerMath.reward(address(mockUsdc1), 17);
        assert(rewardAfterInit.amountInBucket == amtInBucket);
        assert(rewardAfterInit.amountToDeduct == amountToDeduct);
        // assert(rewardAfterInit.inheritedFromLastWeek);

        minerMath.getAmountForTokenAndInitIfNot(address(mockUsdc1), 17);
        //If already inheirted nothing should change
        MD2.WeeklyReward memory rewardAfterInit2 = minerMath.reward(address(mockUsdc1), 17);
        assert(rewardAfterInit2.inheritedFromLastWeek);
        assert(rewardAfterInit2.amountInBucket == rewardAfterInit.amountInBucket);
        assert(rewardAfterInit2.amountToDeduct == rewardAfterInit.amountToDeduct);
    }

    function test_addTwiceToBucket_shouldCorrectlyCalculateRewards() public {
        minerMath.addToCurrentBucket(address(mockUsdc1), 10 ether);
        uint256 expectedAmount = uint256(10 ether) / uint256(192);
        vm.warp(block.timestamp + 7 days);
        uint256 currentBucket = minerMath.currentBucket();
        assert(currentBucket == 1);
        minerMath.addToCurrentBucket(address(mockUsdc1), 10 ether);

        uint256 amountInBucket = minerMath.getAmountForTokenAndInitIfNot(address(mockUsdc1), 17);
        assert(amountInBucket == expectedAmount * 2);

        //Add again to make sure
        minerMath.addToCurrentBucket(address(mockUsdc1), 10 ether);
        amountInBucket = minerMath.getAmountForTokenAndInitIfNot(address(mockUsdc1), 17);
        assert(amountInBucket == expectedAmount * 3);
    }

    function test_internalGenesisTimestamp_shouldAlwaysReturnZero() public {
        assert(minerMath.genesisTimestampInternal() == 0);
    }

    // /**
    //  * @dev function to test the addRewardsToBucket function
    //  *         -   we loop over 300 weeks,
    //  *         -   and add 192,000 to the current bucket
    //  *             - the 192,000 should be equally divided between 192 weeks
    //  *                 -   the first week being {currentBucket + 16}, and the last week
    //  *                 -   being {currentBucket + 208}
    //  *         -   we then save the bucket data to a file
    //  *         -   and then show the graph
    //  * @dev we only add rewards to the first 20 buckets, and then
    //  *             -   we add 0 to the other buckets to see if they correctly inherit from the previous week
    //  *             -   this is all inspected in the py-utils/miner-pool/data/buckets.json file
    //  */
    // function test_MinerPoolFFI() public {
    //     uint256 amountToAdd = 192_000;
    //     uint256 oneWeek = uint256(7 days);

    //     string memory jsonString;
    //     uint256 weeksToLoop = 300;
    //     for (uint256 i = 0; i < weeksToLoop; i++) {
    //         if (i >= 20) {
    //             if (i >= 200) {
    //                 minerMath.addToCurrentBucket(address(mockUsdc1),0);
    //             }
    //         } else {
    //             minerMath.addToCurrentBucket(address(mockUsdc1),amountToAdd);
    //         }
    //         vm.warp(block.timestamp + oneWeek);
    //     }

    //     saveBucketsToFile(0, 340, "py-utils/miner-pool/data/buckets.json");
    // }

    // //-----------------UTILS-----------------

    // /// @dev - helper function to log a reward for debug purposes
    // function logWeeklyReward(uint256 id, MD2.WeeklyReward memory reward) public {
    //     console.logString("---------------------------------");
    //     console.log("id %s", id);
    //     console.log("inheritedFromLastWeek %s", reward.inheritedFromLastWeek);
    //     console.log("amountInBucket %s", reward.amountInBucket);
    //     console.log("amountToDeduct %s", reward.amountToDeduct);
    //     console.logString("---------------------------------");
    // }

    // /// @dev - helper function to log a group of rewards for debug purposes
    // function logBuckets(uint256 start, uint256 finish) public {
    //     for (uint256 i = start; i <= finish; i++) {
    //         logWeeklyReward(i, minerMath.reward(address(mockUsdc1),i));
    //     }
    // }

    // /// @dev used to save the results of the bucket outputs to a file
    // ///     -   we used this during testing to generate the graph
    // ///     -   and to sanity check the results
    // function saveBucketsToFile(uint256 start, uint256 end, string memory fileName) public {
    //     deleteFile();
    //     vm.writeLine(fileName, "[");

    //     for (uint256 i = start; i <= end; i++) {
    //         MD2.WeeklyReward memory reward = minerMath.reward(address(mockUsdc1),i);
    //         string memory key1 = vm.serializeUint(string(abi.encodePacked(Strings.toString(i))), "id", i);
    //         string memory key2 = vm.serializeBool(
    //             string(abi.encodePacked(Strings.toString(i))), "inheritedFromLastWeek", reward.inheritedFromLastWeek
    //         );
    //         string memory key3 =
    //             vm.serializeUint(string(abi.encodePacked(Strings.toString(i))), "amountInBucket", reward.amountInBucket);
    //         //also add amountToDeduct
    //         string memory key4 =
    //             vm.serializeUint(string(abi.encodePacked(Strings.toString(i))), "amountToDeduct", reward.amountToDeduct);
    //         // string memory finalJson = vm.serializeString("","finalJson",jsonString);
    //         vm.writeLine(fileName, key4);
    //         if (i == end) break;
    //         vm.writeLine(fileName, ",");
    //     }
    //     vm.writeLine(fileName, "]");

    //     // showGraph();
    // }

    // /// @dev - helper function to delete the json file that contains the bucket outputs
    // function deleteFile() public {
    //     string[] memory deleteFileCommands = new string[](2);
    //     deleteFileCommands[0] = "py";
    //     deleteFileCommands[1] = "./py-utils/miner-pool/delete_file_if_exists.py";
    //     vm.ffi(deleteFileCommands);
    // }

    // /// @dev - helper function that generates the json and then shows the distribution of the buckets
    // function showGraph() public {
    //     string[] memory graphCommands = new string[](2);
    //     graphCommands[0] = "py";
    //     graphCommands[1] = "./py-utils/miner-pool/graph_buckets.py";
    //     vm.ffi(graphCommands);
    // }
}
