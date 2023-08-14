// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "@/testing/TestGCC.sol";
import "forge-std/console.sol";
import {IGCA} from "@/interfaces/IGCA.sol";
import {MockGCA} from "@/GCA_AND_MINER_POOL//mock/MockGCA.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Governance} from "@/Governance.sol";
import {CarbonCreditAuction} from "@/CarbonCreditAuction.sol";
import "forge-std/StdUtils.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {TestGLOW} from "@/testing/TestGLOW.sol";


contract GCA_TEST is Test {
    MockGCA gca;
    TestGLOW glow;
    address governance = address(0x1);
    address earlyLiquidity = address(0x2);
    address vestingContract = address(0x3);
    address vetoCouncilAddress = address(0x4);
    address grantsTreasuryAddress = address(0x5);

    function setUp() public {
        glow = new TestGLOW(earlyLiquidity,vestingContract);
        address[] memory temp = new address[](0);
        gca = new MockGCA(temp,address(glow),governance);
        glow.setContractAddresses(address(gca), vetoCouncilAddress, grantsTreasuryAddress);
    }

    // function test_Constructor_shouldSetGenesisTimestampForGCAs() public {
    //     address[] memory gcaAddresses = _getAddressArray(5, 25);
    //     gca = new MockGCA(gcaAddresses,address(glow),governance);
    //     uint256 glwGenesisTimestamp = glow.GENESIS_TIMESTAMP();
    //     uint256 gcaGenesisTimestamp = gca.GENESIS_TIMESTAMP();
    //     assertTrue(glwGenesisTimestamp == gcaGenesisTimestamp);
    //     for (uint256 i; i < gcaAddresses.length; i++) {
    //         IGCA.GCAPayout memory payout = gca.gcaPayoutData(gcaAddresses[i]);
    //         assertEq(payout.lastClaimedTimestamp, gcaGenesisTimestamp);
    //     }
    // }

    // function test_setGCAs() public {
    //     //Create addresses in memory so we can set
    //     address[] memory gcaAddresses = _getAddressArray(5, 25);
    //     //Check addresses are not there yet
    //     for (uint256 i; i < gcaAddresses.length; i++) {
    //         assertFalse(gca.isGCA(gcaAddresses[i]));
    //         assertFalse(_containsElement(gca.allGcas(), gcaAddresses[i]));
    //     }
    //     //Set addresses
    //     gca.setGCAs(gcaAddresses);
    //     //Loop through and make sure
    //     /**
    //      * 1. Addresses are now GCAs
    //      *         2. Addresses are in allGcas
    //      *         3. Addresses have the correct compensation plan
    //      *             -   All shares for themselves in their plans
    //      *             -   No shares for others in their plans
    //      */
    //     for (uint256 i; i < gcaAddresses.length; i++) {
    //         assertTrue(gca.isGCA(gcaAddresses[i]));
    //         assertTrue(_containsElement(gca.allGcas(), gcaAddresses[i]));
    //         IGCA.ICompensation[] memory plans = gca.compensationPlan(gcaAddresses[i]);
    //         for (uint256 j; j < plans.length; j++) {
    //             if (plans[j].agent == gcaAddresses[i]) {
    //                 assertTrue(plans[j].shares == gca.SHARES_REQUIRED_PER_AGENT() * gcaAddresses.length);
    //             } else {
    //                 assertTrue(plans[j].shares == 0);
    //             }
    //         }
    //     }
    // }

    function testFuzz_amountNowAndSb(uint secondsSinceLastPayout) public {
        vm.assume(secondsSinceLastPayout < 14 days);
        uint256 shares = 1;
        uint256 totalShares = 1;
        (uint256 amountNow, uint256 slashableBalance) =
            gca.getAmountNowAndSB(secondsSinceLastPayout, shares, totalShares);
        uint rewardPerSecond = gca.REWARDS_PER_SECOND_FOR_ALL();
        uint256 vestingRate = gca.VESTING_REWARDS_PER_SECOND_FOR_ALL();
        uint vestedSum;
        for(uint i; i < secondsSinceLastPayout; i++){
            uint timeElapsed = secondsSinceLastPayout - i;
            uint vestedFromSecond = _min(timeElapsed * vestingRate, rewardPerSecond);
            vestedSum += vestedFromSecond;
        }
        //Account for division errors
        uint maxAcceptableDifference = 10 ** 14; //.00001
        // console.log("amountNow", amountNow);
        // console.log("Sum from loop", vestedSum);
        int256 diff = int256(amountNow) - int256(vestedSum);
        assertTrue(diff < int256(maxAcceptableDifference));
    }

    //------------------------ HELPERS -----------------------------
    function _getAddressArray(uint256 numAddresses, uint256 addressOffset) private pure returns (address[] memory) {
        address[] memory addresses = new address[](numAddresses);
        for (uint256 i = 0; i < numAddresses; i++) {
            addresses[i] = address(uint160(addressOffset + i));
        }
        return addresses;
    }

    function _containsElement(address[] memory arr, address element) private pure returns (bool) {
        for (uint256 i; i < arr.length; i++) {
            if (arr[i] == element) {
                return true;
            }
        }
        return false;
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        if (a < b) {
            return a;
        }
        return b;
    }
}
