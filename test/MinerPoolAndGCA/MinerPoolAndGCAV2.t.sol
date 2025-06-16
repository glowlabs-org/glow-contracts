// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import "@/testing/GuardedLaunch/TestGCC.GuardedLaunch.sol";
import "forge-std/console.sol";
import {IGCA} from "@/interfaces/IGCA.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Governance} from "@/Governance.sol";
import {CarbonCreditDescendingPriceAuction} from "@/CarbonCreditDescendingPriceAuction.sol";
import "forge-std/StdUtils.sol";
import {TestGLOWGuardedLaunch} from "@/testing/GuardedLaunch/TestGLOW.GuardedLaunch.sol";
import {Handler} from "./Handlers/Handler.GCA.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MerkleProofLib} from "@solady/utils/MerkleProofLib.sol";
import {MockMinerPoolAndGCAV2 as MockMinerPoolAndGCA} from "@/MinerPoolAndGCA/mock/MockMinerPoolAndGCAV2.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";
import {IMinerPoolV2 as IMinerPool} from "@/interfaces/IMinerPoolV2.sol";
import {BucketSubmissionV2 as BucketSubmission} from "@/MinerPoolAndGCA/BucketSubmissionV2.sol";
import {VetoCouncil} from "@/VetoCouncil/VetoCouncil.sol";
import {BucketDelayHandler} from "./Handlers/BucketDelayHandler.sol";
import {Holding, ClaimHoldingArgs, ISafetyDelay, SafetyDelay} from "@/SafetyDelay.sol";
import {UnifapV2Factory} from "@unifapv2/UnifapV2Factory.sol";
import {UnifapV2Router} from "@unifapv2/UnifapV2Router.sol";
import {WETH9} from "@/UniswapV2/contracts/test/WETH9.sol";
import {TestUSDG} from "@/testing/TestUSDG.sol";
import {USDG} from "@/USDG.sol";

bytes4 constant BUCKET_OUT_OF_BOUNDS_SIG = 0xfdbe8876;

struct ClaimLeaf {
    address payoutWallet;
    uint256 glwWeight;
    uint256 usdcWeight;
}

