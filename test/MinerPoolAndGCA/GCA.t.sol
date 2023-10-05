// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "@/testing/TestGCC.sol";
import "forge-std/console.sol";
import {IGCA} from "@/interfaces/IGCA.sol";
import {MockGCA} from "@/MinerPoolAndGCA/mock/MockGCA.sol";
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
    address SIMON = address(0x6);
    address OTHER_GCA = address(0x7);
    uint256 constant ONE_WEEK = 7 * uint256(1 days);
    uint256 constant _UINT256_MAX_DIV5 = type(uint256).max / 5;
    uint256 constant _200_BILLION = 200_000_000_000 ether;

    function setUp() public {
        glow = new TestGLOW(earlyLiquidity,vestingContract);
        address[] memory temp = new address[](0);
        gca = new MockGCA(temp,address(glow),governance);
        glow.setContractAddresses(address(gca), vetoCouncilAddress, grantsTreasuryAddress);
    }

    //-------- ISSUING REPORTS ---------//
    function addGCA(address newGCA) public {
        address[] memory allGCAs = gca.allGcas();
        address[] memory temp = new address[](allGCAs.length+1);
        for (uint256 i; i < allGCAs.length; i++) {
            temp[i] = allGCAs[i];
            if (allGCAs[i] == newGCA) {
                return;
            }
        }
        temp[allGCAs.length] = newGCA;
        gca.setGCAs(temp);
        allGCAs = gca.allGcas();
        assertTrue(_containsElement(allGCAs, newGCA));
    }

    function issueReport(uint256 lengthOfReports) public {
        addGCA(SIMON);
        //Current bucket should be zero, let's see if we can add to it
        uint256 currentBucket = 0;
        uint256 totalNewGCC = 100 ether;
        uint256 totalGlwRewardsWeight = 100 ether;
        uint256 totalGRCRewardsWeight = 100 ether;
        //Use a random root for now
        bytes32 randomMerkleRoot = keccak256("random");

        //------ START PRANK ------
        vm.startPrank(SIMON);

        gca.issueWeeklyReport(
            currentBucket, totalNewGCC, totalGlwRewardsWeight, totalGRCRewardsWeight, randomMerkleRoot
        );

        vm.stopPrank();
        //------ STOP PRANK ------

        IGCA.Bucket memory bucket = gca.bucket(currentBucket);
        assertEq(bucket.reports.length, lengthOfReports);
        assertEq(bucket.nonce, 0);
        assertEq(bucket.reinstated, false);
        //TODO: Add a check for the bucket finalization timestamp to make sure it's correct.
        assertTrue(bucket.finalizationTimestamp > 0);
        IGCA.Report memory report = bucket.reports[0];
        assertEq(report.totalNewGCC, totalNewGCC);
        assertEq(report.totalGLWRewardsWeight, totalGlwRewardsWeight);
        assertEq(report.totalGRCRewardsWeight, totalGRCRewardsWeight);
        assertEq(report.merkleRoot, randomMerkleRoot);
        assertEq(report.proposingAgent, SIMON);
    }

    function test_issueReport() public {
        issueReport(1);
    }

    function issueReport_newSubmissionShouldOverrideOldOne(uint256 lengthOfReports) public {
        issueReport(lengthOfReports);
        uint256 currentBucket = 0;
        uint256 totalNewGCC = 101 ether;
        uint256 totalGlwRewardsWeight = 105 ether;
        uint256 totalGRCRewardsWeight = 101 ether;
        //Use a random root for now
        bytes32 randomMerkleRoot = keccak256("random but different");

        //------ START PRANK ------
        vm.startPrank(SIMON);

        gca.issueWeeklyReport(
            currentBucket, totalNewGCC, totalGlwRewardsWeight, totalGRCRewardsWeight, randomMerkleRoot
        );

        vm.stopPrank();
        //------ STOP PRANK ------

        IGCA.Bucket memory bucket = gca.bucket(currentBucket);
        assertEq(bucket.reports.length, lengthOfReports);
        assertEq(bucket.nonce, 0);
        assertEq(bucket.reinstated, false);
        //TODO: Add a check for the bucket finalization timestamp to make sure it's correct.

        IGCA.Report memory report = bucket.reports[0];
        assertEq(report.totalNewGCC, totalNewGCC);
        assertEq(report.totalGLWRewardsWeight, totalGlwRewardsWeight);
        assertEq(report.totalGRCRewardsWeight, totalGRCRewardsWeight);
        assertEq(report.merkleRoot, randomMerkleRoot);
        assertEq(report.proposingAgent, SIMON);
    }

    function test_issueReport_newSubmissionShouldOverrideOldOne() public {
        issueReport_newSubmissionShouldOverrideOldOne(1);
    }

    function test_issueReport_newGCAShouldCreateNewReport() public {
        test_issueReport();
        addGCA(OTHER_GCA);

        uint256 currentBucket = 0;
        uint256 totalNewGCC = 201 ether;
        uint256 totalGlwRewardsWeight = 205 ether;
        uint256 totalGRCRewardsWeight = 204 ether;
        //Use a random root for now
        bytes32 randomMerkleRoot = keccak256("random but different again");

        //------ START PRANK ------
        vm.startPrank(OTHER_GCA);

        gca.issueWeeklyReport(
            currentBucket, totalNewGCC, totalGlwRewardsWeight, totalGRCRewardsWeight, randomMerkleRoot
        );

        vm.stopPrank();
        //------ STOP PRANK ------

        IGCA.Bucket memory bucket = gca.bucket(currentBucket);
        assertEq(bucket.reports.length, 2);
        assertEq(bucket.nonce, 0);
        assertEq(bucket.reinstated, false);

        IGCA.Report memory report = bucket.reports[1];
        assertEq(report.totalNewGCC, totalNewGCC);
        assertEq(report.totalGLWRewardsWeight, totalGlwRewardsWeight);
        assertEq(report.totalGRCRewardsWeight, totalGRCRewardsWeight);
        assertEq(report.merkleRoot, randomMerkleRoot);
        assertEq(report.proposingAgent, OTHER_GCA);
    }

    function test_issueReport_oldReportShouldOverride_whenMultipleReportsInBucket() public {
        test_issueReport();
        test_issueReport_newGCAShouldCreateNewReport();
        issueReport_newSubmissionShouldOverrideOldOne(2);
    }

    function test_issueReport_weightMoreThanUint256Div5_shouldRevert() public {
        addGCA(SIMON);
        vm.startPrank(SIMON);
        uint256 currentBucket = 0;
        uint256 totalNewGCC = 101 ether;
        uint256 totalGlwRewardsWeight = _UINT256_MAX_DIV5 + 1;
        uint256 totalGRCRewardsWeight = 101 ether;
        //Use a random root for now
        bytes32 root = keccak256("random but different");

        vm.expectRevert(IGCA.ReportWeightMustBeLTUintMaxDiv5.selector);
        gca.issueWeeklyReport(currentBucket, totalNewGCC, totalGlwRewardsWeight, totalGRCRewardsWeight, root);

        totalGlwRewardsWeight = 1;
        totalGRCRewardsWeight = _UINT256_MAX_DIV5 + 1;
        vm.expectRevert(IGCA.ReportWeightMustBeLTUintMaxDiv5.selector);
        gca.issueWeeklyReport(currentBucket, totalNewGCC, totalGlwRewardsWeight, totalGRCRewardsWeight, root);

        vm.stopPrank();
    }

    function test_issueReport_moreThan200BillionGCC_shouldRevert() public {
        addGCA(SIMON);
        vm.startPrank(SIMON);
        uint256 currentBucket = 0;
        uint256 totalNewGCC = _200_BILLION + 1;
        uint256 totalGlwRewardsWeight = 105 ether;
        uint256 totalGRCRewardsWeight = 101 ether;
        //Use a random root for now
        bytes32 root = keccak256("random but different");

        vm.expectRevert(IGCA.ReportGCCMustBeLT200Billion.selector);
        gca.issueWeeklyReport(currentBucket, totalNewGCC, totalGlwRewardsWeight, totalGRCRewardsWeight, root);

        vm.stopPrank();
    }

    function test_issueReport_submittingAfterSubmissionShouldRevert() public {
        test_issueReport();
        //Let's get the bucket finalization timestamp so we can submit 1 week before it
        IGCA.Bucket memory bucket = gca.bucket(0);
        uint256 finalizationTimestamp = bucket.finalizationTimestamp;
        uint256 submissionEndTimestamp = finalizationTimestamp - ONE_WEEK;
        vm.warp(submissionEndTimestamp);

        vm.startPrank(SIMON);
        uint256 currentBucket = 0;
        uint256 totalNewGCC = 101 ether;
        uint256 totalGlwRewardsWeight = 105 ether;
        uint256 totalGRCRewardsWeight = 101 ether;
        //Use a random root for now
        bytes32 randomMerkleRoot = keccak256("random but different");

        vm.expectRevert(IGCA.BucketSubmissionEnded.selector);
        gca.issueWeeklyReport(
            currentBucket, totalNewGCC, totalGlwRewardsWeight, totalGRCRewardsWeight, randomMerkleRoot
        );

        vm.stopPrank();
    }

    function test_issueReport_submittingBeforeBucketOpenShouldRevert() public {
        addGCA(SIMON);
        vm.startPrank(SIMON);
        uint256 currentBucket = 1;
        uint256 totalNewGCC = 101 ether;
        uint256 totalGlwRewardsWeight = 105 ether;
        uint256 totalGRCRewardsWeight = 101 ether;
        //Use a random root for now
        bytes32 randomMerkleRoot = keccak256("random but different");

        vm.expectRevert(IGCA.BucketSubmissionNotOpen.selector);
        gca.issueWeeklyReport(
            currentBucket, totalNewGCC, totalGlwRewardsWeight, totalGRCRewardsWeight, randomMerkleRoot
        );

        vm.stopPrank();
    }

    function test_Constructor_shouldSetGenesisTimestampForGCAs() public {
        address[] memory gcaAddresses = _getAddressArray(5, 25);
        gca = new MockGCA(gcaAddresses,address(glow),governance);
        uint256 glwGenesisTimestamp = glow.GENESIS_TIMESTAMP();
        uint256 gcaGenesisTimestamp = gca.GENESIS_TIMESTAMP();
        assertTrue(glwGenesisTimestamp == gcaGenesisTimestamp);
        for (uint256 i; i < gcaAddresses.length; i++) {
            IGCA.GCAPayout memory payout = gca.gcaPayoutData(gcaAddresses[i]);
            assertEq(payout.lastClaimedTimestamp, gcaGenesisTimestamp);
        }
    }

    function test_setGCAs() public {
        //Create addresses in memory so we can set
        address[] memory gcaAddresses = _getAddressArray(5, 25);
        //Check addresses are not there yet
        for (uint256 i; i < gcaAddresses.length; i++) {
            assertFalse(gca.isGCA(gcaAddresses[i]));
            assertFalse(_containsElement(gca.allGcas(), gcaAddresses[i]));
        }
        //Set addresses
        gca.setGCAs(gcaAddresses);
        //Loop through and make sure
        /**
         * 1. Addresses are now GCAs
         *         2. Addresses are in allGcas
         *         3. Addresses have the correct compensation plan
         *             -   All shares for themselves in their plans
         *             -   No shares for others in their plans
         */
        for (uint256 i; i < gcaAddresses.length; i++) {
            assertTrue(gca.isGCA(gcaAddresses[i]));
            assertTrue(_containsElement(gca.allGcas(), gcaAddresses[i]));
            IGCA.ICompensation[] memory plans = gca.compensationPlan(gcaAddresses[i]);
            for (uint256 j; j < plans.length; j++) {
                (uint256 shares, uint256 totalShares) = gca.getShares(gcaAddresses[i]);
                if (plans[j].agent == gcaAddresses[i]) {
                    assertTrue(plans[j].shares == gca.SHARES_REQUIRED_PER_COMP_PLAN());
                } else {
                    assertTrue(plans[j].shares == 0);
                }
                assertEq(totalShares, gca.SHARES_REQUIRED_PER_COMP_PLAN() * gcaAddresses.length);
                assertEq(shares, gca.SHARES_REQUIRED_PER_COMP_PLAN());
            }
        }
    }

    //------------------------ PAYMENTS -----------------------------
    function testFuzz_amountNowAndSb(uint256 secondsSinceLastPayout) public {
        vm.assume(secondsSinceLastPayout < 14 days);
        uint256 shares = 1;
        uint256 totalShares = 1;
        (uint256 amountNow, uint256 slashableBalance) =
            gca.getAmountNowAndSB(secondsSinceLastPayout, shares, totalShares);
        uint256 rewardPerSecond = gca.REWARDS_PER_SECOND_FOR_ALL();
        uint256 vestingRate = gca.VESTING_REWARDS_PER_SECOND_FOR_ALL();
        uint256 vestedSum;
        for (uint256 i; i < secondsSinceLastPayout; i++) {
            uint256 timeElapsed = secondsSinceLastPayout - i;
            uint256 vestedFromSecond = _min(timeElapsed * vestingRate, rewardPerSecond);
            vestedSum += vestedFromSecond;
        }
        //Account for division errors
        uint256 maxAcceptableDifference = 10 ** 10; //.00000001 tokens
        // console.log("amountNow", amountNow);
        // console.log("Sum from loop", vestedSum);
        int256 diff = int256(amountNow) - int256(vestedSum);
        assertTrue(diff < int256(maxAcceptableDifference));
    }

    //------------------------ GOVERNANCE CALLS -----------------------------
    function test_setRequirements_callerNotGovernance_shouldFail() public {
        vm.expectRevert(IGCA.CallerNotGovernance.selector);
        gca.setRequirementsHash(bytes32("new hash"));
    }

    function test_setRequirements_callerNotGovernance_shouldWork() public {
        vm.startPrank(governance);
        gca.setRequirementsHash(bytes32("new hash"));
        assertEq(gca.requirementsHash(), bytes32("new hash"));
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
