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
import {Handler} from "./Handlers/Handler.GCA.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MerkleProofLib} from "@solady/utils/MerkleProofLib.sol";
//TODO: add invariant for total inside global state and the sum of reports
//TODO: add max length to set GCA contract?
//TODO: add tests for withdrawing

contract GCATest is Test {
    //--------  CONTRACTS ---------//
    MockGCA gca;
    TestGLOW glow;
    Handler handler;

    //--------  ADDRESSES ---------//
    address governance = address(0x1);
    address earlyLiquidity = address(0x2);
    address vestingContract = address(0x3);
    address vetoCouncilAddress = address(0x4);
    address grantsTreasuryAddress = address(0x5);
    address SIMON = address(0x6);
    address OTHER_GCA = address(0x7);
    address OTHER_GCA_2 = address(0x8);
    address OTHER_GCA_3 = address(0x9);
    address OTHER_GCA_4 = address(0x10);

    //--------  CONSTANTS ---------//
    uint256 constant ONE_WEEK = 7 * uint256(1 days);
    uint256 constant _UINT64_MAX_DIV5 = type(uint64).max / 5;
    uint256 constant _200_BILLION = 200_000_000_000 * 1e18;

    function setUp() public {
        //Make sure we don't start at 0
        vm.warp(10);
        glow = new TestGLOW(earlyLiquidity,vestingContract);
        address[] memory temp = new address[](0);
        gca = new MockGCA(temp,address(glow),governance);
        glow.setContractAddresses(address(gca), vetoCouncilAddress, grantsTreasuryAddress);
        handler = new Handler(address(gca));
        addGCA(address(handler));
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = Handler.issueWeeklyReport.selector;
        selectors[1] = Handler.issueWeeklyReportCurrentBucket.selector;
        selectors[2] = Handler.incrementSlashNonce.selector;
        selectors[3] = Handler.warp.selector;

        FuzzSelector memory fs = FuzzSelector({selectors: selectors, addr: address(handler)});
        targetSender(SIMON);
        targetSender(OTHER_GCA);
        targetSender(OTHER_GCA_2);
        targetSender(OTHER_GCA_3);
        targetSender(OTHER_GCA_4);
        targetContract(address(handler));
    }

    // /**

    /**
     * forge-config: default.invariant.runs = 10
     * forge-config: default.invariant.depth = 100
     * @dev buckets nonces should never change
     *     -   and should always be zero if they didn't get initialized during their current week
     *         -   if they're not initialized that means that they submitted the first report for the bucket
     */
    function invariant_bucketNonceShouldNeverChangeGas() public {
        uint256[] memory bucketIds = handler.ghost_bucketIds();
        for (uint256 i; i < bucketIds.length; i++) {
            uint256 bucketId = bucketIds[i];
            IGCA.Bucket memory bucket = gca.bucket(bucketId);
            bool initOnCurrentWeek = handler.initOnCurrentWeek(bucketId);
            if (initOnCurrentWeek) {
                assertEq(bucket.originalNonce, handler.bucketIdToSlashNonce(bucketId));
            } else {
                assertEq(bucket.originalNonce, 0);
            }
        }
    }

    /**
     * forge-config: default.invariant.runs = 100
     * forge-config: default.invariant.depth = 100
     */
    function invariant_bucketGlobalState_shouldMatchSumOfReports() public {
        uint256[] memory bucketIds = handler.ghost_bucketIds();
        for (uint256 i; i < bucketIds.length; ++i) {
            uint256 bucketId = bucketIds[i];
            IGCA.BucketGlobalState memory state = gca.bucketGlobalState(bucketId);
            uint256 totalNewGCCInBucket;
            uint256 totalGlowWeightInBucket;
            uint256 totalGRCWeightInBucket;
            IGCA.Report[] memory reports = gca.bucket(bucketId).reports;
            for (uint256 j; j < reports.length; ++j) {
                totalNewGCCInBucket += reports[j].totalNewGCC;
                totalGlowWeightInBucket += reports[j].totalGLWRewardsWeight;
                totalGRCWeightInBucket += reports[j].totalGRCRewardsWeight;
            }

            assertEq(totalNewGCCInBucket, state.totalNewGCC);
            assertEq(totalNewGCCInBucket, state.totalNewGCC);
            assertEq(totalNewGCCInBucket, state.totalNewGCC);
        }
    }

    function testFuzz_invalidBucketSubmission_shouldAlwaysRevert(uint256 bucketId) public {
        //Each bucket last's 1 week, so there will realistically never be a bucket with an id greater than 1e18
        bucketId = bound(bucketId, 0, 1 * 1e15);
        uint256 genesis = gca.GENESIS_TIMESTAMP();
        assertEq(genesis, 10);
        addGCA(SIMON);
        vm.startPrank(SIMON);
        uint256 submissionStartTimestamp = gca.bucketStartSubmissionTimestampNotReinstated(bucketId);
        uint256 submissionEndTimestamp = gca.bucketEndSubmissionTimestampNotReinstated(bucketId);

        assertEq(submissionStartTimestamp, submissionEndTimestamp - ONE_WEEK);
        vm.warp(submissionStartTimestamp - 1);

        vm.expectRevert(IGCA.BucketSubmissionNotOpen.selector);
        gca.issueWeeklyReport(bucketId, 1, 1, 1, bytes32("random"));

        vm.warp(submissionEndTimestamp + 1);
        vm.expectRevert(IGCA.BucketSubmissionEnded.selector);
        gca.issueWeeklyReport(bucketId, 1, 1, 1, bytes32("random"));

        vm.stopPrank();
    }

    function testFuzz_invalidBucketSubmission_nonInitBucket_withDifferentSlashNonce_shouldAlwaysRevert(uint256 bucketId)
        public
    {
        bucketId = bound(bucketId, 0, 1 * 1e15);
        addGCA(SIMON);
        vm.startPrank(SIMON);
        uint256 submissionStartTimestamp = gca.bucketStartSubmissionTimestampNotReinstated(bucketId);

        //We increment the nonces
        //Therefore, we know that the bucket will not be initialized and slashNonce != 0
        gca.incrementSlashNonce();
        //since the bucket is not init it should always be zero
        uint256 submissionEndTimestamp = gca.bucketEndSubmissionTimestampNotReinstated(bucketId);
        uint256 submissionEndTimestamp2 = gca.calculateBucketSubmissionEndTimestamp(bucketId);
        assertEq(submissionEndTimestamp, submissionEndTimestamp2);
        vm.warp(submissionStartTimestamp - 1);

        vm.expectRevert(IGCA.BucketSubmissionNotOpen.selector);
        gca.issueWeeklyReport(bucketId, 1, 1, 1, bytes32("random"));

        vm.warp(submissionEndTimestamp + 1);
        vm.expectRevert(IGCA.BucketSubmissionEnded.selector);
        gca.issueWeeklyReport(bucketId, 1, 1, 1, bytes32("random"));

        vm.stopPrank();
    }

    function testFuzz_invalidBucketSubmission_initBucket_withDifferentSlashNonce_shouldAlwaysRevert(uint256 bucketId)
        public
    {
        bucketId = bound(bucketId, 0, 1 * 1e15);
        addGCA(SIMON);
        vm.startPrank(SIMON);
        uint256 submissionStartTimestamp = gca.bucketStartSubmissionTimestampNotReinstated(bucketId);

        vm.warp(submissionStartTimestamp);
        //Create it
        gca.issueWeeklyReport(bucketId, 1, 1, 1, bytes32("random"));

        //Bucket is init and it's slash nonce != slashNonce in storage
        gca.incrementSlashNonce();
        //since the bucket is not init it should always be zero
        uint256 submissionEndTimestamp = gca.WCEIL(gca.bucket(bucketId).originalNonce);
        uint256 submissionEndTimestamp2 = gca.calculateBucketSubmissionEndTimestamp(bucketId);
        assertEq(submissionEndTimestamp, submissionEndTimestamp2);

        vm.warp(submissionEndTimestamp + 1);
        vm.expectRevert(IGCA.BucketSubmissionEnded.selector);
        gca.issueWeeklyReport(bucketId, 1, 1, 1, bytes32("ran2dom"));

        vm.stopPrank();
    }

    function test_invalidBucketSubmission_initBucket_withDifferentSlashNonce_shouldAlwaysRevert() public {
        uint256 bucketId = 2;
        bucketId = bound(bucketId, 0, 1 * 1e15);
        addGCA(SIMON);
        vm.startPrank(SIMON);
        uint256 submissionStartTimestamp = gca.bucketStartSubmissionTimestampNotReinstated(bucketId);

        vm.warp(submissionStartTimestamp);
        //Create it
        uint256 bucketSubmissionEndTimestamp = gca.calculateBucketSubmissionEndTimestamp(bucketId);

        gca.issueWeeklyReport(bucketId, 1, 1, 1, bytes32("random"));

        //Bucket is init and it's slash nonce != slashNonce in storage
        gca.incrementSlashNonce();
        //since the bucket is not init it should always be zero
        uint256 submissionEndTimestamp = gca.calculateBucketSubmissionEndTimestamp(bucketId);
        //It should also equal the wceil of 0 since the first nonce as 0
        assertEq(submissionEndTimestamp, gca.WCEIL(0));
        vm.warp(submissionEndTimestamp + 1);
        vm.expectRevert(IGCA.BucketSubmissionEnded.selector);
        gca.issueWeeklyReport(bucketId, 1, 1, 1, bytes32("ran2dom"));

        vm.stopPrank();
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

    function issueReport(
        address gcaToSubmitAs,
        uint256 bucket,
        uint256 totalNewGCC,
        uint256 totalGlwRewardsWeight,
        uint256 totalGRCRewardsWeight,
        bytes32 randomMerkleRoot
    ) public {
        addGCA(gcaToSubmitAs);
        //Current bucket should be zero, let's see if we can add to it
        uint256 currentBucket = bucket;

        //------ START PRANK ------
        vm.startPrank(gcaToSubmitAs);

        gca.issueWeeklyReport(
            currentBucket, totalNewGCC, totalGlwRewardsWeight, totalGRCRewardsWeight, randomMerkleRoot
        );

        vm.stopPrank();
        //------ STOP PRANK ------
    }

    function checkBucketAndReport(
        uint256 bucketId,
        uint256 reportIndex,
        uint256 expectedNonce,
        uint256 expectedReportsLength,
        uint256 expectedLastUpdatedNonce,
        uint256 expectedReportTotalNewGCC,
        uint256 expectedReportTotalGLWRewardsWeight,
        uint256 expectedReportTotalGRCRewardsWeight,
        bytes32 expectedMerkleRoot,
        address expectedProposingAgent
    ) internal {
        IGCA.Bucket memory bucket = gca.bucket(bucketId);
        assertEq(bucket.reports.length, expectedReportsLength);
        assertEq(bucket.originalNonce, expectedNonce);
        assertEq(bucket.lastUpdatedNonce, expectedLastUpdatedNonce);
        //TODO: Add a check for the bucket finalization timestamp to make sure it's correct.
        assertTrue(bucket.finalizationTimestamp > 0);
        IGCA.Report memory report = bucket.reports[reportIndex];
        assertEq(report.totalNewGCC, expectedReportTotalNewGCC);
        assertEq(report.totalGLWRewardsWeight, expectedReportTotalGLWRewardsWeight);
        assertEq(report.totalGRCRewardsWeight, expectedReportTotalGRCRewardsWeight);
        assertEq(report.merkleRoot, expectedMerkleRoot);
        assertEq(report.proposingAgent, expectedProposingAgent);
    }

    function checkBucketGlobalState(
        uint256 bucketId,
        uint256 expectedTotalNewGCC,
        uint256 expectedTotalGLWRewardsWeight,
        uint256 expectedTotalGRCRewardsWeight
    ) internal {
        IGCA.BucketGlobalState memory state = gca.bucketGlobalState(bucketId);
        assertEq(state.totalNewGCC, expectedTotalNewGCC);
        assertEq(state.totalGLWRewardsWeight, expectedTotalGLWRewardsWeight);
        assertEq(state.totalGRCRewardsWeight, expectedTotalGRCRewardsWeight);
    }

    function test_issueReport() public {
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 100 * 1e15,
            totalGlwRewardsWeight: 100 * 1e15,
            totalGRCRewardsWeight: 100 * 1e15,
            randomMerkleRoot: keccak256("random but different")
        });

        checkBucketAndReport({
            bucketId: 0,
            reportIndex: 0,
            expectedNonce: 0,
            expectedReportsLength: 1,
            expectedLastUpdatedNonce: 0,
            expectedReportTotalNewGCC: 100 * 1e15,
            expectedReportTotalGLWRewardsWeight: 100 * 1e15,
            expectedReportTotalGRCRewardsWeight: 100 * 1e15,
            expectedMerkleRoot: keccak256("random but different"),
            expectedProposingAgent: SIMON
        });
    }

    function test_issueReport_andCheckGlobalState() public {
        test_issueReport();
        checkBucketGlobalState({
            bucketId: 0,
            expectedTotalNewGCC: 100 * 1e15,
            expectedTotalGLWRewardsWeight: 100 * 1e15,
            expectedTotalGRCRewardsWeight: 100 * 1e15
        });
    }

    function test_issueReport_newSubmissionShouldOverrideOldOne() public {
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 100 * 1e15,
            totalGlwRewardsWeight: 100 * 1e15,
            totalGRCRewardsWeight: 100 * 1e15,
            randomMerkleRoot: keccak256("random but different")
        });

        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 102 * 1e15,
            totalGlwRewardsWeight: 103 * 1e15,
            totalGRCRewardsWeight: 104 * 1e15,
            randomMerkleRoot: keccak256("random but differents")
        });

        checkBucketAndReport({
            bucketId: 0,
            reportIndex: 0,
            expectedNonce: 0,
            expectedReportsLength: 1,
            expectedLastUpdatedNonce: 0,
            expectedReportTotalNewGCC: 102 * 1e15,
            expectedReportTotalGLWRewardsWeight: 103 * 1e15,
            expectedReportTotalGRCRewardsWeight: 104 * 1e15,
            expectedMerkleRoot: keccak256("random but differents"),
            expectedProposingAgent: SIMON
        });
    }

    function test_issueReport_newGCAShouldCreateNewReport() public {
        //Create's one as simon
        /**
         * This should have
         *         totalNewGCC: 100 * 1e15,
         *         totalGlwRewardsWeight: 100 * 1e15,
         *         totalGRCRewardsWeight: 100 * 1e15,
         */
        test_issueReport();
        uint256 totalNewGCCBefore = gca.bucketGlobalState(0).totalNewGCC;
        uint256 totalGLWRewardsWeightBefore = gca.bucketGlobalState(0).totalGLWRewardsWeight;
        uint256 totalGRCRewardsWeightBefore = gca.bucketGlobalState(0).totalGRCRewardsWeight;

        addGCA(OTHER_GCA);

        uint256 currentBucket = 0;
        uint256 totalNewGCC = 201 * 1e15;
        uint256 totalGlwRewardsWeight = 205 * 1e15;
        uint256 totalGRCRewardsWeight = 204 * 1e15;
        //Use a random root for now
        bytes32 randomMerkleRoot = keccak256("random but different again");

        //------ START PRANK ------//
        issueReport({
            gcaToSubmitAs: OTHER_GCA,
            bucket: currentBucket,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwRewardsWeight,
            totalGRCRewardsWeight: totalGRCRewardsWeight,
            randomMerkleRoot: randomMerkleRoot
        });

        vm.startPrank(OTHER_GCA);

        vm.stopPrank();
        //------ STOP PRANK ------

        checkBucketAndReport({
            bucketId: currentBucket,
            reportIndex: 1,
            expectedNonce: 0,
            expectedReportsLength: 2,
            expectedLastUpdatedNonce: 0,
            expectedReportTotalNewGCC: totalNewGCC,
            expectedReportTotalGLWRewardsWeight: totalGlwRewardsWeight,
            expectedReportTotalGRCRewardsWeight: totalGRCRewardsWeight,
            expectedMerkleRoot: randomMerkleRoot,
            expectedProposingAgent: OTHER_GCA
        });

        checkBucketGlobalState({
            bucketId: currentBucket,
            expectedTotalNewGCC: totalNewGCCBefore + totalNewGCC,
            expectedTotalGLWRewardsWeight: totalGLWRewardsWeightBefore + totalGlwRewardsWeight,
            expectedTotalGRCRewardsWeight: totalGRCRewardsWeightBefore + totalGRCRewardsWeight
        });
    }

    function test_issueReport_oldReportShouldOverride_whenMultipleReportsInBucket() public {
        //This issues as SIMON in first index
        test_issueReport();

        //This issues as OTHER_GCA in second index
        test_issueReport_newGCAShouldCreateNewReport();

        uint256 totalNewGCCBefore = gca.bucketGlobalState(0).totalNewGCC;
        uint256 totalGLWRewardsWeightBefore = gca.bucketGlobalState(0).totalGLWRewardsWeight;
        uint256 totalGRCRewardsWeightBefore = gca.bucketGlobalState(0).totalGRCRewardsWeight;
        uint256 amountTotalGCC_OtherSubmittedPreviously = gca.bucket(0).reports[1].totalNewGCC;
        uint256 amountTotalGlwWeight_OtherSubmittedPreviously = gca.bucket(0).reports[1].totalGLWRewardsWeight;
        uint256 amountTotalGRCWeight_OtherSubmittedPreviously = gca.bucket(0).reports[1].totalGRCRewardsWeight;

        //Submit another one as other
        issueReport({
            gcaToSubmitAs: OTHER_GCA,
            bucket: 0,
            totalNewGCC: 202 * 1e15,
            totalGlwRewardsWeight: 206 * 1e15,
            totalGRCRewardsWeight: 205 * 1e15,
            randomMerkleRoot: keccak256("random but different again again")
        });

        //Check to make sure it's correctly overriden in the second index
        uint256 newReportTotalNewGCC = 202 * 1e15;
        uint256 newReportTotalGlwRewardsWeight = 206 * 1e15;
        uint256 newReportTotalGRCRewardsWeight = 205 * 1e15;
        checkBucketAndReport({
            bucketId: 0,
            reportIndex: 1,
            expectedNonce: 0,
            expectedReportsLength: 2,
            expectedLastUpdatedNonce: 0,
            expectedReportTotalNewGCC: newReportTotalNewGCC,
            expectedReportTotalGLWRewardsWeight: newReportTotalGlwRewardsWeight,
            expectedReportTotalGRCRewardsWeight: newReportTotalGRCRewardsWeight,
            expectedMerkleRoot: keccak256("random but different again again"),
            expectedProposingAgent: OTHER_GCA
        });

        checkBucketGlobalState({
            bucketId: 0,
            expectedTotalNewGCC: totalNewGCCBefore + newReportTotalNewGCC - amountTotalGCC_OtherSubmittedPreviously,
            expectedTotalGLWRewardsWeight: totalGLWRewardsWeightBefore + newReportTotalGlwRewardsWeight
                - amountTotalGlwWeight_OtherSubmittedPreviously,
            expectedTotalGRCRewardsWeight: totalGRCRewardsWeightBefore + newReportTotalGRCRewardsWeight
                - amountTotalGRCWeight_OtherSubmittedPreviously
        });
    }

    function test_issueReport_weightMoreThanUint256Div5_shouldRevert() public {
        addGCA(SIMON);
        vm.startPrank(SIMON);
        uint256 currentBucket = 0;
        uint256 totalNewGCC = 101 * 1e15;
        uint256 totalGlwRewardsWeight = _UINT64_MAX_DIV5 + 1;
        uint256 totalGRCRewardsWeight = 101 * 1e15;
        //Use a random root for now
        bytes32 root = keccak256("random but different");

        vm.expectRevert(IGCA.ReportWeightMustBeLTUint64MaxDiv5.selector);
        gca.issueWeeklyReport(currentBucket, totalNewGCC, totalGlwRewardsWeight, totalGRCRewardsWeight, root);

        totalGlwRewardsWeight = 1;
        totalGRCRewardsWeight = _UINT64_MAX_DIV5 + 1;
        vm.expectRevert(IGCA.ReportWeightMustBeLTUint64MaxDiv5.selector);
        gca.issueWeeklyReport(currentBucket, totalNewGCC, totalGlwRewardsWeight, totalGRCRewardsWeight, root);

        vm.stopPrank();
    }

    function test_issueReport_moreThan200BillionGCC_shouldRevert() public {
        addGCA(SIMON);
        vm.startPrank(SIMON);
        uint256 currentBucket = 0;
        uint256 totalNewGCC = _200_BILLION + 1;
        uint256 totalGlwRewardsWeight = 105 * 1e15;
        uint256 totalGRCRewardsWeight = 101 * 1e15;
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
        uint256 totalNewGCC = 101 * 1e15;
        uint256 totalGlwRewardsWeight = 105 * 1e15;
        uint256 totalGRCRewardsWeight = 101 * 1e15;
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
        uint256 totalNewGCC = 101 * 1e15;
        uint256 totalGlwRewardsWeight = 105 * 1e15;
        uint256 totalGRCRewardsWeight = 101 * 1e15;
        //Use a random root for now
        bytes32 randomMerkleRoot = keccak256("random but different");

        vm.expectRevert(IGCA.BucketSubmissionNotOpen.selector);
        gca.issueWeeklyReport(
            currentBucket, totalNewGCC, totalGlwRewardsWeight, totalGRCRewardsWeight, randomMerkleRoot
        );

        vm.stopPrank();
    }

    function test_issueReport_notSubmittingToZero_sanityCheck() public {
        uint256 bucketId = 1;
        uint256 bucketStartSubmission = gca.bucketStartSubmissionTimestampNotReinstated(bucketId);
        vm.warp(bucketStartSubmission);
        vm.startPrank(SIMON);
        addGCA(SIMON);
        uint256 totalNewGCC = 101 * 1e15;
        uint256 totalGlwRewardsWeight = 105 * 1e15;
        uint256 totalGRCRewardsWeight = 101 * 1e15;
        //Use a random root for now
        bytes32 randomMerkleRoot = keccak256("random but different");

        gca.issueWeeklyReport(bucketId, totalNewGCC, totalGlwRewardsWeight, totalGRCRewardsWeight, randomMerkleRoot);

        vm.stopPrank();

        IGCA.Bucket memory bucket = gca.bucket(bucketId);

        checkBucketAndReport({
            bucketId: bucketId,
            reportIndex: 0,
            expectedNonce: 0,
            expectedReportsLength: 1,
            expectedLastUpdatedNonce: 0,
            expectedReportTotalNewGCC: totalNewGCC,
            expectedReportTotalGLWRewardsWeight: totalGlwRewardsWeight,
            expectedReportTotalGRCRewardsWeight: totalGRCRewardsWeight,
            expectedMerkleRoot: randomMerkleRoot,
            expectedProposingAgent: SIMON
        });

        checkBucketGlobalState({
            bucketId: bucketId,
            expectedTotalNewGCC: totalNewGCC,
            expectedTotalGLWRewardsWeight: totalGlwRewardsWeight,
            expectedTotalGRCRewardsWeight: totalGRCRewardsWeight
        });
    }

    function test_issueReport_incrementNonce_shouldStore_ifBucketNotInit() public {
        addGCA(SIMON);
        vm.startPrank(SIMON);
        uint256 currentBucket = 1;
        uint256 totalNewGCC = 101 * 1e15;
        uint256 totalGlwRewardsWeight = 105 * 1e15;
        uint256 totalGRCRewardsWeight = 101 * 1e15;

        //Use a random root for now
        bytes32 randomMerkleRoot = keccak256("random but different");

        uint256 startSubmissionTimestamp = gca.bucketStartSubmissionTimestampNotReinstated(currentBucket);
        vm.warp(startSubmissionTimestamp);

        gca.incrementSlashNonce();

        gca.issueWeeklyReport(
            currentBucket, totalNewGCC, totalGlwRewardsWeight, totalGRCRewardsWeight, randomMerkleRoot
        );

        vm.stopPrank();

        checkBucketAndReport({
            bucketId: currentBucket,
            reportIndex: 0,
            expectedNonce: 1,
            expectedReportsLength: 1,
            expectedLastUpdatedNonce: 1,
            expectedReportTotalNewGCC: totalNewGCC,
            expectedReportTotalGLWRewardsWeight: totalGlwRewardsWeight,
            expectedReportTotalGRCRewardsWeight: totalGRCRewardsWeight,
            expectedMerkleRoot: randomMerkleRoot,
            expectedProposingAgent: SIMON
        });

        checkBucketGlobalState({
            bucketId: currentBucket,
            expectedTotalNewGCC: totalNewGCC,
            expectedTotalGLWRewardsWeight: totalGlwRewardsWeight,
            expectedTotalGRCRewardsWeight: totalGRCRewardsWeight
        });
    }

    function test_issueReport_createReport_thenIncrementNonce_shouldClearAllOldReports() public {
        //There should now be 2 reports in the bucket
        test_issueReport_newGCAShouldCreateNewReport();
        gca.incrementSlashNonce();

        vm.startPrank(SIMON);
        uint256 currentBucket = 0;
        uint256 totalNewGCC = 321 * 1e15;
        uint256 totalGlwRewardsWeight = 441 * 1e15;
        uint256 totalGRCRewardsWeight = 231 * 1e15;
        //Use a random root for now
        bytes32 randomMerkleRoot = keccak256("random but different");

        gca.issueWeeklyReport(
            currentBucket, totalNewGCC, totalGlwRewardsWeight, totalGRCRewardsWeight, randomMerkleRoot
        );

        vm.stopPrank();

        IGCA.Bucket memory bucket = gca.bucket(currentBucket);
        assertEq(bucket.reports.length, 1);
        assertEq(bucket.originalNonce, 0);
        assertEq(bucket.lastUpdatedNonce, 1);
        uint256 endBucketSubmissionTimestamp = gca.WCEIL(bucket.originalNonce);
        uint256 bucketFinalizationTimestamp = endBucketSubmissionTimestamp + ONE_WEEK;
        assertEq(bucket.finalizationTimestamp, bucketFinalizationTimestamp);

        IGCA.Report memory report = bucket.reports[0];
        assertEq(report.totalNewGCC, totalNewGCC);
        assertEq(report.totalGLWRewardsWeight, totalGlwRewardsWeight);
        assertEq(report.totalGRCRewardsWeight, totalGRCRewardsWeight);
        assertEq(report.merkleRoot, randomMerkleRoot);
        assertEq(report.proposingAgent, SIMON);

        checkBucketGlobalState({
            bucketId: currentBucket,
            expectedTotalNewGCC: totalNewGCC,
            expectedTotalGLWRewardsWeight: totalGlwRewardsWeight,
            expectedTotalGRCRewardsWeight: totalGRCRewardsWeight
        });
    }

    function test_issueReport_createReport_thenIncrementNonce_shouldClearAllOldReports_newSubmissionShouldPushToArray()
        public
    {
        test_issueReport_createReport_thenIncrementNonce_shouldClearAllOldReports();
        uint256 currentBucket = 0;
        uint256 globalStateGCCBefore = gca.bucketGlobalState(currentBucket).totalNewGCC;
        uint256 globalStateGLWBefore = gca.bucketGlobalState(currentBucket).totalGLWRewardsWeight;
        uint256 globalStateGRCBefore = gca.bucketGlobalState(currentBucket).totalGRCRewardsWeight;

        vm.startPrank(OTHER_GCA);
        uint256 totalNewGCC = 201 * 1e15;
        uint256 totalGlwRewardsWeight = 205 * 1e15;
        uint256 totalGRCRewardsWeight = 204 * 1e15;
        //Use a random root for now
        bytes32 randomMerkleRoot = keccak256("random but different again again");

        gca.issueWeeklyReport(
            currentBucket, totalNewGCC, totalGlwRewardsWeight, totalGRCRewardsWeight, randomMerkleRoot
        );

        vm.stopPrank();

        IGCA.Bucket memory bucket = gca.bucket(currentBucket);
        assertEq(bucket.reports.length, 2);
        assertEq(bucket.originalNonce, 0);
        assertEq(bucket.lastUpdatedNonce, 1);
        uint256 endBucketSubmissionTimestamp = gca.WCEIL(bucket.originalNonce);
        uint256 bucketFinalizationTimestamp = endBucketSubmissionTimestamp + ONE_WEEK;
        assertEq(bucket.finalizationTimestamp, bucketFinalizationTimestamp);

        IGCA.Report memory report = bucket.reports[1];
        assertEq(report.totalNewGCC, totalNewGCC);
        assertEq(report.totalGLWRewardsWeight, totalGlwRewardsWeight);
        assertEq(report.totalGRCRewardsWeight, totalGRCRewardsWeight);
        assertEq(report.merkleRoot, randomMerkleRoot);
        assertEq(report.proposingAgent, OTHER_GCA);

        checkBucketGlobalState({
            bucketId: currentBucket,
            expectedTotalNewGCC: globalStateGCCBefore + totalNewGCC,
            expectedTotalGLWRewardsWeight: globalStateGLWBefore + totalGlwRewardsWeight,
            expectedTotalGRCRewardsWeight: globalStateGRCBefore + totalGRCRewardsWeight
        });
    }

    function test_issueReport_submittingReportLate_shouldRevert_slashNonceDifferent() public {
        addGCA(SIMON);
        vm.startPrank(SIMON);
        uint256 currentBucket = 0;
        uint256 totalNewGCC = 101 * 1e15;
        uint256 totalGlwRewardsWeight = 105 * 1e15;
        uint256 totalGRCRewardsWeight = 101 * 1e15;

        //Use a random root for now
        bytes32 randomMerkleRoot = keccak256("random but different");

        gca.incrementSlashNonce();

        uint256 endSubmissionTimestamp = gca.WCEIL(currentBucket);

        //Can't submit after the endSubmissionTimestamp
        vm.warp(endSubmissionTimestamp + 1);
        vm.expectRevert(IGCA.BucketSubmissionEnded.selector);
        gca.issueWeeklyReport(
            currentBucket, totalNewGCC, totalGlwRewardsWeight, totalGRCRewardsWeight, randomMerkleRoot
        );
    }

    function test_issueReport_submittingReportLate_shouldRevert_slashNonceDifferentByTwo() public {
        test_issueReport_submittingAfterSubmissionShouldRevert();
        gca.incrementSlashNonce();
        test_issueReport_submittingReportLate_shouldRevert_slashNonceDifferent();
    }

    function test_incrementNonce() public {
        gca.incrementSlashNonce();
    }

    function test_issueReport_proposalsNotUpdated_shouldRevert() public {
        addGCA(SIMON);
        vm.startPrank(SIMON);
        uint256 currentBucket = 0;
        uint256 totalNewGCC = 101 * 1e15;
        uint256 totalGlwRewardsWeight = 105 * 1e15;
        uint256 totalGRCRewardsWeight = 101 * 1e15;

        //Use a random root for now
        bytes32 randomMerkleRoot = keccak256("random but different");

        bytes32 proposalHash = keccak256("proposal hash");
        gca.pushRequirementsHashMock(proposalHash);

        vm.expectRevert(IGCA.ProposalHashesNotUpdated.selector);
        gca.issueWeeklyReport(
            currentBucket, totalNewGCC, totalGlwRewardsWeight, totalGRCRewardsWeight, randomMerkleRoot
        );
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

    /**
     * note: the arithmetic checks for sending correct amounts is done
     *             - in the glow tests
     */
    function test_claimGlwFromInflation() public {
        vm.warp(block.timestamp + ONE_WEEK);
        gca.claimGlowFromInflation();
        assertTrue(glow.balanceOf(address(gca)) > 0);
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

    function test_pushHash_callerNotGovernance_shouldFail() public {
        bytes32 randomHash = keccak256("new hash");
        vm.expectRevert(IGCA.CallerNotGovernance.selector);
        gca.pushHash(randomHash, true);
    }

    function test_pushHash_callerNotGovernance_shouldWork() public {
        bytes32 randomHash = keccak256("new hash");
        uint256 slashNonceBefore = gca.slashNonce();
        vm.startPrank(governance);
        gca.pushHash(randomHash, true);

        assertEq(gca.slashNonce(), slashNonceBefore + 1);
        bytes32[] memory proposalHashes = gca.getProposalHashes();
        assertEq(proposalHashes.length, 1);
        assertEq(proposalHashes[0], randomHash);
    }

    function test_pushHash_callerNotGovernance_slashNonceShouldNotIncrement() public {
        bytes32 randomHash = keccak256("new hash");
        uint256 slashNonceBefore = gca.slashNonce();
        vm.startPrank(governance);
        gca.pushHash(randomHash, false);

        assertEq(gca.slashNonce(), slashNonceBefore);
        bytes32[] memory proposalHashes = gca.getProposalHashes();
        assertEq(proposalHashes.length, 1);
        assertEq(proposalHashes[0], randomHash);
    }

    function test_getProposalHashes_pagination() public {
        bytes32 randomHash = keccak256("new hash");
        bytes32 randomHash2 = keccak256("RH");
        uint256 slashNonceBefore = gca.slashNonce();
        vm.startPrank(governance);
        gca.pushHash(randomHash, false);
        gca.pushHash(randomHash2, false);

        assertEq(gca.slashNonce(), slashNonceBefore);
        bytes32[] memory proposalHashes = gca.getProposalHashes(0, 2);
        assertEq(proposalHashes.length, 2);
        assertEq(proposalHashes[0], randomHash);
        assertEq(proposalHashes[1], randomHash2);

        //if start > end, return []
        proposalHashes = gca.getProposalHashes(3, 1);
        assertEq(proposalHashes.length, 0);

        proposalHashes = gca.getProposalHashes(1, 2);
        assertEq(proposalHashes.length, 1);
        assertEq(proposalHashes[0], randomHash2);

        // if end > the actual len of proposalHashes
        // return up to the actual end
        proposalHashes = gca.getProposalHashes(0, 5);
        assertEq(proposalHashes.length, 2);
        assertEq(proposalHashes[0], randomHash);
        assertEq(proposalHashes[1], randomHash2);
    }

    //TODO: Fix the function to include payouts
    function test_executeAgainstHash() public {
        //Warp to random timestamp
        vm.warp(501);
        uint256 indexOfProposalHash = 0;
        //Start with two GCA's
        addGCA(SIMON);
        addGCA(OTHER_GCA);
        address[] memory gcasToSlash = new address[](1);
        gcasToSlash[0] = SIMON;
        address[] memory newGCAs = new address[](2);
        newGCAs[0] = OTHER_GCA;
        newGCAs[1] = OTHER_GCA_2;
        uint256 proposalCreationTimestamp = 501;

        vm.startPrank(governance);

        gca.pushHash(keccak256(abi.encodePacked(gcasToSlash, newGCAs, proposalCreationTimestamp)), true);
        vm.stopPrank();

        gca.executeAgainstHash(gcasToSlash, newGCAs, proposalCreationTimestamp);

        assertTrue(gca.isGCA(OTHER_GCA));
        assertTrue(gca.isGCA(OTHER_GCA_2));
        assertFalse(gca.isGCA(SIMON));
    }

    function test_executeAgainstHash_badInputsShouldRevert() public {
        //Warp to random timestamp
        vm.warp(501);
        uint256 indexOfProposalHash = 0;
        //Start with two GCA's
        addGCA(SIMON);
        addGCA(OTHER_GCA);
        address[] memory gcasToSlash = new address[](1);
        gcasToSlash[0] = SIMON;
        address[] memory newGCAs = new address[](2);
        newGCAs[0] = OTHER_GCA;
        newGCAs[1] = OTHER_GCA_2;
        uint256 proposalCreationTimestamp = 501;

        vm.startPrank(governance);

        gca.pushHash(keccak256(abi.encodePacked(gcasToSlash, newGCAs, proposalCreationTimestamp)), true);
        vm.stopPrank();

        newGCAs[0] = address(uint160(uint256(keccak256("NOT SIMON"))));
        vm.expectRevert(IGCA.ProposalHashDoesNotMatch.selector);
        gca.executeAgainstHash(gcasToSlash, newGCAs, proposalCreationTimestamp);
    }

    function test_executeAgainstHash_emptyProposalHashes_shouldRevert() public {
        vm.startPrank(SIMON);
        address[] memory gcasToSlash = new address[](1);
        gcasToSlash[0] = SIMON;
        address[] memory newGCAs = new address[](2);
        newGCAs[0] = OTHER_GCA;
        newGCAs[1] = OTHER_GCA_2;
        uint256 proposalCreationTimestamp = 501;

        vm.expectRevert(IGCA.ProposalHashesEmpty.selector);
        gca.executeAgainstHash(gcasToSlash, newGCAs, proposalCreationTimestamp);
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

    function logBucketGlobalState(IGCA.BucketGlobalState memory state) internal {
        console.log("totalNewGCC", state.totalNewGCC);
        console.log("totalGLWRewardsWeight", state.totalGLWRewardsWeight);
        console.log("totalGRCRewardsWeight", state.totalGRCRewardsWeight);
    }
}

/*

Stashed

 // function test_getBucketDataEfficient() public {
    //     issueReport(1, SIMON);

    //     IGCA.Bucket memory bucket = gca.bucket(0);
    //     assertEq(bucket.reports.length, 1);
    //     MockGCA.EfficientBucket memory efficientBucket = gca.getBucketDataEfficient(0);
    //     MockGCA.EfficientReport[] memory efficientReports = efficientBucket.reports;
    //     assertEq(efficientBucket.originalNonce, bucket.originalNonce);
    //     assertEq(efficientBucket.finalizationTimestamp, bucket.finalizationTimestamp);
    //     assertEq(efficientBucket.reinstated, bucket.reinstated);
    //     assertEq(efficientReports.length, 1);

    //     for (uint256 i; i < efficientReports.length; ++i) {
    //         IGCA.Report memory normalReport = bucket.reports[i];
    //         MockGCA.EfficientReport memory efficientReport = efficientReports[i];
    //         assertEq(efficientReport.totalNewGCC, normalReport.totalNewGCC);
    //         assertEq(efficientReport.totalGLWRewardsWeight, normalReport.totalGLWRewardsWeight);
    //         assertEq(efficientReport.totalGRCRewardsWeight, normalReport.totalGRCRewardsWeight);
    //         assertEq(efficientReport.merkleRoot, normalReport.merkleRoot);
    //     }

    //     // }
    // }



    // function test_getBucketData_gasCheckEfficient() public {
    //     issueReport(1, SIMON);
    //     MockGCA.EfficientBucket memory efficientBucket = gca.getBucketDataEfficient(0);
    // }

    // function test_getBucketDataEfficient_multipleArrays() public {
    //     issueReport(1, SIMON);
    //     issueReport(2, OTHER_GCA);
    //     issueReport(3, OTHER_GCA_2);

    //     IGCA.Bucket memory bucket = gca.bucket(0);
    //     assertEq(bucket.reports.length, 3);
    //     MockGCA.EfficientBucket memory efficientBucket = gca.getBucketDataEfficient(0);
    //     MockGCA.EfficientReport[] memory efficientReports = efficientBucket.reports;
    //     assertEq(efficientBucket.originalNonce, bucket.originalNonce);
    //     assertEq(efficientBucket.finalizationTimestamp, bucket.finalizationTimestamp);
    //     assertEq(efficientBucket.reinstated, bucket.reinstated);
    //     assertEq(efficientReports.length, 3);

    //     for (uint256 i; i < bucket.reports.length; ++i) {
    //         IGCA.Report memory normalReport = bucket.reports[i];
    //         MockGCA.EfficientReport memory efficientReport = efficientReports[i];
    //         assertEq(efficientReport.totalNewGCC, normalReport.totalNewGCC);
    //         assertEq(efficientReport.totalGLWRewardsWeight, normalReport.totalGLWRewardsWeight);
    //         assertEq(efficientReport.totalGRCRewardsWeight, normalReport.totalGRCRewardsWeight);
    //         assertEq(efficientReport.merkleRoot, normalReport.merkleRoot);
    //     }
    // }
*/