contract MinerPoolAndGCAV2Test is Test {
    //--------  CONTRACTS ---------//
    UnifapV2Factory public uniswapFactory;
    WETH9 public weth;
    UnifapV2Router public uniswapRouter;
    MockMinerPoolAndGCA minerPoolAndGCA;
    TestGLOWGuardedLaunch glow;
    MockUSDC usdc;
    MockUSDC grc2;

    BucketDelayHandler bucketDelayHandler;
    SafetyDelay holdingContract;
    TestGCCGuardedLaunch gcc;

    uint256 internal VESTING_PERIODS;

    //TODO: add usdg to testing
    TestUSDG usdg;

    //--------  ADDRESSES ---------//
    address governance = address(0x1);
    address earlyLiquidity = address(0x2);
    address vestingContract = address(0x3);
    address vetoCouncilAddress;
    VetoCouncil vetoCouncil;
    address grantsTreasuryAddress = address(0x5);
    address SIMON;
    uint256 SIMON_PRIVATE_KEY;

    address OTHER_GCA = address(0x7);
    address OTHER_GCA_2 = address(0x8);
    address OTHER_GCA_3 = address(0x9);
    address OTHER_GCA_4 = address(0x10);
    address carbonCreditAuction = address(0x11);
    address defaultAddressInWithdraw;
    uint256 defaultAddressPrivateKey;
    address bidder1 = address(0x12);
    address bidder2 = address(0x13);

    // uint256 mainnetFork;
    address usdgOwner = address(0xaaa112);
    address usdcReceiver = address(0xaaa113);

    address deployer = tx.origin;
    //--------  CONSTANTS ---------//
    uint256 constant ONE_WEEK = 7 * uint256(1 days);

    function setUp() public {
        //Make sure we don't start at 0
        vm.startPrank(deployer);
        uniswapFactory = new UnifapV2Factory();
        weth = new WETH9();
        uniswapRouter = new UnifapV2Router(address(uniswapFactory));
        usdc = new MockUSDC();

        uint256 deployerNonce = vm.getNonce(deployer);
        address precomputedVetoCouncilContract = computeCreateAddress(deployer, deployerNonce + 3);
        address precomputedGCA = computeCreateAddress(deployer, deployerNonce + 5);
        address precomputedGlow = computeCreateAddress(deployer, deployerNonce + 1);
        address precomputedUSDG = computeCreateAddress(deployer, deployerNonce + 6);

        gcc = new TestGCCGuardedLaunch({
            _gcaAndMinerPoolContract: address(precomputedGCA),
            _governance: address(governance),
            _glowToken: address(precomputedGlow),
            _usdg: address(precomputedUSDG),
            _vetoCouncilAddress: address(precomputedVetoCouncilContract),
            _uniswapRouter: address(uniswapRouter),
            _uniswapFactory: address(uniswapFactory)
        }); //deployerNonce
        gcc.allowlistPostConstructionContracts();

        (SIMON, SIMON_PRIVATE_KEY) = _createAccount(9999, type(uint256).max);
        vm.warp(10);
        (defaultAddressInWithdraw, defaultAddressPrivateKey) = _createAccount(2313141231, type(uint256).max);

        glow = new TestGLOWGuardedLaunch({
            _earlyLiquidityAddress: earlyLiquidity,
            _vestingContract: vestingContract,
            _gcaAndMinerPoolAddress: precomputedGCA,
            _vetoCouncilAddress: precomputedVetoCouncilContract,
            _grantsTreasuryAddress: grantsTreasuryAddress,
            _owner: SIMON,
            _usdg: address(precomputedUSDG),
            _uniswapV2Factory: address(uniswapFactory),
            _gccContract: address(gcc)
        }); //deployerNonce + 1
        bucketDelayHandler = new BucketDelayHandler(); //deployer nonce + 2
        address[] memory temp = new address[](0);
        address[] memory startingAgents = new address[](2);
        startingAgents[0] = address(SIMON);
        startingAgents[1] = address(bucketDelayHandler);
        vetoCouncil = new VetoCouncil(governance, address(glow), startingAgents); //deployer nonce + 3
        vetoCouncilAddress = address(vetoCouncil);
        holdingContract = new SafetyDelay(vetoCouncilAddress, precomputedGCA); //deployer nonce + 4
        minerPoolAndGCA = new MockMinerPoolAndGCA( //deployer nonce + 5
            temp,
            address(glow),
            governance,
            keccak256("requirementsHash"),
            earlyLiquidity,
            address(precomputedUSDG),
            vetoCouncilAddress,
            address(holdingContract),
            address(gcc)
        );

        usdg = new TestUSDG({
            _usdc: address(usdc),
            _usdcReceiver: usdcReceiver,
            _owner: usdgOwner,
            _univ2Factory: address(uniswapFactory),
            _glow: address(glow),
            _gcc: address(gcc),
            _holdingContract: address(holdingContract),
            _vetoCouncilContract: vetoCouncilAddress,
            _impactCatalyst: address(gcc.IMPACT_CATALYST())
        }); //deployerNonce + 6

        addGCA(address(bucketDelayHandler));
        vm.stopPrank();

        vm.startPrank(SIMON);

        //TODO: precompute
        // glow.setContractAddresses(address(minerPoolAndGCA), vetoCouncilAddress, grantsTreasuryAddress);
        vm.stopPrank();
        grc2 = new MockUSDC();
        bucketDelayHandler.setMinerPool(address(minerPoolAndGCA));
        carbonCreditAuction = address(gcc.CARBON_CREDIT_AUCTION());
        // handler = new Handler(address(gca));
        // addGCA(address(handler));
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = BucketDelayHandler.delayBucket.selector;
        selectors[1] = BucketDelayHandler.preventBucketDelay.selector;

        FuzzSelector memory fs = FuzzSelector({selectors: selectors, addr: address(bucketDelayHandler)});

        vm.startPrank(usdgOwner);
        // usdg.setAllowlistedContracts({
        //     _glow: address(glow),
        //     _gcc: address(gcc),
        //     _holdingContract: address(holdingContract),
        //     _vetoCouncilContract: address(vetoCouncil),
        //     _impactCatalyst: address(gcc.IMPACT_CATALYST())
        // });

        usdc.mint(usdgOwner, 100000000 * 1e6);
        usdc.approve(address(usdg), 100000000 * 1e6);
        usdg.swap(usdgOwner, 100000000 * 1e6);
        vm.stopPrank();
        // targetSender(SIMON);
        // targetSender(OTHER_GCA);
        // targetSender(OTHER_GCA_2);
        // targetSender(OTHER_GCA_3);
        // targetSender(OTHER_GCA_4);
        targetContract(address(bucketDelayHandler));
        VESTING_PERIODS = minerPoolAndGCA.OFFSET_RIGHT() - minerPoolAndGCA.OFFSET_LEFT();
    }

    //-------- ISSUING REPORTS ---------//
    function addGCA(address newGCA) public {
        address[] memory allGCAs = minerPoolAndGCA.allGcas();
        address[] memory temp = new address[](allGCAs.length + 1);
        for (uint256 i; i < allGCAs.length; ++i) {
            temp[i] = allGCAs[i];
            if (allGCAs[i] == newGCA) {
                return;
            }
        }
        temp[allGCAs.length] = newGCA;
        minerPoolAndGCA.setGCAs(temp);
        allGCAs = minerPoolAndGCA.allGcas();
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

        minerPoolAndGCA.submitWeeklyReport(
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
        IGCA.Bucket memory bucket = minerPoolAndGCA.bucket(bucketId);
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
        IGCA.BucketGlobalState memory state = minerPoolAndGCA.bucketGlobalState(bucketId);
        assertEq(state.totalNewGCC, expectedTotalNewGCC);
        assertEq(state.totalGLWRewardsWeight, expectedTotalGLWRewardsWeight);
        assertEq(state.totalGRCRewardsWeight, expectedTotalGRCRewardsWeight);
    }

    function stringifyBytes32Array(bytes32[] memory arr) internal returns (string memory str) {
        str = "[";
        for (uint256 i; i < arr.length; ++i) {
            str = string(abi.encodePacked(str, '"', Strings.toHexString(uint256(arr[i]), 32), '"'));
            if (i != arr.length - 1) {
                str = string(abi.encodePacked(str, ","));
            }
        }
        str = string(abi.encodePacked(str, "]"));
    }

    function test_v2_guarded_checkWeightsForOverflow() public {
        uint256 bucketId = 0;
        uint256 totalGlwWeight = type(uint64).max;
        uint256 totalusdcWeight = type(uint64).max;
        uint256 glwWeight = type(uint64).max;
        uint256 usdcWeight = type(uint64).max;

        minerPoolAndGCA.checkWeightsForOverflow(bucketId, totalGlwWeight, totalusdcWeight, glwWeight, usdcWeight);

        //Any overflow to totalGlwWeight should revert
        vm.expectRevert(stdError.arithmeticError);
        minerPoolAndGCA.checkWeightsForOverflow(bucketId, 1, totalusdcWeight, glwWeight, usdcWeight);
        vm.expectRevert(stdError.arithmeticError);
        minerPoolAndGCA.checkWeightsForOverflow(bucketId, totalGlwWeight, 1, glwWeight, usdcWeight);

        // //Any overflow to totalGlwWeight should revert
        vm.expectRevert(stdError.arithmeticError);
        minerPoolAndGCA.checkWeightsForOverflow(bucketId, type(uint256).max, totalusdcWeight, glwWeight, usdcWeight);
        vm.expectRevert(stdError.arithmeticError);
        minerPoolAndGCA.checkWeightsForOverflow(bucketId, totalGlwWeight, type(uint256).max, glwWeight, usdcWeight);
    }

    function test_v2_guarded_checkWeightsForOverflow_gtThanSubmittedWeights() public {
        uint256 bucketId = 0;
        uint256 totalGlwWeight = 5000;
        uint256 totalusdcWeight = 5000;
        uint256 glwWeight = 5001;
        uint256 usdcWeight = 5000;

        //glw weight should overflow since it's > totalGlwWeight
        vm.expectRevert(IMinerPool.GlowWeightOverflow.selector);
        minerPoolAndGCA.checkWeightsForOverflow(bucketId, totalGlwWeight, totalusdcWeight, glwWeight, usdcWeight);

        ++usdcWeight; //grc weight will now be greater than tha allowed
        --glwWeight; // and glw weight will be ok
        //so the grc weight should revert
        vm.expectRevert(IMinerPool.USDCWeightOverflow.selector);
        minerPoolAndGCA.checkWeightsForOverflow(bucketId, totalGlwWeight, totalusdcWeight, glwWeight, usdcWeight);
    }

    function test_v2_guarded_CreateClaimLeafProof() public {
        ClaimLeaf[] memory leaves = new ClaimLeaf[](5);
        for (uint256 i; i < leaves.length; ++i) {
            leaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                usdcWeight: 200 + i
            });
        }

        ClaimLeaf memory targetLeaf = ClaimLeaf({
            payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + 3)),
            glwWeight: 103,
            usdcWeight: 203
        });
        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdc);
        bytes32 root = createClaimLeafRoot(leaves, payoutTokens);

        {
            (bytes32[] memory proof, bool[] memory flags) = createClaimLeafProof(leaves, payoutTokens, targetLeaf);
            bytes32[] memory targetLeaves = new bytes32[](2);
            targetLeaves[0] = _hashClaimLeaf(targetLeaf);
            targetLeaves[1] = _hashPayoutTokens(payoutTokens);
            sortTargetLeavesArray(targetLeaves);
            //Log the leaves
            for (uint256 i; i < targetLeaves.length; ++i) {
                string memory leaf = Strings.toHexString(uint256(targetLeaves[i]), 32);
                console.logString(leaf);
            }
            bool validProof = MerkleProofLib.verifyMultiProof(proof, root, targetLeaves, flags);
            assertTrue(validProof, "Proof is not valid");
        }
    }

    // // // ------------WITHDRAWALS----------------//

    function test_v2_guarded_withdrawFromBucket() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        uint256 totalGlwWeight;
        uint256 totalusdcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalusdcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                usdcWeight: 200 + i
            });
        }

        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdc);
        bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);

        uint256 bucketId = 0;
        uint256 totalNewGCC = 101 * 1e15;

        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: bucketId,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalusdcWeight,
            randomMerkleRoot: root
        });

        vm.warp(block.timestamp + (ONE_WEEK * 2));

        vm.startPrank(defaultAddressInWithdraw);
        uint256 glwWeightForAddress = 100;
        uint256 usdcWeightForAddress = 200;
        // minerPoolAndGCA.claimRewardFromBucket(bucketId, glwWeight, usdcWeight, proof, packedIndex, user, grcTokens, claimFromInflation);

        (bytes32[] memory proof, bool[] memory proofFlags) =
            createClaimLeafProof(claimLeaves, payoutTokens, claimLeaves[0]);

        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: bucketId,
            glwWeight: glwWeightForAddress,
            usdcWeight: usdcWeightForAddress,
            proof: proof,
            flags: proofFlags,
            tokens: payoutTokens,
            index: 0,
            claimFromInflation: true
        });

        //Should have gotten all the glow rewards
        assertEq(glow.balanceOf((defaultAddressInWithdraw)), (175_000 ether * glwWeightForAddress) / totalGlwWeight);

        vm.stopPrank();
    }

    //-----------------------------------------------------------------//
    //------------------------- Delay Tests ---------------------------//
    //-----------------------------------------------------------------//

    /**
     * In this test, we explore all of the scenarios for a bucket submission.
     *     The following scenarios are:
     *
     *     1. Happy path.
     *     The bucket should not be able to be submitted if it's been more than one week after the bucket submission has open
     *  Bucket Submission should be open from n-n+1 and finalize on n+2 ✅
     *
     *
     *     2. Requested Resubmission Path
     *         The bucket should first be able to be submitted between n-n+1 ✅
     *             Once requested for resubmission, it should be open for submission until n+3, ✅
     *             and should finalize on n+4
     *     Other considerations:
     *         Can only be requested for resubmission once per slash nonce; ✅
     *         Cannot be requested for resubmission if delayed at current slash nonce ✅
     *         Cannot request a bucket that has already been finalized ✅
     *         Cannot request a bucket that is not yet open for submission/has no submissions ✅
     *
     *     3. Delayed Submission Path
     *         The bucket should first be able to be submitted between n-n+1 ✅
     *         If the bucket is delayed, it should not be open for resubmission ✅
     *         If no slash happens, it should finalize at n+15 ✅
     *            If a slash happens and we resubmit, it should finalize at the same timestamp,
     *               unless bucketSubmissionEndTimestamp + bucketDuration() > bucketFinalizationTimestamp
     *               where it then finalizes at bucketSubmissionEndTimestamp + bucketDuration() ✅
     *               submission should only be open until _WCEIL(slashNonce-1) ✅
     *             TODO: Decide if we should change that.
     *             TODO: also test claiming after all this stuff
     *        Other considerations:
     *             Cannot be delayed if the bucket has already been finalized ✅
     *             Delaying a bucket that has been requested for resubmission should still add 13 weeks to the finalization timestamp  ✅
     *
     *
     *
     *     4. Requested for resubmission multiple times through a slash nonce
     *     5. Delayed even with slash nonce multiple times
     *
     *
     *  -- Invariants To Think About --
     *      // TODO: Invariant to check
     *     // Finalization timestamp for each bucket can never be less than the `bucketFinalizationTimestampNotReinstated(bucketId)`
     *     // Let's now move on to bucket 2.
     *     // Let's also make sure that we can't delay or request resubmission since the submission period isnt yet finished
     *     // CannotDelayOrResubmitBucketWhereSubmissionsAreStillOpenOrNotYetOpen
     *     // Another invariant is that the finalization timestamp % 1 week should always be zero.
     */
    function test_v2_bucketEndSubmissionTimestampFull() public {
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 101 * 1e15,
            totalGlwRewardsWeight: 100,
            totalGRCRewardsWeight: 200,
            randomMerkleRoot: bytes32(0)
        });

        //If we warp forward 1 week, we shouldnt be able to submit anymore since the submission timestmap has ended
        vm.warp(block.timestamp + 1 weeks);

        vm.startPrank(SIMON);
        vm.expectRevert(IGCA.BucketSubmissionEnded.selector);
        minerPoolAndGCA.submitWeeklyReport(0, 101 * 1e15, 100, 200, bytes32(0));

        //If we go back one second, we actually should be able to submit it.
        // Sanity check this
        vm.warp(block.timestamp - 1);
        minerPoolAndGCA.submitWeeklyReport(0, 101 * 1e15, 100, 200, bytes32(0));

        //Warp back so the schedule is aligned
        vm.warp(block.timestamp + 1);

        //Let's check if it's finalized , if we fast forward 1 week -1, it should not be finalized,
        // and if we fast forward + 1 from there, it should be finalized
        vm.warp(block.timestamp + 1 weeks - 1);
        assertFalse(minerPoolAndGCA.isBucketFinalized(0), "Bucket should not be finalized");
        vm.warp(block.timestamp + 1);
        assertTrue(minerPoolAndGCA.isBucketFinalized(0), "Bucket should be finalized");

        //We are now in week 2,
        assertEq(minerPoolAndGCA.currentBucket(), 2, "Current week should be 2");

        // Let's make sure that we can't delay or request resubmission
        vm.expectRevert(IGCA.BucketAlreadyFinalized.selector);
        minerPoolAndGCA.delayBucketFinalization({bucketId: 0});
        vm.expectRevert(IGCA.BucketAlreadyFinalized.selector);
        minerPoolAndGCA.requestBucketResubmission({bucketId: 0});

        {
            //We're also testing that we can delay buckets that are empty and in the review period,
            // so delaying AND requesting resubmission on bucket 1 should work.
            minerPoolAndGCA.requestBucketResubmission({bucketId: 1});
            //If we try to request resubmission again, it should fail
            vm.expectRevert(IMinerPool.ResubmissionAlreadyRequestedForSlashNonce.selector);
            minerPoolAndGCA.requestBucketResubmission({bucketId: 1});

            // Now the bucket end submission should be 2 weeks from now
            vm.expectRevert(IGCA.CannotDelayOrResubmitBucketWhereSubmissionsAreStillOpenOrNotYetOpen.selector);
            minerPoolAndGCA.delayBucketFinalization({bucketId: 1});

            //If we warp forward 1 week, it should still not be able to be delayed
            vm.warp(block.timestamp + 1 weeks);
            vm.expectRevert(IGCA.CannotDelayOrResubmitBucketWhereSubmissionsAreStillOpenOrNotYetOpen.selector);
            minerPoolAndGCA.delayBucketFinalization({bucketId: 1});

            vm.warp(block.timestamp + 1 weeks);
            //Now it should be able to be delayed
            //Let's also make sure that the finalization timestamp is 1 week from now
            uint256 finalizationTimestampBucket1BeforeDelay = minerPoolAndGCA.bucket(1).finalizationTimestamp;
            assertEq(
                finalizationTimestampBucket1BeforeDelay,
                block.timestamp + 1 weeks,
                "Finalization timestamp should be 1 week from now"
            );
            minerPoolAndGCA.delayBucketFinalization({bucketId: 1});
            uint256 finalizationTimestampAfterDelay = minerPoolAndGCA.bucket(1).finalizationTimestamp;
            assertEq(
                finalizationTimestampBucket1BeforeDelay + minerPoolAndGCA.bucketDelayDuration(),
                finalizationTimestampAfterDelay,
                "Delaying should add a bucketDelayDuration() to the finalization timestamp"
            );

            //Make sure that we can't delay or request resubmission aymore here.
            vm.expectRevert(IMinerPool.BucketAlreadyDelayed.selector);
            minerPoolAndGCA.delayBucketFinalization({bucketId: 1});

            //Also try the same with resubmission
            vm.expectRevert(IMinerPool.BucketAlreadyDelayed.selector);
            minerPoolAndGCA.requestBucketResubmission({bucketId: 1});
            //Warp back 2 weeks to make sure that we are good for bucket 2
            vm.warp(block.timestamp - 2 weeks);
        }

        //Check again to make sure ew are in bucket 2
        assertEq(minerPoolAndGCA.currentBucket(), 2, "Current week should be 2");

        vm.expectRevert(IGCA.CannotDelayOrResubmitBucketWhereSubmissionsAreStillOpenOrNotYetOpen.selector);
        minerPoolAndGCA.requestBucketResubmission({bucketId: 2});
        vm.expectRevert(IGCA.CannotDelayOrResubmitBucketWhereSubmissionsAreStillOpenOrNotYetOpen.selector);
        minerPoolAndGCA.delayBucketFinalization({bucketId: 2});
        vm.stopPrank();

        //First Step is to submit a report

        //We don't care about the data in it,
    }

    function test_v2_requestResubmissionFlow_shouldAllowResubmissionAndShouldFinalizeAtCorrectTime() public {
        //First Step is to submit a report
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 101 * 1e15,
            totalGlwRewardsWeight: 100,
            totalGRCRewardsWeight: 200,
            randomMerkleRoot: bytes32(0)
        });
        uint256 originalFinalizationTimestamp = minerPoolAndGCA.bucket(0).finalizationTimestamp;
        uint256 bucketSubmissionEndTimestamp = minerPoolAndGCA.calculateBucketSubmissionEndTimestamp(0);

        //Log the current timestamp, and then also log the bucket submission end timestamp
        // console2.log("Current Timestamp: ", block.timestamp);
        // console2.log("Bucket Submission End Timestamp: ", bucketSubmissionEndTimestamp);

        //If we warp forward, we should be able to resubmit
        //Log the timestamp now
        vm.startPrank(SIMON);
        vm.warp(block.timestamp + 1 weeks);
        //Request a resubmission
        minerPoolAndGCA.requestBucketResubmission({bucketId: 0});

        uint256 resubmissionFinalizationTimestamp = minerPoolAndGCA.bucket(0).finalizationTimestamp;

        assertEq(
            resubmissionFinalizationTimestamp,
            originalFinalizationTimestamp + 2 weeks,
            "Finalization timestamp should be 2  weeks from original after resubmission"
        );

        //Let's make sure that the finalization timestamp is equal to the finalization timestamp before + 2 weeks

        vm.stopPrank();
        //Should be able to resubmitagain
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 200 * 1e15,
            totalGlwRewardsWeight: 200,
            totalGRCRewardsWeight: 400,
            randomMerkleRoot: bytes32(uint256(0x1))
        });

        //make sure the finalization timestamp has not been touched even after resubmission
        assertEq(
            minerPoolAndGCA.bucket(0).finalizationTimestamp,
            resubmissionFinalizationTimestamp,
            "Finalization timestamp should not have changed after resubmission"
        );
        //We are currently at n+1

        //Make sure that we can't submit at n+3 start timestamp
        vm.warp(block.timestamp + 2 weeks);
        vm.startPrank(SIMON);
        vm.expectRevert(IGCA.BucketSubmissionEnded.selector);
        minerPoolAndGCA.submitWeeklyReport(0, 101 * 1e15, 100, 200, bytes32(0));
        vm.stopPrank();

        //Warp to 3 weeks - 1 second and make sure that it is not finalized
        //The submission was extended by 2 weeks, so there the submission period is from n+2-n+3,  review period last from n+3 -n+4
        vm.warp(block.timestamp + 1 weeks - 1);
        assertFalse(minerPoolAndGCA.isBucketFinalized(0), "Bucket should not be finalized");

        //Warp 2 seconds forward, and make sure that it is finalized
        vm.warp(block.timestamp + 2);
        assertTrue(minerPoolAndGCA.isBucketFinalized(0), "Bucket should be finalized");
    }

    function test_v2_requestResubmissionMoreThanOncePerSlashNonce_shouldRevert() public {
        vm.startPrank(SIMON);
        vm.warp(block.timestamp + 1 weeks);
        minerPoolAndGCA.requestBucketResubmission({bucketId: 0});
        vm.expectRevert(IMinerPool.ResubmissionAlreadyRequestedForSlashNonce.selector);
        minerPoolAndGCA.requestBucketResubmission({bucketId: 0});

        vm.stopPrank();
    }

    function test_v2_resubmittingFinalizedBucket_shouldRevert() public {
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 101 * 1e15,
            totalGlwRewardsWeight: 100,
            totalGRCRewardsWeight: 200,
            randomMerkleRoot: bytes32(0)
        });

        vm.warp(block.timestamp + 2 weeks);

        vm.startPrank(SIMON);
        vm.expectRevert(IGCA.BucketAlreadyFinalized.selector);
        minerPoolAndGCA.requestBucketResubmission({bucketId: 0});
        vm.stopPrank();
    }

    function test_v2_cannotRequestResubmissionIfWithdrawPeriodStillOpen() public {
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 101 * 1e15,
            totalGlwRewardsWeight: 100,
            totalGRCRewardsWeight: 200,
            randomMerkleRoot: bytes32(0)
        });

        vm.warp(block.timestamp + 1 weeks - 1);

        vm.startPrank(SIMON);
        vm.expectRevert(IGCA.CannotDelayOrResubmitBucketWhereSubmissionsAreStillOpenOrNotYetOpen.selector);
        minerPoolAndGCA.requestBucketResubmission({bucketId: 0});
        vm.stopPrank();
    }

    function test_v2_cannotReuqestResubmissionIfSubmissionPeriod_notOpen() public {
        vm.startPrank(SIMON);
        //Try to request resubmission on bucket 1
        vm.expectRevert(IGCA.CannotDelayOrResubmitBucketWhereSubmissionsAreStillOpenOrNotYetOpen.selector);
        minerPoolAndGCA.requestBucketResubmission({bucketId: 1});
        vm.stopPrank();
    }

    function test_v2_delayedBucketCannotBeRequestedForResubmission() public {
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 101 * 1e15,
            totalGlwRewardsWeight: 100,
            totalGRCRewardsWeight: 200,
            randomMerkleRoot: bytes32(0)
        });

        vm.warp(block.timestamp + 1 weeks);
        vm.startPrank(SIMON);
        minerPoolAndGCA.delayBucketFinalization({bucketId: 0});
        vm.expectRevert(IMinerPool.BucketAlreadyDelayed.selector);
        minerPoolAndGCA.requestBucketResubmission({bucketId: 0});
        vm.stopPrank();
    }

    function test_v2_cannotDelayBucketSubmission_periodNotFinished() public {
        vm.startPrank(SIMON);
        vm.expectRevert(IGCA.CannotDelayOrResubmitBucketWhereSubmissionsAreStillOpenOrNotYetOpen.selector);
        minerPoolAndGCA.delayBucketFinalization({bucketId: 0});
        vm.stopPrank();
    }

    function test_v2_cannotDelayBucketIfSubmissionPeriodNotYetOpen() public {
        vm.startPrank(SIMON);
        vm.expectRevert(IGCA.CannotDelayOrResubmitBucketWhereSubmissionsAreStillOpenOrNotYetOpen.selector);
        minerPoolAndGCA.delayBucketFinalization({bucketId: 1});
        vm.stopPrank();
    }

    function test_v2_bucketDelayShouldFinalize_atN_plus_15() public {
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 101 * 1e15,
            totalGlwRewardsWeight: 100,
            totalGRCRewardsWeight: 200,
            randomMerkleRoot: bytes32(0)
        });

        vm.warp(block.timestamp + 1 weeks);
        vm.startPrank(SIMON);
        minerPoolAndGCA.delayBucketFinalization({bucketId: 0});
        vm.stopPrank();

        vm.warp(block.timestamp + 14 weeks - 1);
        assertFalse(minerPoolAndGCA.isBucketFinalized(0), "Bucket should not be finalized");

        //Warp forward 1 second to make sure it's finalized
        vm.warp(block.timestamp + 1);
        assertTrue(minerPoolAndGCA.isBucketFinalized(0), "Bucket should be finalized");
    }

    function test_v2_sanityCheck_slashHappenedBeforeFinalization_shouldReturnFalseForIsBucketFinalized() public {
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 101 * 1e15,
            totalGlwRewardsWeight: 100,
            totalGRCRewardsWeight: 200,
            randomMerkleRoot: bytes32(0)
        });

        vm.warp(block.timestamp + 1 weeks);
        vm.startPrank(SIMON);
        minerPoolAndGCA.delayBucketFinalization({bucketId: 0});
        vm.stopPrank();

        vm.warp(block.timestamp + 14 weeks - 1);
        assertFalse(minerPoolAndGCA.isBucketFinalized(0), "Bucket should not be finalized");

        //If we increment the slash nonce, it should not be finalized sanity check
        minerPoolAndGCA.incrementSlashNonce();
        vm.warp(block.timestamp + 1);
        assertFalse(minerPoolAndGCA.isBucketFinalized(0), "Bucket should not be finalized");
    }

    function test_v2_slashThenResubmitted_shouldCorrectlyCalculateTheSubmissionEndTimeAndFinalizationTimestamp_whenWCEILPlusBucketDuration_greaterThanFinalizationTimestamp(
    ) public {
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 101 * 1e15,
            totalGlwRewardsWeight: 100,
            totalGRCRewardsWeight: 200,
            randomMerkleRoot: bytes32(0)
        });

        uint256 n = block.timestamp;
        vm.warp(block.timestamp + 1 weeks);
        vm.startPrank(SIMON);
        minerPoolAndGCA.delayBucketFinalization({bucketId: 0});
        vm.stopPrank();

        //We are at n+1
        //The bucket finalizes at n+15
        //if we want WCEIL to be > , we can be in n+14 and run the slash
        // This SHOULD make the new submission end timestamp n+16
        vm.warp(n + 14 weeks);
        minerPoolAndGCA.incrementSlashNonce();

        uint256 submissionEndTimestamp = minerPoolAndGCA.calculateBucketSubmissionEndTimestamp(0);
        assertEq(submissionEndTimestamp, n + 16 weeks, "Submission end timestamp should be n+16 weeks");

        // issue a new report
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 101 * 1e15,
            totalGlwRewardsWeight: 100,
            totalGRCRewardsWeight: 200,
            randomMerkleRoot: bytes32(0)
        });

        uint256 finalizationTimestampAfterResubmission = minerPoolAndGCA.bucket(0).finalizationTimestamp;
        // The new finalization should be n+16 + 1 to give enough time for the veto council to review

        // The original finalization was n+15, but since we WCEILed in week 14,
        // That means that the GCAs should have at least 2 weeks to post the data
        // and that the veto council has AT LEAST one week to review it.
        assertEq(
            finalizationTimestampAfterResubmission,
            n + 16 weeks + 1 weeks,
            "Finalization timestamp should be n+16 weeks + 1 weeks"
        );
    }

    function test_v2_slashThenResubmitted_shouldCorrectlyCalculateTheSubmissionEndTimeAndFinalizationTimestamp_whenWCEILPlusBucketDuration_lessThanFinalizationTimestamp(
    ) public {
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 101 * 1e15,
            totalGlwRewardsWeight: 100,
            totalGRCRewardsWeight: 200,
            randomMerkleRoot: bytes32(0)
        });

        uint256 n = block.timestamp;
        vm.warp(block.timestamp + 1 weeks);
        vm.startPrank(SIMON);
        minerPoolAndGCA.delayBucketFinalization({bucketId: 0});
        vm.stopPrank();

        //We are at n+1
        //The bucket finalizes at n+15
        //if we want WCEIL to be < , we can be in n+12 and run the slash
        // This SHOULD make the new submission end timestamp n+15
        vm.warp(n + 12 weeks);
        minerPoolAndGCA.incrementSlashNonce();

        uint256 submissionEndTimestamp = minerPoolAndGCA.calculateBucketSubmissionEndTimestamp(0);
        assertEq(submissionEndTimestamp, n + 14 weeks, "Submission end timestamp should be n+14  weeks");

        uint256 finalizationTimestampAfterResubmission = minerPoolAndGCA.bucket(0).finalizationTimestamp;
        // The new finalization should  stay at n+15 since the WCEIL + bucketDuration is less than the finalization timestamp
        assertEq(finalizationTimestampAfterResubmission, n + 15 weeks, "Finalization timestamp should be n+15 weeks");
    }

    function test_v2_resubmitThenDelay_multipleTimesThroughDifferentSlashNonces() public {
        vm.startPrank(SIMON);

        vm.warp(block.timestamp + 1 weeks); // n = 1
        minerPoolAndGCA.requestBucketResubmission({bucketId: 0});
        vm.warp(block.timestamp + 2 weeks); // n = 3
        minerPoolAndGCA.delayBucketFinalization({bucketId: 0});

        //Let's now increment the slash nonce
        minerPoolAndGCA.incrementSlashNonce();
        minerPoolAndGCA.incrementSlashNonce();
        minerPoolAndGCA.incrementSlashNonce();
        minerPoolAndGCA.incrementSlashNonce();
        minerPoolAndGCA.incrementSlashNonce();

        //Should be able to resubmit again, but not yet because we need to get to the end of the WCEIL
        //Let's first confirm that statement
        vm.expectRevert(IGCA.CannotDelayOrResubmitBucketWhereSubmissionsAreStillOpenOrNotYetOpen.selector);
        minerPoolAndGCA.requestBucketResubmission({bucketId: 0});
        vm.warp(block.timestamp + 1 weeks); // n = 4
        vm.expectRevert(IGCA.CannotDelayOrResubmitBucketWhereSubmissionsAreStillOpenOrNotYetOpen.selector);
        minerPoolAndGCA.requestBucketResubmission({bucketId: 0});

        uint256 finalizationTimestampBeforeResubmission2 = minerPoolAndGCA.bucket(0).finalizationTimestamp;
        vm.warp(block.timestamp + 1 weeks); // n = 5
        //Now we should be able to
        minerPoolAndGCA.requestBucketResubmission({bucketId: 0});

        uint256 finalizationTimestampAfterResubmission2 = minerPoolAndGCA.bucket(0).finalizationTimestamp;

        assertEq(
            finalizationTimestampAfterResubmission2,
            finalizationTimestampBeforeResubmission2 + 2 weeks,
            "Finalization timestamp should be 2 weeks from original after resubmission"
        );

        vm.stopPrank();

        //Log the block timestamp and the finalization timestamp after 2
        // // andalso log the submission end timestamp
        // console2.log("Current Timestamp: ", block.timestamp);
        // console2.log("Finalization Timestamp After 2: ", finalizationTimestampAfterResubmission2);
        // console2.log("Submission End Timestamp: ", minerPoolAndGCA.calculateBucketSubmissionEndTimestamp(0));

        //Log the bucket submission range()
        {
            (uint256 startSubmissionTimestamp, uint256 endSubmissionTimestamp,,) =
                minerPoolAndGCA.getBucketSubmissionRange(0);
            console2.log("Start Submission Timestamp: ", startSubmissionTimestamp);
            console2.log("End Submission Timestamp: ", endSubmissionTimestamp);
        }
        // We need to issue the report this time to avoid `CannotDelayBucketThatNeedsToUpdateSlashNonce`
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 101 * 1e15,
            totalGlwRewardsWeight: 100,
            totalGRCRewardsWeight: 200,
            randomMerkleRoot: bytes32(0)
        });

        vm.warp(block.timestamp + 2 weeks);
        vm.startPrank(SIMON);
        // minerPoolAndGCA.delayBucketFinalization({bucketId: 0});

        // uint256 finalizationTimestampAfterDelay2 = minerPoolAndGCA.bucket(0).finalizationTimestamp;
        // assertEq(
        //     finalizationTimestampAfterDelay2,
        //     finalizationTimestampAfterResubmission2 + minerPoolAndGCA.bucketDelayDuration(),
        //     "Finalization timestamp should be 2 weeks from original after resubmission"
        // );

        //TODO: Do it one more time

        //Let me write down another thought
        //is it possible that we can resubmit an empty bucket
        //Even if it has been slashed twice?

        vm.stopPrank();
    }

    function test_delayingAfterResubmission_shouldAdd13WeeksFromResubmissionFinalizationTimestamp() public {
        vm.startPrank(SIMON);

        vm.warp(block.timestamp + 1 weeks);
        minerPoolAndGCA.requestBucketResubmission({bucketId: 0});

        uint256 finalizationTimestampAfterResubmission = minerPoolAndGCA.bucket(0).finalizationTimestamp;

        vm.warp(block.timestamp + 2 weeks);
        //Should now be open for delay
        minerPoolAndGCA.delayBucketFinalization({bucketId: 0});

        uint256 finalizationTimestampAfterDelay = minerPoolAndGCA.bucket(0).finalizationTimestamp;
        assertEq(
            finalizationTimestampAfterDelay,
            finalizationTimestampAfterResubmission + minerPoolAndGCA.bucketDelayDuration(),
            "Finalization timestamp should be 13 weeks from resubmission finalization timestamp"
        );
        vm.stopPrank();
    }

    function test_v2_finalizedBucketShouldNeverBeAbleToBeUnfinalized(uint256) public {
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 1,
            totalGlwRewardsWeight: 1,
            totalGRCRewardsWeight: 1,
            randomMerkleRoot: bytes32(uint256(1))
        });

        //This gets finalized at n+2 weeks
        (,,, uint256 bucketFinalizationTimestamp) = minerPoolAndGCA.getBucketSubmissionRange(0);
        vm.warp(bucketFinalizationTimestamp);

        assertTrue(
            minerPoolAndGCA.isBucketFinalized({bucketId: 0}), "Bucket should be finalized on its finalization timestamp"
        );

        vm.startPrank(SIMON);
        //We shouldnt be able to delay or request reubmission
        vm.expectRevert(IGCA.BucketAlreadyFinalized.selector);
        minerPoolAndGCA.delayBucketFinalization({bucketId: 0});

        vm.expectRevert(IGCA.BucketAlreadyFinalized.selector);
        minerPoolAndGCA.requestBucketResubmission({bucketId: 0});

        //These should all be the same after a slash
        minerPoolAndGCA.incrementSlashNonce();

        assertTrue(
            minerPoolAndGCA.isBucketFinalized({bucketId: 0}),
            "Bucket should be finalized on its finalization timestamp even if a slash occurred"
        );

        //We shouldnt be able to delay or request reubmission
        vm.expectRevert(IGCA.BucketAlreadyFinalized.selector);
        minerPoolAndGCA.delayBucketFinalization({bucketId: 0});

        vm.expectRevert(IGCA.BucketAlreadyFinalized.selector);
        minerPoolAndGCA.requestBucketResubmission({bucketId: 0});

        //Let's make sure the finalization timestamp remained the same as well.
        vm.warp(block.timestamp + 10);
        (,,, uint256 finalizationTimestampAfterSlash) = minerPoolAndGCA.getBucketSubmissionRange(0);
        assertEq(finalizationTimestampAfterSlash, bucketFinalizationTimestamp, "Finalization should not change");

        // Let's try another slash one more time
        minerPoolAndGCA.incrementSlashNonce();

        (,,, finalizationTimestampAfterSlash) = minerPoolAndGCA.getBucketSubmissionRange(0);
        assertEq(finalizationTimestampAfterSlash, bucketFinalizationTimestamp, "Finalization should not change");

        vm.stopPrank();
    }

    function test_v2_delayedBucketShouldBeAbleToBeResubmitAfterLongTime() public {
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 1,
            totalGlwRewardsWeight: 1,
            totalGRCRewardsWeight: 1,
            randomMerkleRoot: bytes32(uint256(1))
        });

        vm.warp(block.timestamp + 1 weeks);

        vm.startPrank(SIMON);
        minerPoolAndGCA.delayBucketFinalization({bucketId: 0});

        //Warp forward 6 weeks;

        vm.warp(block.timestamp + 6 weeks);

        minerPoolAndGCA.incrementSlashNonce();

        vm.stopPrank();

        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 1,
            totalGlwRewardsWeight: 1,
            totalGRCRewardsWeight: 1,
            randomMerkleRoot: bytes32(uint256(1))
        });
    }

    function test_v2_shouldCorrectlyUpdateSlashNonce() public {
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 1,
            totalGlwRewardsWeight: 1,
            totalGRCRewardsWeight: 1,
            randomMerkleRoot: bytes32(uint256(1))
        });

        vm.startPrank(SIMON);

        //Increment the slash nonce three times
        minerPoolAndGCA.incrementSlashNonce(); //1
        vm.warp(block.timestamp + 1);
        minerPoolAndGCA.incrementSlashNonce(); // 2
        vm.warp(block.timestamp + 1);
        minerPoolAndGCA.incrementSlashNonce(); // 3
        vm.warp(block.timestamp + 1);

        vm.stopPrank();

        //Resubmit
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 1,
            totalGlwRewardsWeight: 1,
            totalGRCRewardsWeight: 1,
            randomMerkleRoot: bytes32(uint256(1))
        });

        uint256 bucketSlashNonce = minerPoolAndGCA.bucket(0).lastUpdatedNonce;
        assertEq(bucketSlashNonce, 3, "Slash nonce should match");
    }

    function test_v2_delayedBucket_bucketWhereSlashNonceIsNotUpdated_shouldRevertOnClaim() public {
        //Resubmit
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 1,
            totalGlwRewardsWeight: 1,
            totalGRCRewardsWeight: 1,
            randomMerkleRoot: bytes32(uint256(1))
        });

        vm.startPrank(SIMON);
        vm.warp(block.timestamp + 1 weeks);

        minerPoolAndGCA.delayBucketFinalization({bucketId: 0});

        vm.warp(block.timestamp + 6 weeks);
        vm.stopPrank();

        minerPoolAndGCA.incrementSlashNonce();
        vm.warp(block.timestamp + 9 weeks);

        assertTrue(
            minerPoolAndGCA.isBucketFinalized({bucketId: 0}),
            "Bucket should be finalized even if not valid to claim from"
        );
        //Try claiming
        vm.expectRevert(IGCA.BucketSlashNonceNotUpToDate.selector);
        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: 0,
            glwWeight: 10,
            usdcWeight: 10,
            proof: new bytes32[](0),
            flags: new bool[](0),
            tokens: new address[](0),
            index: 0,
            claimFromInflation: true
        });
        //Assert the bucket is finalized
    }

    function test_v2_delayedBucketUpdatingSlashNonceShouldBeAllowedToClaim_slashNonceMatchesOneInGlobalStorage()
        public
    {
        //Resubmit
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 1,
            totalGlwRewardsWeight: 1,
            totalGRCRewardsWeight: 1,
            randomMerkleRoot: bytes32(uint256(1))
        });

        vm.startPrank(SIMON);
        vm.warp(block.timestamp + 1 weeks);

        minerPoolAndGCA.delayBucketFinalization({bucketId: 0});

        vm.warp(block.timestamp + 6 weeks);
        vm.stopPrank();

        minerPoolAndGCA.incrementSlashNonce();
        // Reissuing the report should work now.

        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        uint256 totalGlwWeight;
        uint256 totalusdcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalusdcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                usdcWeight: 200 + i
            });
        }
        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdc);
        bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);

        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 100 ether,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalusdcWeight,
            randomMerkleRoot: root
        });
        vm.warp(block.timestamp + 9 weeks);

        assertTrue(
            minerPoolAndGCA.isBucketFinalized({bucketId: 0}), "Bucket should  finalize and be available to claim from"
        );
        //Try claiming

        vm.startPrank(defaultAddressInWithdraw);
        (bytes32[] memory proof, bool[] memory flags) = createClaimLeafProof(claimLeaves, payoutTokens, claimLeaves[0]);
        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: 0,
            glwWeight: 100,
            usdcWeight: 200,
            proof: proof,
            flags: flags,
            tokens: payoutTokens,
            index: 0,
            claimFromInflation: true
        });

        vm.stopPrank();
    }

    function test_v2_delayedBucket_bucketWhereSlashNonceIsNotUpdated_andMostUpdatedSlashNonce_doesNotMatchTheOneInStorage_shouldRevert(
    ) public {
        //Resubmit
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 1,
            totalGlwRewardsWeight: 1,
            totalGRCRewardsWeight: 1,
            randomMerkleRoot: bytes32(uint256(1))
        });

        vm.startPrank(SIMON);
        vm.warp(block.timestamp + 1 weeks);

        minerPoolAndGCA.delayBucketFinalization({bucketId: 0});

        vm.warp(block.timestamp + 6 weeks);
        vm.stopPrank();

        minerPoolAndGCA.incrementSlashNonce();
        vm.warp(block.timestamp + 9 weeks);
        //Bucket should be finalized
        minerPoolAndGCA.incrementSlashNonce();
        minerPoolAndGCA.incrementSlashNonce();
        minerPoolAndGCA.incrementSlashNonce();

        assertTrue(
            minerPoolAndGCA.isBucketFinalized({bucketId: 0}),
            "Bucket should be finalized even if not valid to claim from"
        );
        //Try claiming
        vm.expectRevert(IGCA.BucketSlashNonceNotUpToDate.selector);
        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: 0,
            glwWeight: 200,
            usdcWeight: 100,
            proof: new bytes32[](0),
            flags: new bool[](0),
            tokens: new address[](0),
            index: 0,
            claimFromInflation: true
        });
    }

    function test_v2_delayedBucketUpdatingSlashNonceShouldBeAllowedToClaim_slashNonceDoesNotMatchGlobalStorage()
        public
    {
        //Resubmit
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 1,
            totalGlwRewardsWeight: 1,
            totalGRCRewardsWeight: 1,
            randomMerkleRoot: bytes32(uint256(1))
        });

        vm.startPrank(SIMON);
        vm.warp(block.timestamp + 1 weeks);

        minerPoolAndGCA.delayBucketFinalization({bucketId: 0});

        vm.warp(block.timestamp + 6 weeks);
        vm.stopPrank();

        minerPoolAndGCA.incrementSlashNonce();
        // Reissuing the report should work now.

        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        uint256 totalGlwWeight;
        uint256 totalusdcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalusdcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                usdcWeight: 200 + i
            });
        }
        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdc);
        bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);

        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 100 ether,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalusdcWeight,
            randomMerkleRoot: root
        });
        vm.warp(block.timestamp + 9 weeks);

        assertTrue(
            minerPoolAndGCA.isBucketFinalized({bucketId: 0}), "Bucket should  finalize and be available to claim from"
        );
        //Slash here after finalization
        minerPoolAndGCA.incrementSlashNonce();

        vm.startPrank(defaultAddressInWithdraw);
        (bytes32[] memory proof, bool[] memory flags) = createClaimLeafProof(claimLeaves, payoutTokens, claimLeaves[0]);
        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: 0,
            glwWeight: 100,
            usdcWeight: 200,
            proof: proof,
            flags: flags,
            tokens: payoutTokens,
            index: 0,
            claimFromInflation: true
        });

        vm.stopPrank();
    }

    function test_v2_slashRightBeforeBucketSubmission_shouldNotInvalidateTheSubmissionOrBucket() public {
        vm.warp(block.timestamp + 1);
        minerPoolAndGCA.incrementSlashNonce();
        vm.warp(block.timestamp + 1);

        {
            ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
            uint256 totalGlwWeight;
            uint256 totalusdcWeight;
            for (uint256 i; i < claimLeaves.length; ++i) {
                totalGlwWeight += 100 + i;
                totalusdcWeight += 200 + i;
                claimLeaves[i] = ClaimLeaf({
                    payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                    glwWeight: 100 + i,
                    usdcWeight: 200 + i
                });
            }
            address[] memory payoutTokens = new address[](1);
            payoutTokens[0] = address(usdc);
            bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);

            issueReport({
                gcaToSubmitAs: SIMON,
                bucket: 0,
                totalNewGCC: 100 ether,
                totalGlwRewardsWeight: totalGlwWeight,
                totalGRCRewardsWeight: totalusdcWeight,
                randomMerkleRoot: root
            });

            vm.warp(block.timestamp + 2 weeks);

            assertTrue(
                minerPoolAndGCA.isBucketFinalized({bucketId: 0}),
                "Bucket should  finalize and be available to claim from"
            );

            vm.startPrank(defaultAddressInWithdraw);
            (bytes32[] memory proof, bool[] memory flags) =
                createClaimLeafProof(claimLeaves, payoutTokens, claimLeaves[0]);
            minerPoolAndGCA.claimRewardFromBucket({
                bucketId: 0,
                glwWeight: 100,
                usdcWeight: 200,
                proof: proof,
                flags: flags,
                tokens: payoutTokens,
                index: 0,
                claimFromInflation: true
            });
            vm.stopPrank();
        }
    }

    //Fork from above here ^^

    function test_issueBucket_slashBucket_reissueBucket_requestResubmission_shouldCorrectlyAdjustRange() public {
        uint256 n = block.timestamp;
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 1,
            totalGlwRewardsWeight: 1,
            totalGRCRewardsWeight: 1,
            randomMerkleRoot: bytes32(uint256(1))
        });

        vm.warp(n + 1 weeks);

        vm.startPrank(SIMON);
        minerPoolAndGCA.delayBucketFinalization({bucketId: 0});
        vm.stopPrank();

        minerPoolAndGCA.incrementSlashNonce();

        //before the request
        (
            uint256 startSubmissionTimestamp,
            uint256 endSubmissionTimestamp,
            uint256 shouldBeNonce,
            uint256 newFinalizationTimestamp
        ) = minerPoolAndGCA.getBucketSubmissionRange(0);

        assertEq(startSubmissionTimestamp, n + 1 weeks, "Submission start should correctly adjust");
        assertEq(endSubmissionTimestamp, n + 3 weeks, "End submission timestamp should be WCEIL(0) which is n+3");
        assertEq(shouldBeNonce, 1, "New nonce should match the most recent slash one");
        assertEq(
            newFinalizationTimestamp,
            n + 15 weeks,
            "since it was going to finalize on n+2, and we delay 13 weeks, it finalized at n+15"
        );

        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 1,
            totalGlwRewardsWeight: 1,
            totalGRCRewardsWeight: 1,
            randomMerkleRoot: bytes32(uint256(1))
        });

        //before the request
        (startSubmissionTimestamp, endSubmissionTimestamp, shouldBeNonce, newFinalizationTimestamp) =
            minerPoolAndGCA.getBucketSubmissionRange(0);

        assertEq(startSubmissionTimestamp, n + 1 weeks, "Submission start should correctly adjust");
        assertEq(endSubmissionTimestamp, n + 3 weeks, "End submission timestamp should be WCEIL(0) which is n+3");
        assertEq(shouldBeNonce, 1, "New nonce should match the most recent slash one");
        assertEq(
            newFinalizationTimestamp,
            n + 15 weeks,
            "since it was going to finalize on n+2, and we delay 13 weeks, it finalized at n+15"
        );
        // Start submission should now be at the nonce

        vm.startPrank(SIMON);
        vm.warp(n + 3 weeks);
        minerPoolAndGCA.requestBucketResubmission({bucketId: 0});
        vm.stopPrank();

        (,,, newFinalizationTimestamp) = minerPoolAndGCA.getBucketSubmissionRange(0);
        assertEq(
            newFinalizationTimestamp,
            n + 17 weeks,
            "Was finalizing n+15 and then requested resubmission, so should finalize at n+17"
        );

        //Let it finalize and then increment slash nonce and make sure the numbers still add up
        vm.warp(n + 17 weeks + 1);

        minerPoolAndGCA.incrementSlashNonce();
        (,,, newFinalizationTimestamp) = minerPoolAndGCA.getBucketSubmissionRange(0);

        //before the request
        (startSubmissionTimestamp, endSubmissionTimestamp, shouldBeNonce, newFinalizationTimestamp) =
            minerPoolAndGCA.getBucketSubmissionRange(0);

        assertEq(startSubmissionTimestamp, n + 1 weeks, "[end] Submission start should correctly adjust");
        assertEq(
            endSubmissionTimestamp,
            n + 5 weeks,
            "[end] End submission timestamp should be 2 weeks after original wceil which should be n+5 week"
        );
        assertEq(shouldBeNonce, 1, "[end] New nonce should match the most recent slash one");
        assertEq(minerPoolAndGCA.slashNonce(), 2, "[end] slash nonce should have incremented");
        assertEq(
            newFinalizationTimestamp,
            n + 17 weeks,
            "[end] since it was going to finalize on n+2, and we delay 13 weeks, it finalized at n+15"
        );
    }

    function test_v2_slashNonceMatchesLastUpdatedNonce_plusRedelayed_shouldReturnCorrectEndSubmissionTime() public {
        uint256 n = block.timestamp;
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 1,
            totalGlwRewardsWeight: 1,
            totalGRCRewardsWeight: 1,
            randomMerkleRoot: bytes32(uint256(1))
        });

        vm.warp(n + 1 weeks);

        vm.startPrank(SIMON);
        minerPoolAndGCA.incrementSlashNonce();
        //Right after resubmission, the stats should be different
        (
            uint256 startSubmissionTimestamp,
            uint256 endSubmissionTimestamp,
            uint256 slashNonceToUpgradeTo,
            uint256 finalizationTimestamp
        ) = minerPoolAndGCA.getBucketSubmissionRange({bucketId: 0});

        assertEq(startSubmissionTimestamp, n + 1 weeks, "Start submission should start the time of the new slash");
        assertEq(endSubmissionTimestamp, n + 3 weeks, "end submission should be wceil(0) which should be n+1+2 = n+3");
        assertEq(slashNonceToUpgradeTo, 1, "Because slash happened before finalization, it should be 1");
        assertEq(
            finalizationTimestamp, n + 4 weeks, "since there was a slash, finalization should be wceil(0) + 1 week"
        );

        vm.warp(n + 3 weeks);
        minerPoolAndGCA.requestBucketResubmission({bucketId: 0});
        vm.stopPrank();
        //Reissue it
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 1,
            totalGlwRewardsWeight: 1,
            totalGRCRewardsWeight: 1,
            randomMerkleRoot: bytes32(uint256(1))
        });

        //Also make sure the slash nonce is matching
        IGCA.Bucket memory zeroBucket = minerPoolAndGCA.bucket(0);
        //Slash nonce matches the once  storage now
        (, endSubmissionTimestamp,, finalizationTimestamp) = minerPoolAndGCA.getBucketSubmissionRange({bucketId: 0});
        assertEq(zeroBucket.lastUpdatedNonce, 1, "last updated nonce should be updated");
        assertEq(minerPoolAndGCA.slashNonce(), 1, "sanity check that we incremented the slash nonce");
        assertEq(
            endSubmissionTimestamp,
            n + 5 weeks,
            "End submission timestamp should have been delayed by 2 weeks and was previously n+3"
        );
        assertEq(
            finalizationTimestamp,
            n + 6 weeks,
            "Finalization timestamp should have been delayed by 2 weeks and was previously n+4"
        );
    }

    //Do the same as above but also for a delayed bucket

    function test_v2_wceilFinalizationTimestamp() public {
        uint256 n = block.timestamp;
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 1,
            totalGlwRewardsWeight: 1,
            totalGRCRewardsWeight: 1,
            randomMerkleRoot: bytes32(uint256(1))
        });

        vm.startPrank(SIMON);
        vm.warp(n + 1 weeks);
        minerPoolAndGCA.delayBucketFinalization({bucketId: 0});
        vm.stopPrank();

        //Before we slash, let's make sure finalization is n+15
        (,,, uint256 finalizationTimestampBefore) = minerPoolAndGCA.getBucketSubmissionRange({bucketId: 0});
        assertEq(finalizationTimestampBefore, n + 15 weeks, "Finalization timestamp should be n+15");
        //Bucket now finalizes at n+15
        vm.warp(n + 14 weeks);

        minerPoolAndGCA.incrementSlashNonce();

        //WCEIL of n+14 = 16, so it should finalize at n+17
        (,,, uint256 finalizationTimestamp) = minerPoolAndGCA.getBucketSubmissionRange({bucketId: 0});
        assertEq(
            finalizationTimestamp,
            n + 17 weeks,
            "finalization timestamp should update to WCEIl + 1 week, when wceil + 1 week > finalizationTimestamp"
        );

        //If i warp to n+16 - 1 second, i should be able to submit a report!
        vm.warp(n + 16 weeks - 1);
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 1,
            totalGlwRewardsWeight: 1,
            totalGRCRewardsWeight: 1,
            randomMerkleRoot: bytes32(uint256(1))
        });
    }

    //Also do one now where we submit it, then a slash happens,
    // then it should finalize at wceil + 1

    //^ The same but with not delayed buckets
    //Add also claiming from them to make sure
    //Now do all the aboves but with a wceil finalization timestamp

    //Test V2, Slash Nonce should match to latest one
    //Test V2, Compare finalization timestamp to WCEIL + 1 weeks
    //Test V2, should not finalize if not up to date with the slash nonce it should be up to date with ?
    /**
     * Invariants To Write:
     *   If a bucket has been delayed, it should be finalized  max(n+13,wceil(slashNonce)+1)
     *   Once a bucket has been finalized, it should never be able to be unfinalized.
     *   Other ones to think about how invariants work
     *         1. Delay + Resubmission Combinations
     */

    //-----------------------------------------------------------------//
    //--------------------- End Delay Tests ---------------------------//
    //-----------------------------------------------------------------//
    //TODO: Here
    function test_v2_guarded_claim_multiple_buckets_withdrawFromBucket() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        uint256 totalGlwWeight;
        uint256 totalusdcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalusdcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                usdcWeight: 200 + i
            });
        }

        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdc);
        bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);

        uint256 bucketId = 0;
        uint256 totalNewGCC = 101 * 1e15;

        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: bucketId,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalusdcWeight,
            randomMerkleRoot: root
        });
        //warp a week forward and submit another report at bucket + 1
        vm.warp(block.timestamp + ONE_WEEK);
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: bucketId + 1,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalusdcWeight,
            randomMerkleRoot: root
        });

        vm.warp(block.timestamp + (ONE_WEEK * 2));

        vm.startPrank(defaultAddressInWithdraw);
        uint256 glwWeightForAddress = 100;
        uint256 usdcWeightForAddress = 200;
        // minerPoolAndGCA.claimRewardFromBucket(bucketId, glwWeight, usdcWeight, proof, packedIndex, user, grcTokens, claimFromInflation);

        (bytes32[] memory proof, bool[] memory proofFlags) =
            createClaimLeafProof(claimLeaves, payoutTokens, claimLeaves[0]);

        //Use multicall to claim from both buckets

        {
            bytes[] memory data = new bytes[](2);
            data[0] = abi.encodeWithSelector(
                minerPoolAndGCA.claimRewardFromBucket.selector,
                bucketId,
                glwWeightForAddress,
                usdcWeightForAddress,
                proof,
                proofFlags,
                payoutTokens,
                0,
                true
            );

            data[1] = abi.encodeWithSelector(
                minerPoolAndGCA.claimRewardFromBucket.selector,
                bucketId + 1,
                glwWeightForAddress,
                usdcWeightForAddress,
                proof,
                proofFlags,
                payoutTokens,
                0,
                true
            );

            minerPoolAndGCA.multicall({data: data});
        }

        // Should have gotten all the glow rewards twice
        assertEq(
            glow.balanceOf((defaultAddressInWithdraw)), ((175_000 ether * glwWeightForAddress) / totalGlwWeight) * 2
        );

        vm.stopPrank();
    }

    function test_v2_guarded_withdrawFromBucket_glowWeightGreaterThanUint64Max_ShouldRevert() public {
        vm.startPrank(defaultAddressInWithdraw);
        // uint
        {
            // usdc.mint(address(defaultAddressInWithdraw), 100000000000000 ether);
            mintUSDG(defaultAddressInWithdraw, 100000000000000 ether);
            usdg.approve(address(minerPoolAndGCA), 100000000000000 ether);
            minerPoolAndGCA.donateTokenToMinerRewardsPool(address(usdg), 100000000000000 ether);
        }
        vm.stopPrank();

        vm.warp(block.timestamp + (ONE_WEEK * minerPoolAndGCA.OFFSET_LEFT()));

        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdc);
        uint256 totalGlwWeight;
        uint256 totalusdcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += type(uint64).max / 40;
            totalusdcWeight += type(uint64).max / 40;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: uint256(type(uint64).max) + 1,
                usdcWeight: 10
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);
        uint256 bucketId = minerPoolAndGCA.OFFSET_LEFT();

        {
            uint256 totalNewGCC = 101 * 1e15;

            issueReport({
                gcaToSubmitAs: SIMON,
                bucket: bucketId,
                totalNewGCC: totalNewGCC,
                totalGlwRewardsWeight: totalGlwWeight,
                totalGRCRewardsWeight: totalusdcWeight,
                randomMerkleRoot: root
            });
        }

        vm.warp(block.timestamp + (ONE_WEEK * 2));

        vm.startPrank(defaultAddressInWithdraw);

        uint256 glwWeightForAddress = uint256(type(uint64).max) + 1;
        uint256 usdcWeightForAddress = 10;

        (bytes32[] memory proof, bool[] memory flags) = createClaimLeafProof(claimLeaves, payoutTokens, claimLeaves[0]);

        vm.expectRevert();
        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: bucketId,
            glwWeight: glwWeightForAddress,
            usdcWeight: usdcWeightForAddress,
            proof: proof,
            flags: flags,
            tokens: payoutTokens,
            index: 0,
            claimFromInflation: true
        });
    }

    function test_v2_guarded_withdrawFromBucket_usdcWeightGreaterThanUint64Max_ShouldRevert() public {
        vm.startPrank(defaultAddressInWithdraw);
        // uint
        {
            // usdc.mint(address(defaultAddressInWithdraw), 100000000000000 ether);
            mintUSDG(defaultAddressInWithdraw, 100000000000000 ether);
            usdg.approve(address(minerPoolAndGCA), 100000000000000 ether);
            minerPoolAndGCA.donateTokenToMinerRewardsPool(address(usdg), 100000000000000 ether);
        }
        vm.stopPrank();

        vm.warp(block.timestamp + (ONE_WEEK * minerPoolAndGCA.OFFSET_LEFT()));

        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdc);
        uint256 totalGlwWeight;
        uint256 totalusdcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += type(uint64).max / 40;
            totalusdcWeight += type(uint64).max / 40;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 10,
                usdcWeight: uint256(type(uint64).max) + 1
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);
        uint256 bucketId = minerPoolAndGCA.OFFSET_LEFT();

        {
            uint256 totalNewGCC = 101 * 1e15;

            issueReport({
                gcaToSubmitAs: SIMON,
                bucket: bucketId,
                totalNewGCC: totalNewGCC,
                totalGlwRewardsWeight: totalGlwWeight,
                totalGRCRewardsWeight: totalusdcWeight,
                randomMerkleRoot: root
            });
        }
        vm.warp(block.timestamp + (ONE_WEEK * 2));

        vm.startPrank(defaultAddressInWithdraw);

        uint256 glwWeightForAddress = 10;
        uint256 usdcWeightForAddress = uint256(type(uint64).max) + 1;

        (bytes32[] memory proof, bool[] memory flags) = createClaimLeafProof(claimLeaves, payoutTokens, claimLeaves[0]);

        vm.expectRevert();
        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: bucketId,
            glwWeight: glwWeightForAddress,
            usdcWeight: usdcWeightForAddress,
            proof: proof,
            flags: flags,
            tokens: payoutTokens,
            index: 0,
            claimFromInflation: true
        });
    }

    function test_v2_guarded_withdrawFromBucket_weightGreaterThan_totalWeight_shouldRevert() public {
        vm.startPrank(defaultAddressInWithdraw);
        // uint
        {
            // usdc.mint(address(defaultAddressInWithdraw), 100000000000000 ether);
            mintUSDG(defaultAddressInWithdraw, 100000000000000 ether);
            usdg.approve(address(minerPoolAndGCA), 100000000000000 ether);
            minerPoolAndGCA.donateTokenToMinerRewardsPool(address(usdg), 100000000000000 ether);
        }
        vm.stopPrank();

        vm.warp(block.timestamp + (ONE_WEEK * minerPoolAndGCA.OFFSET_LEFT()));

        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](1);
        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdc);
        uint256 totalGlwWeight;
        uint256 totalusdcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100;
            totalusdcWeight += 200;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 101,
                usdcWeight: 200
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);
        uint256 bucketId = minerPoolAndGCA.OFFSET_LEFT();

        {
            uint256 totalNewGCC = 101 * 1e15;

            issueReport({
                gcaToSubmitAs: SIMON,
                bucket: bucketId,
                totalNewGCC: totalNewGCC,
                totalGlwRewardsWeight: totalGlwWeight,
                totalGRCRewardsWeight: totalusdcWeight,
                randomMerkleRoot: root
            });
        }

        vm.warp(block.timestamp + (ONE_WEEK * 2));

        vm.startPrank(defaultAddressInWithdraw);

        uint256 glwWeightForAddress = 101;
        uint256 usdcWeightForAddress = 200;

        (bytes32[] memory proof, bool[] memory flags) = createClaimLeafProof(claimLeaves, payoutTokens, claimLeaves[0]);

        vm.expectRevert(IMinerPool.GlowWeightOverflow.selector);
        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: bucketId,
            glwWeight: glwWeightForAddress,
            usdcWeight: usdcWeightForAddress,
            proof: proof,
            flags: flags,
            tokens: payoutTokens,
            index: 0,
            claimFromInflation: true
        });
    }

    function test_v2_guarded_withdrawFromBucket_usdcWeightGreaterThan_totalWeight_shouldRevert() public {
        vm.startPrank(defaultAddressInWithdraw);
        {
            // uint
            // usdc.mint(address(defaultAddressInWithdraw), 100000000000000 ether);
            mintUSDG(defaultAddressInWithdraw, 100000000000000 ether);
            usdg.approve(address(minerPoolAndGCA), 100000000000000 ether);
            minerPoolAndGCA.donateTokenToMinerRewardsPool(address(usdg), 100000000000000 ether);
        }
        vm.stopPrank();

        vm.warp(block.timestamp + (ONE_WEEK * minerPoolAndGCA.OFFSET_LEFT()));

        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](1);
        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdc);
        uint256 totalGlwWeight;
        uint256 totalusdcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100;
            totalusdcWeight += 200;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100,
                usdcWeight: 201
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);
        uint256 bucketId = minerPoolAndGCA.OFFSET_LEFT();

        {
            uint256 totalNewGCC = 101 * 1e15;

            issueReport({
                gcaToSubmitAs: SIMON,
                bucket: bucketId,
                totalNewGCC: totalNewGCC,
                totalGlwRewardsWeight: totalGlwWeight,
                totalGRCRewardsWeight: totalusdcWeight,
                randomMerkleRoot: root
            });
        }
        vm.warp(block.timestamp + (ONE_WEEK * 2));

        vm.startPrank(defaultAddressInWithdraw);

        uint256 glwWeightForAddress = 100;
        uint256 usdcWeightForAddress = 201;

        (bytes32[] memory proof, bool[] memory flags) = createClaimLeafProof(claimLeaves, payoutTokens, claimLeaves[0]);
        vm.expectRevert(IMinerPool.USDCWeightOverflow.selector);
        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: bucketId,
            glwWeight: glwWeightForAddress,
            usdcWeight: usdcWeightForAddress,
            proof: proof,
            flags: flags,
            tokens: payoutTokens,
            index: 0,
            claimFromInflation: true
        });
    }

    // // function test_v2_guarded_withdrawFromBucket_uint64Max_thenPlusOne_shouldRevert() public {
    // //     vm.startPrank(defaultAddressInWithdraw);
    // //     // uint
    // //     {
    // //         usdc.mint(address(defaultAddressInWithdraw), 100000000000000 ether);
    // //         usdc.approve(address(minerPoolAndGCA), 100000000000000 ether);
    // //         minerPoolAndGCA.donateTokenToMinerRewardsPool(100000000000000 ether);
    // //     }
    // //     vm.stopPrank();

    // //     vm.warp(block.timestamp + (ONE_WEEK * minerPoolAndGCA.OFFSET_LEFT()));

    // //     ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](1);
    // //     uint256 totalGlwWeight;
    // //     uint256 totalusdcWeight;
    // //     for (uint256 i; i < claimLeaves.length; ++i) {
    // //         totalGlwWeight += type(uint64).max / 5;
    // //         totalusdcWeight += type(uint64).max / 5;
    // //         claimLeaves[i] = ClaimLeaf({
    // //             payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
    // //             glwWeight: type(),
    // //             usdcWeight: 201
    // //         });
    // //     }
    // //     bytes32 root = createClaimLeafRoot(claimLeaves);
    // //     uint256 bucketId = minerPoolAndGCA.OFFSET_LEFT();
    // //     uint256 totalNewGCC = 101 * 1e15;

    // //     issueReport({
    // //         gcaToSubmitAs: SIMON,
    // //         bucket: bucketId,
    // //         totalNewGCC: totalNewGCC,
    // //         totalGlwRewardsWeight: totalGlwWeight,
    // //         totalGRCRewardsWeight: totalusdcWeight,
    // //         randomMerkleRoot: root
    // //     });

    // //     vm.warp(block.timestamp + (ONE_WEEK * 2));

    // //     vm.startPrank(defaultAddressInWithdraw);

    // //     uint256 glwWeightForAddress = 100;
    // //     uint256 usdcWeightForAddress = 201;
    // //     vm.expectRevert(IMinerPool.USDCWeightOverflow.selector);
    // //     minerPoolAndGCA.claimRewardFromBucket({
    // //         bucketId: bucketId,
    // //         glwWeight: glwWeightForAddress,
    // //         usdcWeight: usdcWeightForAddress,
    // //         proof: createClaimLeafProof(claimLeaves, claimLeaves[0]),
    // //         index: 0,
    // //         user: (defaultAddressInWithdraw),
    // //         claimFromInflation: true,
    // //         signature: bytes("")
    // //     });
    // // }

    function test_v2_guarded_isBucketFinalized_bucketFinalizedBeforeSlash_shouldReturnTrue() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdc);

        uint256 totalGlwWeight;
        uint256 totalusdcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalusdcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                usdcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);
        uint256 bucketId = 0;
        uint256 totalNewGCC = 101 * 1e15;

        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: bucketId,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalusdcWeight,
            randomMerkleRoot: root
        });

        vm.warp(block.timestamp + 2 weeks);

        vm.startPrank(defaultAddressInWithdraw);

        vm.stopPrank();

        address[] memory gcasToSlash = new address[](1);
        gcasToSlash[0] = OTHER_GCA;
        address[] memory newGCAs = new address[](1);
        newGCAs[0] = SIMON;
        bytes32 hash = keccak256(abi.encode(gcasToSlash, newGCAs));
        minerPoolAndGCA.pushRequirementsHashMock(hash);
        minerPoolAndGCA.incrementSlashNonce();
        minerPoolAndGCA.executeAgainstHash(gcasToSlash, newGCAs);

        assertTrue(minerPoolAndGCA.isBucketFinalized(bucketId), "The bucket should be finalized");
    }

    function test_v2_guarded_claimReward_indexOutOfBounds_shouldRevert() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdc);

        uint256 totalGlwWeight;
        uint256 totalusdcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalusdcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                usdcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);
        uint256 bucketId = 0;
        uint256 totalNewGCC = 101 * 1e15;
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: bucketId,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalusdcWeight,
            randomMerkleRoot: root
        });
        issueReport({
            gcaToSubmitAs: OTHER_GCA,
            bucket: bucketId,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalusdcWeight,
            randomMerkleRoot: root
        });

        {
            IGCA.Bucket memory bucket = minerPoolAndGCA.bucket(bucketId);

            assertEq(bucket.originalNonce, 0, "Original nonce should be 0");
            assertEq(bucket.lastUpdatedNonce, 0, "Last updated nonce should be 0");
            assertEq(bucket.reports.length, 2, "Reports length should be 2");

            vm.warp(block.timestamp + (ONE_WEEK * 2) - 1);

            address[] memory gcasToSlash = new address[](1);
            gcasToSlash[0] = OTHER_GCA;
            address[] memory newGCAs = new address[](1);
            newGCAs[0] = SIMON;
            bytes32 hash = keccak256(abi.encode(gcasToSlash, newGCAs));
            minerPoolAndGCA.pushRequirementsHashMock(hash);
            minerPoolAndGCA.incrementSlashNonce();
            minerPoolAndGCA.executeAgainstHash(gcasToSlash, newGCAs);

            issueReport({
                gcaToSubmitAs: SIMON,
                bucket: bucketId,
                totalNewGCC: totalNewGCC,
                totalGlwRewardsWeight: totalGlwWeight,
                totalGRCRewardsWeight: totalusdcWeight,
                randomMerkleRoot: root
            });

            bucket = minerPoolAndGCA.bucket(bucketId);
            assertEq(bucket.originalNonce, 0, "Original nonce should be 0");
            assertEq(bucket.lastUpdatedNonce, 1, "Last updated nonce should be 1");
            assertEq(bucket.reports.length, 1, "Reports length should be 1");
        }
        vm.startPrank(defaultAddressInWithdraw);
        vm.warp(block.timestamp + (ONE_WEEK * 13) + 1);
        // uint256 glwWeightForAddress = 100;
        // uint256 usdcWeightForAddress = 200;
        {
            //claiming from index 1 should fail since
            //it got deleted in the slash event
            (bytes32[] memory proof, bool[] memory flags) =
                createClaimLeafProof(claimLeaves, payoutTokens, claimLeaves[0]);
            vm.expectRevert(BUCKET_OUT_OF_BOUNDS_SIG);
            minerPoolAndGCA.claimRewardFromBucket({
                bucketId: bucketId,
                glwWeight: 100,
                usdcWeight: 200,
                proof: proof,
                flags: flags,
                tokens: payoutTokens,
                index: 1,
                claimFromInflation: true
            });

            //claiming from index zero should be ok.

            minerPoolAndGCA.claimRewardFromBucket({
                bucketId: bucketId,
                glwWeight: 100,
                usdcWeight: 200,
                proof: proof,
                flags: flags,
                tokens: payoutTokens,
                index: 0,
                claimFromInflation: true
            });
        }
        vm.stopPrank();
    }

    function test_v2_guarded_isBucketFinalized_bucketNotFinalizedBeforeSlash_shouldReturnFalse() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdc);
        uint256 totalGlwWeight;
        uint256 totalusdcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalusdcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                usdcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);
        uint256 bucketId = 0;
        uint256 totalNewGCC = 101 * 1e15;

        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: bucketId,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalusdcWeight,
            randomMerkleRoot: root
        });

        vm.warp(block.timestamp + (ONE_WEEK * 2) - 20);

        vm.startPrank(defaultAddressInWithdraw);

        vm.stopPrank();

        address[] memory gcasToSlash = new address[](1);
        gcasToSlash[0] = OTHER_GCA;
        address[] memory newGCAs = new address[](1);
        newGCAs[0] = SIMON;
        uint256 ts = block.timestamp;
        bytes32 hash = keccak256(abi.encode(gcasToSlash, newGCAs));
        minerPoolAndGCA.pushRequirementsHashMock(hash);
        minerPoolAndGCA.incrementSlashNonce();
        minerPoolAndGCA.executeAgainstHash(gcasToSlash, newGCAs);

        //Warp past the original expiration
        vm.warp(block.timestamp + 21);
        //It should not be finalized since the slash nonce does not match
        //and the bucket has not been reinstated.
        assertTrue(!minerPoolAndGCA.isBucketFinalized(bucketId), "Bucket should be finalized");
    }

    function testFuzz_currentWeekInternal_makeCoverageHappy(uint256 warpSeconds) public {
        vm.assume(warpSeconds < 500_000 weeks);
        vm.warp(block.timestamp + warpSeconds);
        uint256 currentWeek = minerPoolAndGCA.currentWeekInternal();
        assertEq(minerPoolAndGCA.currentBucket(), currentWeek);
    }

    function test_v2_guarded_withdrawFromBucket_shouldAddToHoldings() public {
        vm.startPrank(SIMON);
        uint256 amountGRCToDonate = 1_000_000 * 1e6;
        uint256 expectedAmountInEachBucket = amountGRCToDonate / VESTING_PERIODS;
        mintUSDG(SIMON, amountGRCToDonate);
        usdg.approve(address(minerPoolAndGCA), amountGRCToDonate);
        minerPoolAndGCA.donateTokenToMinerRewardsPool(address(usdg), amountGRCToDonate);
        vm.stopPrank();

        //Go to the OFFSET_LEFT bucket since that's where the grc tokens start unlocking
        vm.warp(block.timestamp + ONE_WEEK * minerPoolAndGCA.OFFSET_LEFT());
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdg);

        uint256 totalGlwWeight;
        uint256 totalusdcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalusdcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                usdcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);
        uint256 bucketId = minerPoolAndGCA.OFFSET_LEFT();

        {
            uint256 totalNewGCC = 101 * 1e15;

            issueReport({
                gcaToSubmitAs: SIMON,
                bucket: bucketId,
                totalNewGCC: totalNewGCC,
                totalGlwRewardsWeight: totalGlwWeight,
                totalGRCRewardsWeight: totalusdcWeight,
                randomMerkleRoot: root
            });
        }

        vm.warp(block.timestamp + (ONE_WEEK * 2));

        vm.startPrank(defaultAddressInWithdraw);
        uint256 glwWeightForAddress = 100;
        uint256 usdcWeightForAddress = 200;

        (bytes32[] memory proof, bool[] memory flags) = createClaimLeafProof(claimLeaves, payoutTokens, claimLeaves[0]);

        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: bucketId,
            glwWeight: glwWeightForAddress,
            usdcWeight: usdcWeightForAddress,
            proof: proof,
            flags: flags,
            tokens: payoutTokens,
            index: 0,
            claimFromInflation: true
        });

        //Should have gotten all the glow rewards
        assertEq(glow.balanceOf((defaultAddressInWithdraw)), (175_000 ether * glwWeightForAddress) / totalGlwWeight);
        assertEq(
            uint256(holdingContract.holdings(defaultAddressInWithdraw, address(usdg)).amount),
            (expectedAmountInEachBucket * usdcWeightForAddress) / totalusdcWeight
        );

        //Revert if it hasn't been a week
        vm.expectRevert(SafetyDelay.WithdrawalNotReady.selector);
        holdingContract.claimHoldingSingleton(defaultAddressInWithdraw, address(usdg));

        //Warp one week
        vm.warp(block.timestamp + ONE_WEEK);
        //Should be able to claim now
        holdingContract.claimHoldingSingleton(defaultAddressInWithdraw, address(usdg));
        assertEq(
            usdg.balanceOf(defaultAddressInWithdraw),
            (expectedAmountInEachBucket * usdcWeightForAddress) / totalusdcWeight
        );
        vm.stopPrank();
    }

    function test_v2_guarded_withdrawFromBucket_multipleTokens_shouldAddToHoldings() public {
        vm.startPrank(SIMON);
        uint256 amountGRCToDonate = 1_000_000 * 1e6;
        uint256 expectedAmountInEachBucket = amountGRCToDonate / VESTING_PERIODS;
        mintUSDG(SIMON, amountGRCToDonate);
        usdg.approve(address(minerPoolAndGCA), amountGRCToDonate);
        minerPoolAndGCA.donateTokenToMinerRewardsPool(address(usdg), amountGRCToDonate);
        //Also send USDC
        usdc.mint(SIMON, amountGRCToDonate / 2);
        usdc.approve(address(minerPoolAndGCA), amountGRCToDonate / 2);
        minerPoolAndGCA.donateTokenToMinerRewardsPool(address(usdc), amountGRCToDonate / 2);

        vm.stopPrank();

        //Go to the OFFSET_LEFT bucket since that's where the grc tokens start unlocking
        vm.warp(block.timestamp + ONE_WEEK * minerPoolAndGCA.OFFSET_LEFT());
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        address[] memory payoutTokens = new address[](2);
        payoutTokens[0] = address(usdg);
        payoutTokens[1] = address(usdc);

        uint256 totalGlwWeight;
        uint256 totalusdcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalusdcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                usdcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);
        uint256 bucketId = minerPoolAndGCA.OFFSET_LEFT();

        {
            uint256 totalNewGCC = 101 * 1e15;

            issueReport({
                gcaToSubmitAs: SIMON,
                bucket: bucketId,
                totalNewGCC: totalNewGCC,
                totalGlwRewardsWeight: totalGlwWeight,
                totalGRCRewardsWeight: totalusdcWeight,
                randomMerkleRoot: root
            });
        }

        vm.warp(block.timestamp + (ONE_WEEK * 2));

        vm.startPrank(defaultAddressInWithdraw);
        uint256 glwWeightForAddress = 100;
        uint256 usdcWeightForAddress = 200;

        (bytes32[] memory proof, bool[] memory flags) = createClaimLeafProof(claimLeaves, payoutTokens, claimLeaves[0]);

        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: bucketId,
            glwWeight: glwWeightForAddress,
            usdcWeight: usdcWeightForAddress,
            proof: proof,
            flags: flags,
            tokens: payoutTokens,
            index: 0,
            claimFromInflation: true
        });

        //Should have gotten all the glow rewards
        assertEq(glow.balanceOf((defaultAddressInWithdraw)), (175_000 ether * glwWeightForAddress) / totalGlwWeight);
        assertEq(
            uint256(holdingContract.holdings(defaultAddressInWithdraw, address(usdg)).amount),
            (expectedAmountInEachBucket * usdcWeightForAddress) / totalusdcWeight
        );
        //also assert for usdc that it's / 2
        assertEq(
            uint256(holdingContract.holdings(defaultAddressInWithdraw, address(usdc)).amount),
            (expectedAmountInEachBucket / 2 * usdcWeightForAddress) / totalusdcWeight,
            "USDC should also match in the holdings"
        );

        //Revert if it hasn't been a week
        vm.expectRevert(SafetyDelay.WithdrawalNotReady.selector);
        holdingContract.claimHoldingSingleton(defaultAddressInWithdraw, address(usdg));

        vm.expectRevert(SafetyDelay.WithdrawalNotReady.selector);
        holdingContract.claimHoldingSingleton(defaultAddressInWithdraw, address(usdc));

        //Warp one week
        vm.warp(block.timestamp + ONE_WEEK);
        //Should be able to claim now
        holdingContract.claimHoldingSingleton(defaultAddressInWithdraw, address(usdg));
        assertEq(
            usdg.balanceOf(defaultAddressInWithdraw),
            (expectedAmountInEachBucket * usdcWeightForAddress) / totalusdcWeight
        );
        //check for usdc now
        holdingContract.claimHoldingSingleton(defaultAddressInWithdraw, address(usdc));
        assertEq(
            usdc.balanceOf(defaultAddressInWithdraw),
            (expectedAmountInEachBucket / 2 * usdcWeightForAddress) / totalusdcWeight
        );
        vm.stopPrank();
    }

    function test_v2_guarded_withdrawFromBucket_glwWeightsInTwoTransactions_gtBucketGlobalState_shouldRevertOnSecond()
        public
    {
        vm.startPrank(SIMON);
        uint256 amountGRCToDonate = 1_000_000 * 1e6;
        uint256 expectedAmountInEachBucket = amountGRCToDonate / VESTING_PERIODS;
        // usdc.mint(SIMON, amountGRCToDonate);
        // usdc.approve(address(minerPoolAndGCA), amountGRCToDonate);
        mintUSDG(SIMON, amountGRCToDonate);
        usdg.approve(address(minerPoolAndGCA), amountGRCToDonate);
        minerPoolAndGCA.donateTokenToMinerRewardsPool(address(usdg), amountGRCToDonate);
        vm.stopPrank();

        //Go to the OFFSET_LEFT bucket since that's where the grc tokens start unlocking
        vm.warp(block.timestamp + ONE_WEEK * minerPoolAndGCA.OFFSET_LEFT());
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](2);
        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdg);
        {
            claimLeaves[0] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + 0)),
                glwWeight: 100,
                usdcWeight: 200
            });

            claimLeaves[1] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + 1)),
                glwWeight: 100,
                usdcWeight: 200
            });
        }
        uint256 glwWeight = 199; //1 less than the actual in the leaves
        uint256 usdcWeight = 400;
        bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);
        uint256 bucketId = minerPoolAndGCA.OFFSET_LEFT();

        {
            uint256 totalNewGCC = 101 * 1e15;

            issueReport({
                gcaToSubmitAs: SIMON,
                bucket: bucketId,
                totalNewGCC: totalNewGCC,
                totalGlwRewardsWeight: glwWeight,
                totalGRCRewardsWeight: usdcWeight,
                randomMerkleRoot: root
            });
        }

        vm.warp(block.timestamp + (ONE_WEEK * 2));

        vm.startPrank(defaultAddressInWithdraw);
        uint256 glwWeightForAddress = 100;
        uint256 usdcWeightForAddress = 200;
        // minerPoolAndGCA.claimRewardFromBucket(bucketId, glwWeight, usdcWeight, proof, packedIndex, user, grcTokens, claimFromInflation);
        (bytes32[] memory proof, bool[] memory flags) = createClaimLeafProof(claimLeaves, payoutTokens, claimLeaves[0]);
        {
            (,,, uint256 finalizationTimestamp) = minerPoolAndGCA.getBucketSubmissionRange({bucketId: 0});
            console2.log("Finalization Timestamp = ", finalizationTimestamp);
        }
        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: bucketId,
            glwWeight: glwWeightForAddress,
            usdcWeight: usdcWeightForAddress,
            proof: proof,
            flags: flags,
            tokens: payoutTokens,
            index: 0,
            claimFromInflation: true
        });
        vm.stopPrank();

        vm.startPrank(address(uint160(uint160(defaultAddressInWithdraw) + 1)));

        (proof, flags) = createClaimLeafProof(claimLeaves, payoutTokens, claimLeaves[1]);
        //If we try to claim with the correct proof, it should overflow the glow weight first

        {
            (,,, uint256 finalizationTimestamp) = minerPoolAndGCA.getBucketSubmissionRange({bucketId: 0});
            console2.log("Finalization Timestamp = ", finalizationTimestamp);
        }
        vm.expectRevert(IMinerPool.GlowWeightOverflow.selector);
        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: bucketId,
            glwWeight: glwWeightForAddress,
            usdcWeight: usdcWeightForAddress,
            proof: proof,
            flags: flags,
            tokens: payoutTokens,
            index: 0,
            claimFromInflation: true
        });
    }

    function test_v2_guarded_withdrawFromBucket_usdcWeightsInTwoTransactions_gtBucketGlobalState_shouldRevertOnSecond()
        public
    {
        vm.startPrank(SIMON);
        uint256 amountGRCToDonate = 1_000_000 * 1e6;
        uint256 expectedAmountInEachBucket = amountGRCToDonate / VESTING_PERIODS;
        mintUSDG(SIMON, amountGRCToDonate);
        usdg.approve(address(minerPoolAndGCA), amountGRCToDonate);
        minerPoolAndGCA.donateTokenToMinerRewardsPool(address(usdg), amountGRCToDonate);
        vm.stopPrank();

        //Go to the OFFSET_LEFT bucket since that's where the grc tokens start unlocking
        vm.warp(block.timestamp + ONE_WEEK * minerPoolAndGCA.OFFSET_LEFT());
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](2);
        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdg);
        {
            claimLeaves[0] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + 0)),
                glwWeight: 100,
                usdcWeight: 200
            });

            claimLeaves[1] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + 1)),
                glwWeight: 100,
                usdcWeight: 200
            });
        }
        uint256 glwWeight = 200; //1 less than the actual in the leaves
        uint256 usdcWeight = 399;
        bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);
        uint256 bucketId = minerPoolAndGCA.OFFSET_LEFT();

        {
            uint256 totalNewGCC = 101 * 1e15;

            issueReport({
                gcaToSubmitAs: SIMON,
                bucket: bucketId,
                totalNewGCC: totalNewGCC,
                totalGlwRewardsWeight: glwWeight,
                totalGRCRewardsWeight: usdcWeight,
                randomMerkleRoot: root
            });
        }
        vm.warp(block.timestamp + (ONE_WEEK * 2));

        vm.startPrank(defaultAddressInWithdraw);
        uint256 glwWeightForAddress = 100;
        uint256 usdcWeightForAddress = 200;
        // minerPoolAndGCA.claimRewardFromBucket(bucketId, glwWeight, usdcWeight, proof, packedIndex, user, grcTokens, claimFromInflation);
        (bytes32[] memory proof, bool[] memory flags) = createClaimLeafProof(claimLeaves, payoutTokens, claimLeaves[0]);
        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: bucketId,
            glwWeight: glwWeightForAddress,
            usdcWeight: usdcWeightForAddress,
            proof: proof,
            flags: flags,
            tokens: payoutTokens,
            index: 0,
            claimFromInflation: true
        });
        vm.stopPrank();

        vm.startPrank(address(uint160(uint160(defaultAddressInWithdraw) + 1)));
        //If we try to claim with the correct proof, it should overflow the glow weight first

        (proof, flags) = createClaimLeafProof(claimLeaves, payoutTokens, claimLeaves[1]);
        vm.expectRevert(IMinerPool.USDCWeightOverflow.selector);
        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: bucketId,
            glwWeight: glwWeightForAddress,
            usdcWeight: usdcWeightForAddress,
            proof: proof,
            flags: flags,
            tokens: payoutTokens,
            index: 0,
            claimFromInflation: true
        });

        vm.stopPrank();
    }

    function test_v2_guarded_handleMintToCarbonCreditAuction() public {
        vm.startPrank(SIMON);
        uint256 amountGRCToDonate = 1_000_000 * 1e6;
        uint256 expectedAmountInEachBucket = amountGRCToDonate / VESTING_PERIODS;
        mintUSDG(SIMON, amountGRCToDonate);
        usdg.approve(address(minerPoolAndGCA), amountGRCToDonate);
        minerPoolAndGCA.donateTokenToMinerRewardsPool(address(usdg), amountGRCToDonate);
        vm.stopPrank();

        //Go to the OFFSET_LEFT bucket since that's where the grc tokens start unlocking
        vm.warp(block.timestamp + ONE_WEEK * minerPoolAndGCA.OFFSET_LEFT());
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdg);

        uint256 totalGlwWeight;
        uint256 totalusdcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalusdcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                usdcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);
        uint256 bucketId = minerPoolAndGCA.OFFSET_LEFT();
        uint256 totalNewGCC = 101 * 1e15;

        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: bucketId,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalusdcWeight,
            randomMerkleRoot: root
        });

        vm.warp(block.timestamp + (ONE_WEEK * 2));

        minerPoolAndGCA.handleMintToCarbonCreditAuction(minerPoolAndGCA.OFFSET_LEFT());
    }

    function test_v2_guarded_handleMintToCarbonCreditAuction_mintingTwice_shouldNotMint_andNotRevert() public {
        test_v2_guarded_handleMintToCarbonCreditAuction();
        uint256 gccBalanceBeforeSecondMint = gcc.balanceOf(address(carbonCreditAuction));
        minerPoolAndGCA.handleMintToCarbonCreditAuction(minerPoolAndGCA.OFFSET_LEFT());
        uint256 gccBalanceAfterSecondMint = gcc.balanceOf(address(carbonCreditAuction));
        assert(gccBalanceAfterSecondMint == gccBalanceBeforeSecondMint);
    }

    function testFuzz_handleMintToCarbonCreditAuction_bucketNotFinalized_shouldRevert(uint256 bucketId) public {
        vm.assume(bucketId < 10_000_000);
        vm.warp(block.timestamp + ONE_WEEK * bucketId);
        //buckets finalize 2 weeks after they start, not 1 week, so this should always revert
        vm.expectRevert(IMinerPool.BucketNotFinalized.selector);
        minerPoolAndGCA.handleMintToCarbonCreditAuction(bucketId);
    }

    function test_v2_guarded_withdrawFromBucket_SingleAddressShouldRecoverAllGlow() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](1);
        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdg);
        uint256 totalGlwWeight;
        uint256 totalusdcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalusdcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                usdcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);
        uint256 bucketId = 0;

        {
            uint256 totalNewGCC = 101 * 1e15;
            issueReport({
                gcaToSubmitAs: SIMON,
                bucket: bucketId,
                totalNewGCC: totalNewGCC,
                totalGlwRewardsWeight: totalGlwWeight,
                totalGRCRewardsWeight: totalusdcWeight,
                randomMerkleRoot: root
            });
        }

        vm.warp(block.timestamp + (ONE_WEEK * 2));

        vm.startPrank(defaultAddressInWithdraw);
        uint256 glwWeightForAddress = 100;
        uint256 usdcWeightForAddress = 200;

        (bytes32[] memory proof, bool[] memory flags) = createClaimLeafProof(claimLeaves, payoutTokens, claimLeaves[0]);

        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: bucketId,
            glwWeight: glwWeightForAddress,
            usdcWeight: usdcWeightForAddress,
            proof: proof,
            flags: flags,
            tokens: payoutTokens,
            index: 0,
            claimFromInflation: true
        });

        //Should have gotten all the glow rewards
        assertEq(glow.balanceOf((defaultAddressInWithdraw)), 175_000 ether);

        vm.stopPrank();
    }

    modifier setStageForWithdrawRevertTests() {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](1);
        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdg);
        uint256 totalGlwWeight;
        uint256 totalusdcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalusdcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                usdcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);
        uint256 bucketId = 0;
        uint256 totalNewGCC = 101 * 1e15;
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: bucketId,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalusdcWeight,
            randomMerkleRoot: root
        });

        _;
    }

    function test_v2_guarded_withdrawFromBucket_BucketNotFinalizedShouldRevert()
        public
        setStageForWithdrawRevertTests
    {
        vm.startPrank(defaultAddressInWithdraw);
        uint256 glwWeightForAddress = 100;
        uint256 usdcWeightForAddress = 200;
        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdg);
        bytes32[] memory arbitraryProof = new bytes32[](1);
        bool[] memory flags = new bool[](1);

        vm.expectRevert(IMinerPool.BucketNotFinalized.selector);
        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: 0,
            glwWeight: glwWeightForAddress,
            usdcWeight: usdcWeightForAddress,
            proof: arbitraryProof,
            flags: flags,
            tokens: payoutTokens,
            index: 0,
            claimFromInflation: true
        });
    }

    function test_v2_guarded_withdrawFromBucket_badProof_shouldRevert() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdg);
        uint256 totalGlwWeight;
        uint256 totalusdcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalusdcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                usdcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);
        uint256 bucketId = 0;
        {
            uint256 totalNewGCC = 101 * 1e15;
            issueReport({
                gcaToSubmitAs: SIMON,
                bucket: bucketId,
                totalNewGCC: totalNewGCC,
                totalGlwRewardsWeight: totalGlwWeight,
                totalGRCRewardsWeight: totalusdcWeight,
                randomMerkleRoot: root
            });
        }

        vm.warp(block.timestamp + (ONE_WEEK * 2));

        vm.startPrank(defaultAddressInWithdraw);
        uint256 glwWeightForAddress = 100;
        uint256 usdcWeightForAddress = 200;
        // minerPoolAndGCA.claimRewardFromBucket(bucketId, glwWeight, usdcWeight, proof, packedIndex, user, grcTokens, claimFromInflation);

        //Create the bad proof array
        bytes32[] memory badProof = new bytes32[](3);
        //put a random value
        badProof[0] = bytes32(uint256(10));
        bool[] memory flags = new bool[](1);
        vm.expectRevert(IMinerPool.InvalidUserProof.selector);
        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: bucketId,
            glwWeight: glwWeightForAddress,
            usdcWeight: usdcWeightForAddress,
            proof: badProof,
            flags: flags,
            tokens: payoutTokens,
            index: 0,
            claimFromInflation: true
        });
    }

    function test_v2_guarded_ClaimingShouldSetBitmap() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdg);
        uint256 totalGlwWeight;
        uint256 totalusdcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalusdcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                usdcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);
        {
            uint256 totalNewGCC = 101 * 1e15;
            issueReport({
                gcaToSubmitAs: SIMON,
                bucket: 0,
                totalNewGCC: totalNewGCC,
                totalGlwRewardsWeight: totalGlwWeight,
                totalGRCRewardsWeight: totalusdcWeight,
                randomMerkleRoot: root
            });

            vm.warp(block.timestamp + ONE_WEEK);
            issueReport({
                gcaToSubmitAs: SIMON,
                bucket: 1,
                totalNewGCC: totalNewGCC,
                totalGlwRewardsWeight: totalGlwWeight,
                totalGRCRewardsWeight: totalusdcWeight,
                randomMerkleRoot: root
            });

            vm.warp(block.timestamp + ONE_WEEK);
        }

        vm.startPrank(defaultAddressInWithdraw);
        uint256 glwWeightForAddress = 100;
        uint256 usdcWeightForAddress = 200;
        // minerPoolAndGCA.claimRewardFromBucket(bucketId, glwWeight, usdcWeight, proof, packedIndex, user, grcTokens, claimFromInflation);

        (bytes32[] memory proof, bool[] memory flags) = createClaimLeafProof(claimLeaves, payoutTokens, claimLeaves[0]);
        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: 0,
            glwWeight: glwWeightForAddress,
            usdcWeight: usdcWeightForAddress,
            proof: proof,
            flags: flags,
            tokens: payoutTokens,
            index: 0,
            claimFromInflation: true
        });

        uint256 bitmap = minerPoolAndGCA.getUserBitmapForBucket(0, (defaultAddressInWithdraw));
        assertTrue(bitmap == 1);

        vm.warp(block.timestamp + ONE_WEEK);
        (proof, flags) = createClaimLeafProof(claimLeaves, payoutTokens, claimLeaves[0]);
        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: 1,
            glwWeight: glwWeightForAddress,
            usdcWeight: usdcWeightForAddress,
            proof: proof,
            flags: flags,
            tokens: payoutTokens,
            index: 0,
            claimFromInflation: true
        });

        bitmap = minerPoolAndGCA.getUserBitmapForBucket(1, (defaultAddressInWithdraw));
        assertTrue(bitmap == 0x3);
        vm.stopPrank();
    }

    function test_v2_guarded_withdrawTwice_ShouldRevert() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdg);
        uint256 totalGlwWeight;
        uint256 totalusdcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalusdcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                usdcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);
        uint256 bucketId = 0;
        {
            uint256 totalNewGCC = 101 * 1e15;
            issueReport({
                gcaToSubmitAs: SIMON,
                bucket: bucketId,
                totalNewGCC: totalNewGCC,
                totalGlwRewardsWeight: totalGlwWeight,
                totalGRCRewardsWeight: totalusdcWeight,
                randomMerkleRoot: root
            });
        }
        vm.warp(block.timestamp + (ONE_WEEK * 2));

        vm.startPrank(defaultAddressInWithdraw);
        uint256 glwWeightForAddress = 100;
        uint256 usdcWeightForAddress = 200;
        // minerPoolAndGCA.claimRewardFromBucket(bucketId, glwWeight, usdcWeight, proof, packedIndex, user, grcTokens, claimFromInflation);
        (bytes32[] memory proof, bool[] memory flags) = createClaimLeafProof(claimLeaves, payoutTokens, claimLeaves[0]);

        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: bucketId,
            glwWeight: glwWeightForAddress,
            usdcWeight: usdcWeightForAddress,
            proof: proof,
            flags: flags,
            tokens: payoutTokens,
            index: 0,
            claimFromInflation: true
        });

        vm.expectRevert(IMinerPool.UserAlreadyClaimed.selector);
        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: 0,
            glwWeight: glwWeightForAddress,
            usdcWeight: usdcWeightForAddress,
            proof: proof,
            flags: flags,
            tokens: payoutTokens,
            index: 0,
            claimFromInflation: true
        });

        vm.stopPrank();
    }

    // //************************************************************* */
    // //****************  DELAYING BUCKET TESTS   *************** */
    // //************************************************************* */

    // /**
    //  * @notice This test is to ensure that the delay bucket bitmap is correctly set
    //  * @dev buckets that have been delayed should return true
    //  * @dev buckets that have not been delayed should return false
    //  * forge-config: default.invariant.runs = 5
    //  * forge-config: default.invariant.depth = 100
    //  */
    function invariant_delayBucketBitmapShouldCorrectlyAffectBuckets() public {
        uint256[] memory ids = bucketDelayHandler.delayedBucketIds();
        unchecked {
            for (uint256 i; i < ids.length; ++i) {
                assertTrue(minerPoolAndGCA.hasBucketBeenDelayed({_slashNonce: 0, bucketId: ids[i]}));
            }
        }
        ids = bucketDelayHandler.nonDelayedBucketIds();
        unchecked {
            for (uint256 i; i < ids.length; ++i) {
                assertFalse(minerPoolAndGCA.hasBucketBeenDelayed({_slashNonce: 0, bucketId: ids[i]}));
            }
        }
    }

    function test_v2_guarded_bucketDelay_NotFinishedWithSubmission_shouldRevert() public {
        vm.startPrank(SIMON);
        vm.expectRevert(IGCA.CannotDelayOrResubmitBucketWhereSubmissionsAreStillOpenOrNotYetOpen.selector);
        minerPoolAndGCA.delayBucketFinalization(0);
        vm.stopPrank();
    }

    function test_v2_guarded_delayBucketFinalization_shouldComplete() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdg);

        uint256 totalGlwWeight;
        uint256 totalusdcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalusdcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                usdcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);
        uint256 bucketId = 0;
        {
            uint256 totalNewGCC = 101 * 1e15;
            issueReport({
                gcaToSubmitAs: SIMON,
                bucket: bucketId,
                totalNewGCC: totalNewGCC,
                totalGlwRewardsWeight: totalGlwWeight,
                totalGRCRewardsWeight: totalusdcWeight,
                randomMerkleRoot: root
            });
        }
        vm.startPrank(SIMON);
        //simon is a council member in the `setUp` function
        uint256 finalizationTimestampBefore = minerPoolAndGCA.bucket(bucketId).finalizationTimestamp;

        vm.warp(block.timestamp + 1 weeks);
        minerPoolAndGCA.delayBucketFinalization(0);
        uint256 finalizationTimestampAfter = minerPoolAndGCA.bucket(bucketId).finalizationTimestamp;

        assertEq(finalizationTimestampBefore + (604800 * 13), finalizationTimestampAfter);
        checkBucketAndReport({
            bucketId: bucketId,
            reportIndex: 0,
            expectedNonce: 0,
            expectedReportsLength: 1,
            expectedLastUpdatedNonce: 0,
            expectedReportTotalNewGCC: 101 * 1e15,
            expectedReportTotalGLWRewardsWeight: totalGlwWeight,
            expectedReportTotalGRCRewardsWeight: totalusdcWeight,
            expectedMerkleRoot: root,
            expectedProposingAgent: SIMON
        });

        vm.stopPrank();
    }

    function test_v2_guarded_delayBucketFinalization_bucketAlreadyFinalized_shouldRevert() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdg);
        uint256 totalGlwWeight;
        uint256 totalusdcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalusdcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                usdcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);
        uint256 bucketId = 0;
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: bucketId,
            totalNewGCC: 101 * 1e15,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalusdcWeight,
            randomMerkleRoot: root
        });

        vm.startPrank(SIMON);
        //simon is a council member in the `setUp` function
        uint256 finalizationTimestampBefore = minerPoolAndGCA.bucket(bucketId).finalizationTimestamp;
        vm.warp(block.timestamp + (604800 * 2));
        vm.expectRevert(IGCA.BucketAlreadyFinalized.selector);
        minerPoolAndGCA.delayBucketFinalization(0);
        vm.stopPrank();
    }

    function test_v2_guarded_delayBucketFinalization_twoDelaysShouldRevert() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdg);
        uint256 totalGlwWeight;
        uint256 totalusdcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalusdcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                usdcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);
        uint256 bucketId = 0;
        uint256 totalNewGCC = 101 * 1e15;
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: bucketId,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalusdcWeight,
            randomMerkleRoot: root
        });

        vm.startPrank(SIMON);
        //simon is a council member in the `setUp` function
        uint256 finalizationTimestampBefore = minerPoolAndGCA.bucket(bucketId).finalizationTimestamp;
        //Log the finalization timestamp before =
        console2.log("finalization timestamp before = ", finalizationTimestampBefore);
        vm.warp(block.timestamp + 1 weeks);
        minerPoolAndGCA.delayBucketFinalization(0);
        uint256 finalizationTimestampAfter = minerPoolAndGCA.bucket(bucketId).finalizationTimestamp;

        assertEq(finalizationTimestampBefore + (604800 * 13), finalizationTimestampAfter);
        checkBucketAndReport({
            bucketId: bucketId,
            reportIndex: 0,
            expectedNonce: 0,
            expectedReportsLength: 1,
            expectedLastUpdatedNonce: 0,
            expectedReportTotalNewGCC: totalNewGCC,
            expectedReportTotalGLWRewardsWeight: totalGlwWeight,
            expectedReportTotalGRCRewardsWeight: totalusdcWeight,
            expectedMerkleRoot: root,
            expectedProposingAgent: SIMON
        });

        assertTrue(minerPoolAndGCA.hasBucketBeenDelayed({_slashNonce: 0, bucketId: 0}));

        vm.expectRevert(IMinerPool.BucketAlreadyDelayed.selector);
        minerPoolAndGCA.delayBucketFinalization(0);

        vm.stopPrank();
    }

    //--------------------------------------------------------------------------------//
    //  Tests for delaying a bucket multiple times
    //--------------------------------------------------------------------------------//

    function test_v2_delayBucketMultipleTimes() public {
        test_v2_guarded_delayBucketFinalization_twoDelaysShouldRevert();
        // Let's increment the slashnonce
        vm.warp(block.timestamp + 30 days);
        assertEq(minerPoolAndGCA.slashNonce(), 0, "Slash nonce should still be zero and not incremented");
        minerPoolAndGCA.incrementSlashNonce();
        // We should be able to delay the bucket again?

        uint256 bucketFinalizationTimestamp = minerPoolAndGCA.bucket(0).finalizationTimestamp;

        // We need to issue another report so that the slash nonce is updated
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdg);
        uint256 totalGlwWeight;
        uint256 totalusdcWeight;

        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalusdcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                usdcWeight: 200 + i
            });
        }

        bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);
        {
            uint256 totalNewGCC = 101 * 1e15;
            issueReport({
                gcaToSubmitAs: SIMON,
                bucket: 0,
                totalNewGCC: totalNewGCC,
                totalGlwRewardsWeight: totalGlwWeight,
                totalGRCRewardsWeight: totalusdcWeight,
                randomMerkleRoot: root
            });
        }
        vm.startPrank(SIMON);

        // vm.warp(minerPoolAndGCA.calculateBucketSubmissionEndTimestamp(0));
        // minerPoolAndGCA.delayBucketFinalization(0);
        // uint256 bucketFinalizationTimestampAfter = minerPoolAndGCA.bucket(0).finalizationTimestamp;
        // //Make sure the finalization timestamp differnce is 13 weeks
        // assertEq(bucketFinalizationTimestamp + (604800 * 13), bucketFinalizationTimestampAfter);

        // //Doing it again should revert

        // vm.expectRevert(IMinerPool.BucketAlreadyDelayed.selector);
        // minerPoolAndGCA.delayBucketFinalization(0);

        // //Some more checks potentially @0xSimbo
        // //TODO:
        // // Make sure that delay can never happen while the submission is open

        vm.stopPrank();
    }

    //--------------------------------------------------------------------------------//

    function test_v2_guarded_delayBucketFinalization_delayingBucketThatNeedsToUpdateSlashNonce_shouldRevert() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdg);
        uint256 totalGlwWeight;
        uint256 totalusdcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalusdcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                usdcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);
        uint256 bucketId = 0;
        uint256 totalNewGCC = 101 * 1e15;
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: bucketId,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalusdcWeight,
            randomMerkleRoot: root
        });

        vm.startPrank(SIMON);
        //simon is a council member in the `setUp` function
        // uint256 finalizationTimestampBefore = minerPoolAndGCA.bucket(bucketId).finalizationTimestamp;
        minerPoolAndGCA.incrementSlashNonce();

        vm.warp(block.timestamp + 3 weeks);
        vm.expectRevert(IGCA.BucketAlreadyFinalized.selector);
        minerPoolAndGCA.delayBucketFinalization(0);

        vm.stopPrank();
    }

    function test_v2_guarded_delayBucketFinalization_callerNotVetoCouncilMember_shouldRevert() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        address[] memory payoutTokens = new address[](1);
        payoutTokens[0] = address(usdg);
        uint256 totalGlwWeight;
        uint256 totalusdcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalusdcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                usdcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves, payoutTokens);
        uint256 bucketId = 0;
        uint256 totalNewGCC = 101 * 1e15;
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: bucketId,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalusdcWeight,
            randomMerkleRoot: root
        });

        vm.startPrank(bidder1);
        vm.expectRevert(IMinerPool.CallerNotVetoCouncilMember.selector);
        minerPoolAndGCA.delayBucketFinalization(0);

        vm.stopPrank();
    }

    // //************************************************************* */
    // //*************  DONATIONS   ************ */
    // //************************************************************* */

    function test_v2_guarded_donateToUSDCMinerRewardsPool() public {
        // usdc.mint(SIMON, donationAmount);
        // usdc.approve(address(minerPoolAndGCA), donationAmount);
        vm.startPrank(SIMON);
        uint256 donationAmount = 1_000_000_000 * 1e6;
        mintUSDG(SIMON, donationAmount);
        usdg.approve(address(minerPoolAndGCA), donationAmount);
        uint256 simonBalanceBefore = usdg.balanceOf(SIMON);
        assertEq(simonBalanceBefore, donationAmount);
        minerPoolAndGCA.donateTokenToMinerRewardsPool(address(usdg), donationAmount);
        {
            uint256 simonBalanceAfter = usdg.balanceOf(SIMON);
            assertEq(simonBalanceAfter, 0);
            assertEq(usdg.balanceOf(address(holdingContract)), donationAmount);
        }
        uint256 amountExpectedInEachBucket = donationAmount / VESTING_PERIODS;
        //Since we are at bucket 0 when we deposit
        unchecked {
            for (uint256 i = minerPoolAndGCA.OFFSET_LEFT(); i < VESTING_PERIODS; ++i) {
                BucketSubmission.WeeklyReward memory reward = minerPoolAndGCA.reward(address(usdg), i);
                uint256 amount = reward.amountInBucket;
                //Rewards vest over VESTING_PERIODS weeks
                assertEq(amount, amountExpectedInEachBucket);
            }
        }
        //Let's also expect bucket 209 to have 0
        uint256 amountInBucket208 = minerPoolAndGCA.reward(address(usdg), 208).amountInBucket;
        assertEq(amountInBucket208, 0);
        vm.stopPrank();
    }

    function test_v2_guarded_donateToUSDCMinerRewardsPoolEarlyLiquidity() public {
        vm.startPrank(earlyLiquidity);
        uint256 donationAmount = 1_000_000_000 * 1e6;
        minerPoolAndGCA.donateTokenToRewardsPoolEarlyLiquidity(address(usdg), donationAmount);
        uint256 amountExpectedInEachBucket = donationAmount / VESTING_PERIODS;
        //Since we are at bucket 0 when we deposit
        unchecked {
            for (uint256 i = minerPoolAndGCA.OFFSET_LEFT(); i < VESTING_PERIODS; ++i) {
                BucketSubmission.WeeklyReward memory reward = minerPoolAndGCA.reward(address(usdg), i);
                uint256 amount = reward.amountInBucket;
                //Rewards vest over VESTING_PERIODS weeks
                assertEq(amount, amountExpectedInEachBucket);
            }
        }
        //Let's also expect bucket 209 to have 0
        uint256 amountInBucket208 = minerPoolAndGCA.reward(address(usdg), 208).amountInBucket;
        assertEq(amountInBucket208, 0);
        vm.stopPrank();
    }

    function test_v2_guarded_donateToUSDCMinerRewardsPoolEarlyLiquidity_callerNotEarlyLiquidity_shouldRevert() public {
        vm.startPrank(SIMON);
        uint256 amount = 10000;
        vm.expectRevert(IMinerPool.CallerNotEarlyLiquidity.selector);
        minerPoolAndGCA.donateTokenToRewardsPoolEarlyLiquidity(address(usdg), amount);
    }

    function test_v2_increment_slashNonce_shouldAllowForResubmissions_if_bucketDelayed() public {
        //Currently in week 0
        //
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 101 * 1e15,
            totalGlwRewardsWeight: 105 * 1e15,
            totalGRCRewardsWeight: 101 * 1e15,
            randomMerkleRoot: keccak256("random but different")
        });

        //Delay it
        vm.warp(block.timestamp + 1 weeks);
        //Delay the bucket
        vm.startPrank(SIMON);
        minerPoolAndGCA.delayBucketFinalization(0);
        vm.stopPrank();

        //If we warp 10 weeks , (enough for governance to act,)
        //We should be able to resubmit after
        vm.warp(block.timestamp + 10 weeks);
        //We should be able to resubmit if the slash nonce is incremented
        minerPoolAndGCA.incrementSlashNonce();

        //I should have 2 weeks to resubmit
        vm.warp(block.timestamp + 2 weeks - 1);
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: 22 * 1e15,
            totalGlwRewardsWeight: 22 * 1e15,
            totalGRCRewardsWeight: 22 * 1e15,
            randomMerkleRoot: keccak256("random 2 different")
        });
    }

    //------------------------ HELPERS -----------------------------
    function donateToken(address from, address token, uint256 amount) internal {
        vm.startPrank(from);
        MockUSDC(token).mint(from, amount);
        MockUSDC(token).approve(address(minerPoolAndGCA), amount);
        minerPoolAndGCA.donateTokenToMinerRewardsPool(token, amount);
        vm.stopPrank();
    }

    function logBucketTracker(BucketSubmission.BucketTracker memory bucketTracker) internal {
        console.log("----------------------------");
        console.log("last updated bucket id ", bucketTracker.lastUpdatedBucket);
        console.log("first added bucket id ", bucketTracker.firstAddedBucketId);
        console.log("max bucket = %s", bucketTracker.maxBucketId);
        console.log("----------------------------");
    }

    function logWeeklyReward(BucketSubmission.WeeklyReward memory reward) internal {
        console.log("----------------------------");
        console.log("amount in bucket ", reward.amountInBucket);
        console.log("amount to deduct ", reward.amountToDeduct);
        console.log("inherited from last week ", reward.inheritedFromLastWeek);
        console.log("----------------------------");
    }

    function _getAddressArray(uint256 numAddresses, uint256 addressOffset) private pure returns (address[] memory) {
        address[] memory addresses = new address[](numAddresses);
        for (uint256 i = 0; i < numAddresses; ++i) {
            addresses[i] = address(uint160(addressOffset + i));
        }
        return addresses;
    }

    function _containsElement(address[] memory arr, address element) private pure returns (bool) {
        for (uint256 i; i < arr.length; ++i) {
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

    function createClaimLeafRoot(ClaimLeaf[] memory leaves, address[] memory payoutTokens) internal returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](leaves.length + 1);
        for (uint256 i; i < leaves.length; ++i) {
            hashes[i] = _hashClaimLeaf(leaves[i]);
        }

        //This is the tokens leaf prrefix
        hashes[leaves.length] = _hashPayoutTokens(payoutTokens);

        string[] memory inputs = new string[](4);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = "./test/MinerPoolAndGCA/CreateMerkleRoot.ts";
        inputs[3] = string(abi.encodePacked("--leaves=", stringifyBytes32Array(hashes)));

        bytes memory res = vm.ffi(inputs);
        bytes32 root = abi.decode(res, (bytes32));
        return root;
    }

    function _hashPayoutTokens(address[] memory payoutTokens) internal pure returns (bytes32) {
        return keccak256(
            bytes.concat(
                keccak256(
                    abi.encodePacked(
                        bytes32(0x5a2b68280ef3658be6bd388ec714543fc8d9df8f00d7ab7ab3249e364ebfa76d), payoutTokens
                    )
                )
            )
        );
    }

    function createClaimLeafProof(ClaimLeaf[] memory leaves, address[] memory payoutTokens, ClaimLeaf memory targetLeaf)
        internal
        returns (bytes32[] memory, bool[] memory)
    {
        bytes32[] memory hashes = new bytes32[](leaves.length + 1);
        for (uint256 i; i < leaves.length; ++i) {
            hashes[i] = _hashClaimLeaf(leaves[i]);
        }

        //This is the tokens leaf prrefix
        hashes[leaves.length] = _hashPayoutTokens(payoutTokens);
        string[] memory inputs = new string[](5);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = "./test/MinerPoolAndGCA/GetMerkleMultiProof.ts";
        inputs[3] = string(abi.encodePacked("--leaves=", stringifyBytes32Array(hashes)));

        bytes32 targetLeafB = _hashClaimLeaf(targetLeaf);

        string memory targetLeavesString = string(
            abi.encodePacked(
                Strings.toHexString(uint256(targetLeafB), 32),
                ",",
                Strings.toHexString(uint256(hashes[leaves.length]), 32)
            )
        );

        inputs[4] = string(abi.encodePacked("--targetLeaves=", targetLeavesString));

        bytes memory res = vm.ffi(inputs);
        (bytes32[] memory proof, bool[] memory flags) = abi.decode(res, (bytes32[], bool[]));
        return (proof, flags);
    }

    function _hashClaimLeaf(ClaimLeaf memory leaf) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encodePacked(leaf.payoutWallet, leaf.glwWeight, leaf.usdcWeight))));
    }

    function createTokenProof(ClaimLeaf[] memory leaves, address[] memory payoutTokens)
        internal
        returns (bytes32[] memory)
    {
        bytes32[] memory hashes = new bytes32[](leaves.length + 1);
        for (uint256 i; i < leaves.length; ++i) {
            hashes[i] = keccak256(abi.encodePacked(leaves[i].payoutWallet, leaves[i].glwWeight, leaves[i].usdcWeight));
        }

        //This is the tokens leaf prrefix
        hashes[leaves.length] = keccak256(
            abi.encodePacked(bytes32(0x5a2b68280ef3658be6bd388ec714543fc8d9df8f00d7ab7ab3249e364ebfa76d), payoutTokens)
        );

        string[] memory inputs = new string[](5);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = "./test/MinerPoolAndGCA/GetMerkleProof.ts";
        inputs[3] = string(abi.encodePacked("--leaves=", stringifyBytes32Array(hashes)));
        bytes32 targetLeaf = hashes[leaves.length];
        inputs[4] = string(abi.encodePacked("--targetLeaf=", Strings.toHexString(uint256(targetLeaf), 32)));

        bytes memory res = vm.ffi(inputs);
        bytes32[] memory proof = abi.decode(res, (bytes32[]));
        return proof;
    }

    function _createAccount(uint256 privateKey, uint256 amount)
        internal
        returns (address addr, uint256 signerPrivateKey)
    {
        addr = vm.addr(privateKey);
        vm.deal(addr, amount);
        signerPrivateKey = privateKey;
        return (addr, signerPrivateKey);
    }

    function _signDigest(uint256 signerPrivateKey, bytes32 digestHash) internal pure returns (bytes memory signature) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digestHash);
        signature = abi.encodePacked(r, s, v);
    }

    function addrToUint(address a) internal pure returns (uint256 addr) {
        addr = uint256(uint160(a));
    }

    // function signClaimFromBucketDigest(
    //     uint256 pk,
    //     uint256 bucketId,
    //     uint256 glwWeight,
    //     uint256 usdcWeight,
    //     uint256 index,
    //     address[] memory grcTokens,
    //     bool claimFromInflation
    // ) internal view returns (bytes memory) {
    //     bytes32 hash = minerPoolAndGCA.createClaimRewardFromBucketDigest({
    //         bucketId: bucketId,
    //         glwWeight: glwWeight,
    //         usdcWeight: usdcWeight,
    //         index: index,
    //         claimFromInflation: claimFromInflation
    //     });
    //     console.log("hash from tests  =", uint256(hash));

    //     return _signDigest(pk, hash);
    // }

    function mintUSDG(address user, uint256 amount) public {
        // vm.startPrank(user);
        usdc.mint(user, amount);
        usdc.approve(address(usdg), amount);
        usdg.swap(user, amount);
        // vm.stopPrank();
    }

    function sortTargetLeavesArray(bytes32[] memory targetLeaves) internal pure {
        if (targetLeaves.length != 2) {
            revert("targetLeaves array must have 2 elements");
        }
        if (targetLeaves[0] > targetLeaves[1]) {
            bytes32 temp = targetLeaves[0];
            targetLeaves[0] = targetLeaves[1];
            targetLeaves[1] = temp;
        }
    }
}
