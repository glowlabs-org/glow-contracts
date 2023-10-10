// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {VestingMathLib} from "@/libraries/VestingMathLib.sol";
import {ProofOfConceptVestingLib} from "@/libraries/VestingMathLib.sol";

contract VestingMathLibTest is Test {
    uint256 public constant REWARDS_PER_SECOND = uint256(10_000 ether) / uint256((86400 * 7));
    //------------- SETUP -------------
    ProofOfConceptVestingLib s;
    address defaultAgent = address(0xffffaaaaadddd);
    /**
     * @dev we create all the contracts
     *         -   and assign fuzzing andinvariant_bucketMath_shouldMatchManualArray_badInvariant invariant targets
     *         -   we only test the addRewardsToBucket function inside the handler
     */

    function setUp() public {
        s = new ProofOfConceptVestingLib();
    }

    function test_vestingMathLib() public {
        console.log("rewards per second = %s", REWARDS_PER_SECOND);
        s.addAgent(defaultAgent);
        vm.warp(block.timestamp + 1 weeks);

        s.claimPayout(defaultAgent, 0);
        (uint256 withdrawableAmount, uint256 slashableBalance) = s.payoutData(defaultAgent, 0);

        console.log("withdrawableAmount: %s", withdrawableAmount);
        console.log("slashableBalance: %s", slashableBalance);
        // logPayoutHelper(s.payoutHelper(defaultAgent, 0));
        // console.log("withdrawableAmount: %s", withdrawableAmount);
        // console.log("slashableAmount: %s", slashableAmount);
    }

    function logPayoutHelper(ProofOfConceptVestingLib.PayoutHelper memory helper) internal {
        console.log("shiftStartTimestamp: %s", helper.shiftStartTimestamp);
        console.log("shiftEndTimestamp: %s", helper.shiftEndTimestamp);
        console.log("rewardPerSecond: %s", helper.rewardPerSecond);
        console.log("amountAlreadyWithdrawn: %s", helper.amountAlreadyWithdrawn);
    }
}

/**
 * withdrawableAmount: 7812501033399466320000
 *   slashableAmount: 117187498966600530720000
 *            8438, 116562
 */

/**
 * Withdraw: 7768174430842560, Slash: 7743871864937535552
 *
 * withdrawableAmount: 2000016534391505280
 *   slashableAmount: 1997999983465608447360
 */
