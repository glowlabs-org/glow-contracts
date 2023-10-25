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
import {CarbonCreditDutchAuction} from "@/CarbonCreditDutchAuction.sol";
import "forge-std/StdUtils.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {TestGLOW} from "@/testing/TestGLOW.sol";
import {Handler} from "./Handlers/Handler.GCA.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MerkleProofLib} from "@solady/utils/MerkleProofLib.sol";
import {MockMinerPoolAndGCA} from "@/MinerPoolAndGCA/mock/MockMinerPoolAndGCA.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";
import {IMinerPool} from "@/interfaces/IMinerPool.sol";
import {BucketSubmission} from "@/MinerPoolAndGCA/BucketSubmission.sol";
import {VetoCouncil} from "@/VetoCouncil.sol";
import {BucketDelayHandler} from "./Handlers/BucketDelayHandler.sol";
import {Holding, ClaimHoldingArgs, IHoldingContract, HoldingContract} from "@/HoldingContract.sol";

struct ClaimLeaf {
    address payoutWallet;
    uint256 glwWeight;
    uint256 grcWeight;
}

contract MinerPoolAndGCATest is Test {
    //--------  CONTRACTS ---------//
    MockMinerPoolAndGCA minerPoolAndGCA;
    TestGLOW glow;
    MockUSDC usdc;
    MockUSDC grc2;
    BucketDelayHandler bucketDelayHandler;
    HoldingContract holdingContract;
    TestGCC gcc;

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

    //--------  CONSTANTS ---------//
    uint256 constant ONE_WEEK = 7 * uint256(1 days);

    function setUp() public {
        //Make sure we don't start at 0
        (SIMON, SIMON_PRIVATE_KEY) = _createAccount(9999, type(uint256).max);
        vm.warp(10);
        usdc = new MockUSDC();
        (defaultAddressInWithdraw, defaultAddressPrivateKey) = _createAccount(2313141231, type(uint256).max);
        glow = new TestGLOW(earlyLiquidity,vestingContract);
        bucketDelayHandler = new BucketDelayHandler();
        address[] memory temp = new address[](0);
        address[] memory startingAgents = new address[](2);
        startingAgents[0] = address(SIMON);
        startingAgents[1] = address(bucketDelayHandler);
        vetoCouncil = new VetoCouncil(governance, address(glow),startingAgents);
        vetoCouncilAddress = address(vetoCouncil);
        holdingContract = new HoldingContract(vetoCouncilAddress);
        minerPoolAndGCA =
        new MockMinerPoolAndGCA(temp,address(glow),governance,keccak256("requirementsHash"),earlyLiquidity,address(usdc),vetoCouncilAddress,address(holdingContract));
        gcc = new TestGCC(address(minerPoolAndGCA),governance,address(glow));
        minerPoolAndGCA.setGCC(address(gcc));
        addGCA(address(bucketDelayHandler));
        glow.setContractAddresses(address(minerPoolAndGCA), vetoCouncilAddress, grantsTreasuryAddress);
        grc2 = new MockUSDC();
        bucketDelayHandler.setMinerPool(address(minerPoolAndGCA));
        // handler = new Handler(address(gca));
        // addGCA(address(handler));
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = BucketDelayHandler.delayBucket.selector;
        selectors[1] = BucketDelayHandler.preventBucketDelay.selector;

        FuzzSelector memory fs = FuzzSelector({selectors: selectors, addr: address(bucketDelayHandler)});

        // targetSender(SIMON);
        // targetSender(OTHER_GCA);
        // targetSender(OTHER_GCA_2);
        // targetSender(OTHER_GCA_3);
        // targetSender(OTHER_GCA_4);
        targetContract(address(bucketDelayHandler));
    }

    //-------- ISSUING REPORTS ---------//
    function addGCA(address newGCA) public {
        address[] memory allGCAs = minerPoolAndGCA.allGcas();
        address[] memory temp = new address[](allGCAs.length+1);
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

        minerPoolAndGCA.issueWeeklyReport(
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
            str = string(abi.encodePacked(str, "\"", Strings.toHexString(uint256(arr[i]), 32), "\""));
            if (i != arr.length - 1) {
                str = string(abi.encodePacked(str, ","));
            }
        }
        str = string(abi.encodePacked(str, "]"));
    }

    function test_setGCC() public {
        //Make sure we don't start at 0
        (SIMON, SIMON_PRIVATE_KEY) = _createAccount(9999, type(uint256).max);
        vm.warp(10);
        usdc = new MockUSDC();
        (defaultAddressInWithdraw, defaultAddressPrivateKey) = _createAccount(2313141231, type(uint256).max);
        glow = new TestGLOW(earlyLiquidity,vestingContract);
        bucketDelayHandler = new BucketDelayHandler();
        address[] memory temp = new address[](0);
        address[] memory startingAgents = new address[](2);
        startingAgents[0] = address(SIMON);
        startingAgents[1] = address(bucketDelayHandler);
        vetoCouncil = new VetoCouncil(governance, address(glow),startingAgents);
        vetoCouncilAddress = address(vetoCouncil);
        holdingContract = new HoldingContract(vetoCouncilAddress);
        minerPoolAndGCA =
        new MockMinerPoolAndGCA(temp,address(glow),governance,keccak256("requirementsHash"),earlyLiquidity,address(usdc),vetoCouncilAddress,address(holdingContract));
        gcc = new TestGCC(address(minerPoolAndGCA),governance,address(glow));

        minerPoolAndGCA.setGCC(address(gcc));
        vm.expectRevert(IGCA.GCCAlreadySet.selector);
        minerPoolAndGCA.setGCC(address(gcc));
    }

    function test_checkWeightsForOverflow() public {
        uint256 bucketId = 0;
        uint256 totalGlwWeight = type(uint64).max;
        uint256 totalGrcWeight = type(uint64).max;
        uint256 glwWeight = type(uint64).max;
        uint256 grcWeight = type(uint64).max;

        minerPoolAndGCA.checkWeightsForOverflow(bucketId, totalGlwWeight, totalGrcWeight, glwWeight, grcWeight);

        //Any overflow to totalGlwWeight should revert
        vm.expectRevert(stdError.arithmeticError);
        minerPoolAndGCA.checkWeightsForOverflow(bucketId, 1, totalGrcWeight, glwWeight, grcWeight);
        vm.expectRevert(stdError.arithmeticError);
        minerPoolAndGCA.checkWeightsForOverflow(bucketId, totalGlwWeight, 1, glwWeight, grcWeight);

        // //Any overflow to totalGlwWeight should revert
        vm.expectRevert(stdError.arithmeticError);
        minerPoolAndGCA.checkWeightsForOverflow(bucketId, type(uint256).max, totalGrcWeight, glwWeight, grcWeight);
        vm.expectRevert(stdError.arithmeticError);
        minerPoolAndGCA.checkWeightsForOverflow(bucketId, totalGlwWeight, type(uint256).max, glwWeight, grcWeight);
    }

    function test_checkWeightsForOverflow_gtThanSubmittedWeights() public {
        uint256 bucketId = 0;
        uint256 totalGlwWeight = 5000;
        uint256 totalGrcWeight = 5000;
        uint256 glwWeight = 5001;
        uint256 grcWeight = 5000;

        //glw weight should overflow since it's > totalGlwWeight
        vm.expectRevert(IMinerPool.GlowWeightOverflow.selector);
        minerPoolAndGCA.checkWeightsForOverflow(bucketId, totalGlwWeight, totalGrcWeight, glwWeight, grcWeight);

        ++grcWeight; //grc weight will now be greater than tha allowed
        --glwWeight; // and glw weight will be ok
        //so the grc weight should revert
        vm.expectRevert(IMinerPool.GRCWeightOverflow.selector);
        minerPoolAndGCA.checkWeightsForOverflow(bucketId, totalGlwWeight, totalGrcWeight, glwWeight, grcWeight);
    }

    function test_CreateClaimLeafProof() public {
        ClaimLeaf[] memory leaves = new ClaimLeaf[](5);
        for (uint256 i; i < leaves.length; ++i) {
            leaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                grcWeight: 200 + i
            });
        }

        ClaimLeaf memory targetLeaf = ClaimLeaf({
            payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + 3)),
            glwWeight: 103,
            grcWeight: 203
        });
        bytes32 root = createClaimLeafRoot(leaves);
        bytes32[] memory proof = createClaimLeafProof(leaves, targetLeaf);
        bool validProof = MerkleProofLib.verify(
            proof,
            root,
            keccak256(abi.encodePacked(targetLeaf.payoutWallet, targetLeaf.glwWeight, targetLeaf.grcWeight))
        );
        assertTrue(validProof);
    }

    // ------------WITHDRAWALS----------------//
    // TODO: Add sending to carbon credit auction

    function test_withdrawFromBucket() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        uint256 totalGlwWeight;
        uint256 totalGrcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalGrcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                grcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves);
        uint256 bucketId = 0;
        uint256 totalNewGCC = 101 * 1e15;

        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: bucketId,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalGrcWeight,
            randomMerkleRoot: root
        });

        vm.warp(block.timestamp + (ONE_WEEK * 2));

        vm.startPrank(defaultAddressInWithdraw);
        uint256 glwWeightForAddress = 100;
        uint256 grcWeightForAddress = 200;
        // minerPoolAndGCA.claimRewardFromBucket(bucketId, glwWeight, grcWeight, proof, packedIndex, user, grcTokens, claimFromInflation);
        address[] memory grcTokens = new address[](1);
        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: bucketId,
            glwWeight: glwWeightForAddress,
            grcWeight: grcWeightForAddress,
            proof: createClaimLeafProof(claimLeaves, claimLeaves[0]),
            index: 0,
            user: (defaultAddressInWithdraw),
            grcTokens: grcTokens,
            claimFromInflation: true,
            signature: bytes("")
        });

        //Should have gotten all the glow rewards
        assertEq(glow.balanceOf((defaultAddressInWithdraw)), 175_000 ether * glwWeightForAddress / totalGlwWeight);

        vm.stopPrank();
    }

    function testFuzz_currentWeekInternal_makeCoverageHappy(uint256 warpSeconds) public {
        vm.assume(warpSeconds < 500_000 weeks);
        vm.warp(block.timestamp + warpSeconds);
        uint256 currentWeek = minerPoolAndGCA.currentWeekInternal();
        assertEq(minerPoolAndGCA.currentBucket(), currentWeek);
    }

    function test_domainSeperatorV4_makeCoverageHappy() public {
        assert(minerPoolAndGCA.domainSeperatorOZ() == minerPoolAndGCA.domainSeperatorV4MainInternal());
    }

    function test_withdrawFromBucket_shouldAddToHoldings() public {
        vm.startPrank(SIMON);
        uint256 amountGRCToDonate = 1_000_000 * 1e6;
        uint256 expectedAmountInEachBucket = amountGRCToDonate / 192;
        usdc.mint(SIMON, amountGRCToDonate);
        usdc.approve(address(minerPoolAndGCA), amountGRCToDonate);
        minerPoolAndGCA.donateToGRCMinerRewardsPool(address(usdc), amountGRCToDonate);
        vm.stopPrank();

        //Go to the 16th bucket since that's where the grc tokens start unlocking
        vm.warp(block.timestamp + ONE_WEEK * 16);
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        uint256 totalGlwWeight;
        uint256 totalGrcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalGrcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                grcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves);
        uint256 bucketId = 16;
        uint256 totalNewGCC = 101 * 1e15;

        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: bucketId,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalGrcWeight,
            randomMerkleRoot: root
        });

        vm.warp(block.timestamp + (ONE_WEEK * 2));

        vm.startPrank(defaultAddressInWithdraw);
        uint256 glwWeightForAddress = 100;
        uint256 grcWeightForAddress = 200;
        // minerPoolAndGCA.claimRewardFromBucket(bucketId, glwWeight, grcWeight, proof, packedIndex, user, grcTokens, claimFromInflation);
        address[] memory grcTokens = new address[](1);
        grcTokens[0] = address(usdc);
        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: bucketId,
            glwWeight: glwWeightForAddress,
            grcWeight: grcWeightForAddress,
            proof: createClaimLeafProof(claimLeaves, claimLeaves[0]),
            index: 0,
            user: (defaultAddressInWithdraw),
            grcTokens: grcTokens,
            claimFromInflation: true,
            signature: bytes("")
        });

        //Should have gotten all the glow rewards
        assertEq(glow.balanceOf((defaultAddressInWithdraw)), 175_000 ether * glwWeightForAddress / totalGlwWeight);
        assertEq(
            uint256(holdingContract.holdings(defaultAddressInWithdraw, address(usdc)).amount),
            expectedAmountInEachBucket * grcWeightForAddress / totalGrcWeight
        );

        //Revert if it hasn't been a week
        vm.expectRevert(HoldingContract.WithdrawalNotReady.selector);
        holdingContract.claimHoldingSingleton(defaultAddressInWithdraw, address(usdc));

        //Warp one week
        vm.warp(block.timestamp + ONE_WEEK);
        //Should be able to claim now
        holdingContract.claimHoldingSingleton(defaultAddressInWithdraw, address(usdc));
        assertEq(
            usdc.balanceOf(defaultAddressInWithdraw), expectedAmountInEachBucket * grcWeightForAddress / totalGrcWeight
        );
        vm.stopPrank();
    }

    function test_withdrawFromBucket_senderNotUser_shouldNotClaimGRCTokens() public {
        {
            vm.startPrank(SIMON);
            uint256 amountGRCToDonate = 1_000_000 * 1e6;
            uint256 expectedAmountInEachBucket = amountGRCToDonate / 192;
            usdc.mint(SIMON, amountGRCToDonate);
            usdc.approve(address(minerPoolAndGCA), amountGRCToDonate);
            minerPoolAndGCA.donateToGRCMinerRewardsPool(address(usdc), amountGRCToDonate);
            vm.stopPrank();
        }

        //Go to the 16th bucket since that's where the grc tokens start unlocking
        vm.warp(block.timestamp + ONE_WEEK * 16);
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        uint256 totalGlwWeight;
        uint256 totalGrcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalGrcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                grcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves);
        uint256 bucketId = 16;
        uint256 totalNewGCC = 101 * 1e15;

        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: bucketId,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalGrcWeight,
            randomMerkleRoot: root
        });

        vm.warp(block.timestamp + (ONE_WEEK * 2));

        address notDefaultAddressInWithdraw = address(0x3982391273891273891279);
        vm.startPrank(notDefaultAddressInWithdraw);
        // minerPoolAndGCA.claimRewardFromBucket(bucketId, glwWeight, grcWeight, proof, packedIndex, user, grcTokens, claimFromInflation);
        address[] memory grcTokens = new address[](1);
        grcTokens[0] = address(usdc);
        vm.expectRevert(IMinerPool.SignatureDoesNotMatchUser.selector);
        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: bucketId,
            glwWeight: 100,
            grcWeight: 200,
            proof: createClaimLeafProof(claimLeaves, claimLeaves[0]),
            index: 0,
            user: (defaultAddressInWithdraw),
            grcTokens: grcTokens,
            claimFromInflation: true,
            signature: bytes("")
        });

        vm.stopPrank();
    }

    function test_withdrawFromBucket_senderNotUser_validSig_shouldClaimGRCTokens() public {
        {
            vm.startPrank(SIMON);
            uint256 amountGRCToDonate = 1_000_000 * 1e6;
            uint256 expectedAmountInEachBucket = amountGRCToDonate / 192;
            usdc.mint(SIMON, amountGRCToDonate);
            usdc.approve(address(minerPoolAndGCA), amountGRCToDonate);
            minerPoolAndGCA.donateToGRCMinerRewardsPool(address(usdc), amountGRCToDonate);
            vm.stopPrank();
        }

        //Go to the 16th bucket since that's where the grc tokens start unlocking
        vm.warp(block.timestamp + ONE_WEEK * 16);
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        uint256 totalGlwWeight;
        uint256 totalGrcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalGrcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                grcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves);
        uint256 bucketId = 16;
        uint256 totalNewGCC = 101 * 1e15;

        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: bucketId,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalGrcWeight,
            randomMerkleRoot: root
        });

        vm.warp(block.timestamp + (ONE_WEEK * 2));

        address notDefaultAddressInWithdraw = address(0x3982391273891273891279);
        vm.startPrank(notDefaultAddressInWithdraw);
        // minerPoolAndGCA.claimRewardFromBucket(bucketId, glwWeight, grcWeight, proof, packedIndex, user, grcTokens, claimFromInflation);
        address[] memory grcTokens = new address[](1);
        grcTokens[0] = address(usdc);
        bytes memory sig = signClaimFromBucketDigest(defaultAddressPrivateKey, bucketId, 100, 200, 0, grcTokens, true);
        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: bucketId,
            glwWeight: 100,
            grcWeight: 200,
            proof: createClaimLeafProof(claimLeaves, claimLeaves[0]),
            index: 0,
            user: (defaultAddressInWithdraw),
            grcTokens: grcTokens,
            claimFromInflation: true,
            signature: sig
        });

        vm.stopPrank();
    }

    function test_withdrawFromBucket_shouldClaimMultipleGRCTokens() public {
        vm.startPrank(governance);
        //Add a second grc token
        minerPoolAndGCA.editReserveCurrencies(address(0), address(grc2));
        vm.stopPrank();
        vm.startPrank(SIMON);

        //init amounts to donate
        uint256 amountGRCToDonate = 1_000_000 * 1e6;
        uint256 amountGRC2_toDonate = 1_000 * 1e6;

        //mint the amounts and approve them
        usdc.mint(SIMON, amountGRCToDonate);
        usdc.approve(address(minerPoolAndGCA), amountGRCToDonate);
        grc2.mint(SIMON, amountGRC2_toDonate);
        grc2.approve(address(minerPoolAndGCA), amountGRC2_toDonate);

        //Execute donation
        minerPoolAndGCA.donateToGRCMinerRewardsPool(address(usdc), amountGRCToDonate);

        //Execute donation
        minerPoolAndGCA.donateToGRCMinerRewardsPool(address(grc2), amountGRC2_toDonate);
        vm.stopPrank();

        {
            //make sure we sent all the tokens we could
            assertEq(grc2.balanceOf(SIMON), 0);
            assertEq(usdc.balanceOf(SIMON), 0);
        }

        //Go to the 16th bucket since that's where the grc tokens start unlocking
        vm.warp(block.timestamp + ONE_WEEK * 16);

        //Init 5 claim leaves
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        uint256 totalGlwWeight;
        uint256 totalGrcWeight;

        //Loop through the claim leaves and assign them values
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalGrcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                grcWeight: 200 + i
            });
        }

        //Create the root using ffi
        bytes32 root = createClaimLeafRoot(claimLeaves);
        uint256 bucketId = 16;
        uint256 totalNewGCC = 101 * 1e15;

        //Issue the report
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: bucketId,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalGrcWeight,
            randomMerkleRoot: root
        });

        //Warp forward 2 weeks so the claim opens up for the bucket
        vm.warp(block.timestamp + (ONE_WEEK * 2));

        //Start the prank as the user
        vm.startPrank(defaultAddressInWithdraw);

        //The user has the below weights
        uint256 glwWeightForAddress = 100;
        uint256 grcWeightForAddress = 200;

        //Add both tokens to the grcTokens array
        address[] memory grcTokens = new address[](2);
        grcTokens[0] = address(usdc);
        grcTokens[1] = address(grc2);
        //Initiate a withdraw for both tokens from the bucket
        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: bucketId,
            glwWeight: glwWeightForAddress,
            grcWeight: grcWeightForAddress,
            proof: createClaimLeafProof(claimLeaves, claimLeaves[0]),
            index: 0,
            user: (defaultAddressInWithdraw),
            grcTokens: grcTokens,
            claimFromInflation: true,
            signature: bytes("")
        });

        //Should have gotten all the glow rewards
        assertEq(glow.balanceOf((defaultAddressInWithdraw)), 175_000 ether * glwWeightForAddress / totalGlwWeight);
        assertEq(
            holdingContract.holdings(defaultAddressInWithdraw, address(usdc)).amount,
            amountGRCToDonate / 192 * grcWeightForAddress / totalGrcWeight
        );
        assertEq(
            holdingContract.holdings(defaultAddressInWithdraw, address(grc2)).amount,
            amountGRC2_toDonate / 192 * grcWeightForAddress / totalGrcWeight
        );

        //expect both to revert when trying to claim from holding contract
        vm.expectRevert(HoldingContract.WithdrawalNotReady.selector);
        holdingContract.claimHoldingSingleton(defaultAddressInWithdraw, address(usdc));
        vm.expectRevert(HoldingContract.WithdrawalNotReady.selector);
        holdingContract.claimHoldingSingleton(defaultAddressInWithdraw, address(grc2));

        //Fast forward 1 week
        vm.warp(block.timestamp + ONE_WEEK);
        //expect both claims to work
        holdingContract.claimHoldingSingleton(defaultAddressInWithdraw, address(usdc));
        holdingContract.claimHoldingSingleton(defaultAddressInWithdraw, address(grc2));

        //Ensure the balances align
        assertEq(
            usdc.balanceOf(defaultAddressInWithdraw), amountGRCToDonate / 192 * grcWeightForAddress / totalGrcWeight
        );
        assertEq(
            grc2.balanceOf(defaultAddressInWithdraw), amountGRC2_toDonate / 192 * grcWeightForAddress / totalGrcWeight
        );

        vm.stopPrank();
    }

    function test_withdrawFromBucket_SingleAddressShouldRecoverAllGlow() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](1);
        uint256 totalGlwWeight;
        uint256 totalGrcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalGrcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                grcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves);
        uint256 bucketId = 0;
        uint256 totalNewGCC = 101 * 1e15;
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: bucketId,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalGrcWeight,
            randomMerkleRoot: root
        });

        vm.warp(block.timestamp + (ONE_WEEK * 2));

        vm.startPrank(defaultAddressInWithdraw);
        uint256 glwWeightForAddress = 100;
        uint256 grcWeightForAddress = 200;
        // minerPoolAndGCA.claimRewardFromBucket(bucketId, glwWeight, grcWeight, proof, packedIndex, user, grcTokens, claimFromInflation);
        address[] memory grcTokens = new address[](1);
        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: bucketId,
            glwWeight: glwWeightForAddress,
            grcWeight: grcWeightForAddress,
            proof: createClaimLeafProof(claimLeaves, claimLeaves[0]),
            index: 0,
            user: (defaultAddressInWithdraw),
            grcTokens: grcTokens,
            claimFromInflation: true,
            signature: bytes("")
        });

        //Should have gotten all the glow rewards
        assertEq(glow.balanceOf((defaultAddressInWithdraw)), 175_000 ether);

        vm.stopPrank();
    }

    modifier setStageForWithdrawRevertTests() {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](1);
        uint256 totalGlwWeight;
        uint256 totalGrcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalGrcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                grcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves);
        uint256 bucketId = 0;
        uint256 totalNewGCC = 101 * 1e15;
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: bucketId,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalGrcWeight,
            randomMerkleRoot: root
        });

        _;
    }

    function test_withdrawFromBucket_BucketNotFinalizedShouldRevert() public setStageForWithdrawRevertTests {
        vm.startPrank(defaultAddressInWithdraw);
        vm.expectRevert(IMinerPool.BucketNotFinalized.selector);
        uint256 glwWeightForAddress = 100;
        uint256 grcWeightForAddress = 200;
        // minerPoolAndGCA.claimRewardFromBucket(bucketId, glwWeight, grcWeight, proof, packedIndex, user, grcTokens, claimFromInflation);
        address[] memory grcTokens = new address[](1);
        bytes32[] memory arbitraryProof = new bytes32[](1);
        grcTokens[0] = address(usdc);
        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: 0,
            glwWeight: glwWeightForAddress,
            grcWeight: grcWeightForAddress,
            proof: arbitraryProof,
            index: 0,
            user: (defaultAddressInWithdraw),
            grcTokens: grcTokens,
            claimFromInflation: true,
            signature: bytes("")
        });
    }

    function test_withdrawFromBucket_badProof_shouldRevert() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        uint256 totalGlwWeight;
        uint256 totalGrcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalGrcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                grcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves);
        uint256 bucketId = 0;
        uint256 totalNewGCC = 101 * 1e15;
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: bucketId,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalGrcWeight,
            randomMerkleRoot: root
        });

        vm.warp(block.timestamp + (ONE_WEEK * 2));

        vm.startPrank(defaultAddressInWithdraw);
        uint256 glwWeightForAddress = 100;
        uint256 grcWeightForAddress = 200;
        // minerPoolAndGCA.claimRewardFromBucket(bucketId, glwWeight, grcWeight, proof, packedIndex, user, grcTokens, claimFromInflation);
        address[] memory grcTokens = new address[](1);
        //Create the bad proof array
        bytes32[] memory badProof = new bytes32[](3);
        //put a random value
        badProof[0] = bytes32(uint256(10));
        vm.expectRevert(IMinerPool.InvalidProof.selector);
        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: bucketId,
            glwWeight: glwWeightForAddress,
            grcWeight: grcWeightForAddress,
            proof: badProof,
            index: 0,
            user: (defaultAddressInWithdraw),
            grcTokens: grcTokens,
            claimFromInflation: true,
            signature: bytes("")
        });
    }

    function test_ClaimingShouldSetBitmap() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        uint256 totalGlwWeight;
        uint256 totalGrcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalGrcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                grcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves);
        uint256 totalNewGCC = 101 * 1e15;
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 0,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalGrcWeight,
            randomMerkleRoot: root
        });

        vm.warp(block.timestamp + ONE_WEEK);
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: 1,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalGrcWeight,
            randomMerkleRoot: root
        });

        vm.warp(block.timestamp + ONE_WEEK);

        vm.startPrank(defaultAddressInWithdraw);
        uint256 glwWeightForAddress = 100;
        uint256 grcWeightForAddress = 200;
        // minerPoolAndGCA.claimRewardFromBucket(bucketId, glwWeight, grcWeight, proof, packedIndex, user, grcTokens, claimFromInflation);
        address[] memory grcTokens = new address[](1);
        grcTokens[0] = address(usdc);

        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: 0,
            glwWeight: glwWeightForAddress,
            grcWeight: grcWeightForAddress,
            proof: createClaimLeafProof(claimLeaves, claimLeaves[0]),
            index: 0,
            user: (defaultAddressInWithdraw),
            grcTokens: grcTokens,
            claimFromInflation: true,
            signature: bytes("")
        });

        uint256 bitmap = minerPoolAndGCA.getUserBitmapForBucket(0, (defaultAddressInWithdraw), grcTokens[0]);
        assertTrue(bitmap == 1);

        vm.warp(block.timestamp + ONE_WEEK);
        // vm.expectRevert(IMinerPool.UserAlreadyClaimed.selector);
        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: 1,
            glwWeight: glwWeightForAddress,
            grcWeight: grcWeightForAddress,
            proof: createClaimLeafProof(claimLeaves, claimLeaves[0]),
            index: 0,
            user: (defaultAddressInWithdraw),
            grcTokens: grcTokens,
            claimFromInflation: true,
            signature: bytes("")
        });

        bitmap = minerPoolAndGCA.getUserBitmapForBucket(1, (defaultAddressInWithdraw), grcTokens[0]);
        assertTrue(bitmap == 0x3);
        vm.stopPrank();
    }

    function test_withdrawTwice_ShouldRevert() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        uint256 totalGlwWeight;
        uint256 totalGrcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalGrcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                grcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves);
        uint256 bucketId = 0;
        uint256 totalNewGCC = 101 * 1e15;
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: bucketId,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalGrcWeight,
            randomMerkleRoot: root
        });

        vm.warp(block.timestamp + (ONE_WEEK * 2));

        vm.startPrank(defaultAddressInWithdraw);
        uint256 glwWeightForAddress = 100;
        uint256 grcWeightForAddress = 200;
        // minerPoolAndGCA.claimRewardFromBucket(bucketId, glwWeight, grcWeight, proof, packedIndex, user, grcTokens, claimFromInflation);
        address[] memory grcTokens = new address[](1);
        grcTokens[0] = address(usdc);

        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: bucketId,
            glwWeight: glwWeightForAddress,
            grcWeight: grcWeightForAddress,
            proof: createClaimLeafProof(claimLeaves, claimLeaves[0]),
            index: 0,
            user: (defaultAddressInWithdraw),
            grcTokens: grcTokens,
            claimFromInflation: true,
            signature: bytes("")
        });

        vm.expectRevert(IMinerPool.UserAlreadyClaimed.selector);
        minerPoolAndGCA.claimRewardFromBucket({
            bucketId: 0,
            glwWeight: glwWeightForAddress,
            grcWeight: grcWeightForAddress,
            proof: createClaimLeafProof(claimLeaves, claimLeaves[0]),
            index: 0,
            user: (defaultAddressInWithdraw),
            grcTokens: grcTokens,
            claimFromInflation: true,
            signature: bytes("")
        });

        vm.stopPrank();
    }

    //************************************************************* */
    //****************  DELAYING BUCKET TESTS   *************** */
    //************************************************************* */

    /**
     * @notice This test is to ensure that the delay bucket bitmap is correctly set
     * @dev buckets that have been delayed should return true
     * @dev buckets that have not been delayed should return false
     * forge-config: default.invariant.runs = 5
     * forge-config: default.invariant.depth = 100
     */
    function invariant_delayBucketBitmapShouldCorrectlyAffectBuckets() public {
        uint256[] memory ids = bucketDelayHandler.delayedBucketIds();
        unchecked {
            for (uint256 i; i < ids.length; ++i) {
                assertTrue(minerPoolAndGCA.hasBucketBeenDelayed(ids[i]));
            }
        }
        ids = bucketDelayHandler.nonDelayedBucketIds();
        unchecked {
            for (uint256 i; i < ids.length; ++i) {
                assertFalse(minerPoolAndGCA.hasBucketBeenDelayed(ids[i]));
            }
        }
    }

    function test_delayBucketFinalization_bucketNotInitialized_shouldRevert() public {
        vm.expectRevert(IMinerPool.CannotDelayEmptyBucket.selector);
        minerPoolAndGCA.delayBucketFinalization(0);
    }

    function test_delayBucketFinalization_shouldComplete() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        uint256 totalGlwWeight;
        uint256 totalGrcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalGrcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                grcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves);
        uint256 bucketId = 0;
        uint256 totalNewGCC = 101 * 1e15;
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: bucketId,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalGrcWeight,
            randomMerkleRoot: root
        });

        vm.startPrank(SIMON);
        //simon is a council member in the `setUp` function
        uint256 finalizationTimestampBefore = minerPoolAndGCA.bucket(bucketId).finalizationTimestamp;
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
            expectedReportTotalGRCRewardsWeight: totalGrcWeight,
            expectedMerkleRoot: root,
            expectedProposingAgent: SIMON
        });

        vm.stopPrank();
    }

    function test_delayBucketFinalization_bucketAlreadyFinalized_shouldRevert() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        uint256 totalGlwWeight;
        uint256 totalGrcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalGrcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                grcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves);
        uint256 bucketId = 0;
        uint256 totalNewGCC = 101 * 1e15;
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: bucketId,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalGrcWeight,
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

    function test_delayBucketFinalization_twoDelaysShouldRevert() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        uint256 totalGlwWeight;
        uint256 totalGrcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalGrcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                grcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves);
        uint256 bucketId = 0;
        uint256 totalNewGCC = 101 * 1e15;
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: bucketId,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalGrcWeight,
            randomMerkleRoot: root
        });

        vm.startPrank(SIMON);
        //simon is a council member in the `setUp` function
        uint256 finalizationTimestampBefore = minerPoolAndGCA.bucket(bucketId).finalizationTimestamp;
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
            expectedReportTotalGRCRewardsWeight: totalGrcWeight,
            expectedMerkleRoot: root,
            expectedProposingAgent: SIMON
        });

        assertTrue(minerPoolAndGCA.hasBucketBeenDelayed(0));

        vm.expectRevert(IMinerPool.BucketAlreadyDelayed.selector);
        minerPoolAndGCA.delayBucketFinalization(0);

        vm.stopPrank();
    }

    function test_delayBucketFinalization_delayingBucketThatNeedsToUpdateSlashNonce_shouldRevert() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        uint256 totalGlwWeight;
        uint256 totalGrcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalGrcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                grcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves);
        uint256 bucketId = 0;
        uint256 totalNewGCC = 101 * 1e15;
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: bucketId,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalGrcWeight,
            randomMerkleRoot: root
        });

        vm.startPrank(SIMON);
        //simon is a council member in the `setUp` function
        uint256 finalizationTimestampBefore = minerPoolAndGCA.bucket(bucketId).finalizationTimestamp;
        minerPoolAndGCA.incrementSlashNonce();
        vm.expectRevert(IMinerPool.CannotDelayBucketThatNeedsToUpdateSlashNonce.selector);
        minerPoolAndGCA.delayBucketFinalization(0);

        vm.stopPrank();
    }

    function test_delayBucketFinalization_callerNotVetoCouncilMember_shouldRevert() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        uint256 totalGlwWeight;
        uint256 totalGrcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalGrcWeight += 200 + i;
            claimLeaves[i] = ClaimLeaf({
                payoutWallet: address(uint160(addrToUint(defaultAddressInWithdraw) + i)),
                glwWeight: 100 + i,
                grcWeight: 200 + i
            });
        }
        bytes32 root = createClaimLeafRoot(claimLeaves);
        uint256 bucketId = 0;
        uint256 totalNewGCC = 101 * 1e15;
        issueReport({
            gcaToSubmitAs: SIMON,
            bucket: bucketId,
            totalNewGCC: totalNewGCC,
            totalGlwRewardsWeight: totalGlwWeight,
            totalGRCRewardsWeight: totalGrcWeight,
            randomMerkleRoot: root
        });

        vm.startPrank(bidder1);
        vm.expectRevert(IMinerPool.CallerNotVetoCouncilMember.selector);
        minerPoolAndGCA.delayBucketFinalization(0);

        vm.stopPrank();
    }

    //************************************************************* */
    //*************  DONATIONS   ************ */
    //************************************************************* */

    function test_donateToGRCMinerRewardsPool() public {
        vm.startPrank(SIMON);
        uint256 donationAmount = 1_000_000_000 * 1e6;
        usdc.mint(SIMON, donationAmount);
        usdc.approve(address(minerPoolAndGCA), donationAmount);
        uint256 simonBalanceBefore = usdc.balanceOf(SIMON);
        assertEq(simonBalanceBefore, donationAmount);
        minerPoolAndGCA.donateToGRCMinerRewardsPool(address(usdc), donationAmount);
        {
            uint256 simonBalanceAfter = usdc.balanceOf(SIMON);
            assertEq(simonBalanceAfter, 0);
            assertEq(usdc.balanceOf(address(holdingContract)), donationAmount);
        }
        uint256 amountExpectedInEachBucket = donationAmount / 192;
        //Since we are at bucket 0 when we deposit
        unchecked {
            for (uint256 i = 16; i < 208; ++i) {
                BucketSubmission.WeeklyReward memory reward = minerPoolAndGCA.reward(address(usdc), i);
                uint256 amount = reward.amountInBucket;
                //Rewards vest over 192 weeks
                assertEq(amount, amountExpectedInEachBucket);
            }
        }
        //Let's also expect bucket 209 to have 0
        uint256 amountInBucket208 = minerPoolAndGCA.reward(address(usdc), 208).amountInBucket;
        assertEq(amountInBucket208, 0);
        vm.stopPrank();
    }

    function test_donateToGRCMinerRewardsPoolEarlyLiquidity() public {
        vm.startPrank(earlyLiquidity);
        uint256 donationAmount = 1_000_000_000 * 1e6;
        minerPoolAndGCA.donateToGRCMinerRewardsPoolEarlyLiquidity(address(usdc), donationAmount);
        uint256 amountExpectedInEachBucket = donationAmount / 192;
        //Since we are at bucket 0 when we deposit
        unchecked {
            for (uint256 i = 16; i < 208; ++i) {
                BucketSubmission.WeeklyReward memory reward = minerPoolAndGCA.reward(address(usdc), i);
                uint256 amount = reward.amountInBucket;
                //Rewards vest over 192 weeks
                assertEq(amount, amountExpectedInEachBucket);
            }
        }
        //Let's also expect bucket 209 to have 0
        uint256 amountInBucket208 = minerPoolAndGCA.reward(address(usdc), 208).amountInBucket;
        assertEq(amountInBucket208, 0);
        vm.stopPrank();
    }

    function test_donateToGRCMinerRewardsPoolEarlyLiquidity_callerNotEarlyLiquidity_shouldRevert() public {
        vm.startPrank(SIMON);
        uint256 amount = 10000;
        vm.expectRevert(IMinerPool.CallerNotEarlyLiquidity.selector);
        minerPoolAndGCA.donateToGRCMinerRewardsPoolEarlyLiquidity(address(usdc), amount);
    }

    // add invariant to make sure there cna never be more than 3 GRC's
    // at any point in time.
    function test_editReserveCurrencies_swapOldForNew() public {
        vm.startPrank(governance);
        address newRandomGRC = address(0x421928138129381983);
        minerPoolAndGCA.editReserveCurrencies(address(usdc), newRandomGRC);
        BucketSubmission.BucketTracker memory bucketTrackerOld = minerPoolAndGCA.bucketTracker(address(usdc));
        console.logBool(bucketTrackerOld.isGRC);

        assertEq(bucketTrackerOld.isGRC, false);
        BucketSubmission.BucketTracker memory bucketTrackerNew = minerPoolAndGCA.bucketTracker(newRandomGRC);
        assertEq(bucketTrackerNew.isGRC, true);

        assertEq(minerPoolAndGCA.numReserveCurrencies(), 1);
        vm.stopPrank();
    }

    // add invariant to make sure there cna never be more than 3 GRC's
    // at any point in time.
    function test_editReserveCurrencies_shouldBeAbleToGetToZeroGRCs() public {
        vm.startPrank(governance);
        address newRandomGRC = address(0x421928138129381983);
        minerPoolAndGCA.editReserveCurrencies(address(usdc), address(0));
        BucketSubmission.BucketTracker memory bucketTrackerOld = minerPoolAndGCA.bucketTracker(address(usdc));
        assertEq(bucketTrackerOld.isGRC, false);

        assertEq(minerPoolAndGCA.numReserveCurrencies(), 0);
        vm.stopPrank();
    }

    //We need to return if there's an underflow possibility
    //so that governance can keep executing proposals
    function test_editReserveCurrencies_potentialUnderflowShouldNotRevert() public {
        vm.startPrank(governance);
        address newRandomGRC = address(0x421928138129381983);
        minerPoolAndGCA.editReserveCurrencies(address(usdc), address(0));
        BucketSubmission.BucketTracker memory bucketTrackerOld = minerPoolAndGCA.bucketTracker(address(usdc));
        assertEq(bucketTrackerOld.isGRC, false);

        minerPoolAndGCA.editReserveCurrencies(address(usdc), address(0));
        assertEq(minerPoolAndGCA.numReserveCurrencies(), 0);
        vm.stopPrank();
    }

    //We need to return if there's an underflow possibility
    //so that governance can keep executing proposals
    function test_editReserveCurrencies_shouldNeverSurpassThreeReserveCurrencies() public {
        vm.startPrank(governance);
        address newRandomGRC = address(0x421928138129381983);
        minerPoolAndGCA.editReserveCurrencies(address(0), newRandomGRC);
        assertEq(minerPoolAndGCA.numReserveCurrencies(), 2);

        newRandomGRC = address(0x421928138129381984);
        minerPoolAndGCA.editReserveCurrencies(address(0), newRandomGRC);
        assertEq(minerPoolAndGCA.numReserveCurrencies(), 3);

        newRandomGRC = address(0x421928138129381985);
        minerPoolAndGCA.editReserveCurrencies(address(0), newRandomGRC);
        assertEq(minerPoolAndGCA.numReserveCurrencies(), 3);
    }

    function test_editReserveCurrencies_tryReaddingExistingCurrency_shouldReturnFalse() public {
        vm.startPrank(governance);
        bool res = minerPoolAndGCA.editReserveCurrencies(address(usdc), address(usdc));
        assert(!res);
    }

    //Tests to make sure that either both currencies are updated, or none are updated
    function test_editReserveCurrency_addReserveCurrencyGoesThrough_butRemoveReserveCurrencyFails_shouldNotUpdateState()
        public
    {
        vm.startPrank(governance);
        address notAGrc = address(0x1235);
        address grcTryingToPush = address(0x1234);
        //We can't remove a grc that is not already a grc
        bool res = minerPoolAndGCA.editReserveCurrencies(notAGrc, grcTryingToPush);
        BucketSubmission.BucketTracker memory trackerNotGRC = minerPoolAndGCA.bucketTracker(notAGrc);
        // assert(!res);
        trackerNotGRC = minerPoolAndGCA.bucketTracker(notAGrc);
        //Should still be a GRC since the second edit failed
        assert(!trackerNotGRC.isGRC);
        assertEq(minerPoolAndGCA.numReserveCurrencies(), 1);

        BucketSubmission.BucketTracker memory trackerTryingToPush = minerPoolAndGCA.bucketTracker(grcTryingToPush);
        assert(!trackerTryingToPush.isGRC);
    }

    // the general rule for setting grc token is ---.....
    // If it's the first time adding the grc token,
    // then, the first added bucket id becomes current bucket + 16
    // if the bucket has already been added
    // if the current bucket is greater than the max bucket,
    // then we set the first added bucket to current bucket + 16
    // if the current bucket is not greater than the max bucket,
    // then we don't change the struct since it still has periods to vest
    function test_setGRCToken_addingNewTokenForFirstTime_shouldSetFirstBucketIdToCurrentBucketIdPlus16() public {
        vm.warp(block.timestamp + ONE_WEEK * 192);
        uint256 currentBucket = minerPoolAndGCA.currentBucket();
        minerPoolAndGCA.setGRCToken(address(grc2), true, currentBucket);
        BucketSubmission.BucketTracker memory bucketTracker = minerPoolAndGCA.bucketTracker(address(grc2));
        donateToken(SIMON, address(grc2), 2000);
        assertEq(bucketTracker.firstAddedBucketId, currentBucket + 16);
    }

    function test_setGRCToken_readdingToken_beforeAllVestingFinished_shouldNotChangeFirstAddedBucketId() public {
        //Usdc starts out as the default grc
        donateToken(SIMON, address(usdc), 1000);
        vm.warp(block.timestamp + ONE_WEEK * 192);
        //USDC should be vesting until 208, so we should not be able to change the first added bucket id
        uint256 currentBucket = minerPoolAndGCA.currentBucket();
        minerPoolAndGCA.setGRCToken(address(usdc), false, currentBucket);
        BucketSubmission.BucketTracker memory bucketTracker = minerPoolAndGCA.bucketTracker(address(usdc));
        assert(bucketTracker.firstAddedBucketId == 16);
    }

    function test_setGRCToken_readdingExistingCurrency_shouldReturnFalse() public {
        bool res = minerPoolAndGCA.setGRCToken(address(usdc), true, 0);
        assert(!res);
    }

    function test_setGRCToken_removingNonExistingCurrency_shouldReturnFalse() public {
        address notGRC = address(0xdead);
        bool res = minerPoolAndGCA.setGRCToken(address(notGRC), false, 0);
        assert(!res);
    }

    //------------------------ HELPERS -----------------------------
    function donateToken(address from, address token, uint256 amount) internal {
        vm.startPrank(from);
        MockUSDC(token).mint(from, amount);
        MockUSDC(token).approve(address(minerPoolAndGCA), amount);
        minerPoolAndGCA.donateToGRCMinerRewardsPool(token, amount);
        vm.stopPrank();
    }

    function logBucketTracker(BucketSubmission.BucketTracker memory bucketTracker) internal {
        console.log("----------------------------");
        console.log("last updated bucket id ", bucketTracker.lastUpdatedBucket);
        console.log("first added bucket id ", bucketTracker.firstAddedBucketId);
        console.log("max bucket = %s", bucketTracker.maxBucketId);
        console.log("isGRC ", bucketTracker.isGRC);
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

    function createClaimLeafRoot(ClaimLeaf[] memory leaves) internal returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](leaves.length);
        for (uint256 i; i < leaves.length; ++i) {
            hashes[i] = keccak256(abi.encodePacked(leaves[i].payoutWallet, leaves[i].glwWeight, leaves[i].grcWeight));
        }

        string[] memory inputs = new string[](4);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = "./test/MinerPoolAndGCA/CreateMerkleRoot.ts";
        inputs[3] = string(abi.encodePacked("--leaves=", stringifyBytes32Array(hashes)));

        bytes memory res = vm.ffi(inputs);
        bytes32 root = abi.decode(res, (bytes32));
        return root;
    }

    function createClaimLeafProof(ClaimLeaf[] memory leaves, ClaimLeaf memory targetLeaf)
        internal
        returns (bytes32[] memory)
    {
        bytes32[] memory hashes = new bytes32[](leaves.length);
        for (uint256 i; i < leaves.length; ++i) {
            hashes[i] = keccak256(abi.encodePacked(leaves[i].payoutWallet, leaves[i].glwWeight, leaves[i].grcWeight));
        }
        string[] memory inputs = new string[](5);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = "./test/MinerPoolAndGCA/GetMerkleProof.ts";
        inputs[3] = string(abi.encodePacked("--leaves=", stringifyBytes32Array(hashes)));
        bytes32 targetLeaf =
            keccak256(abi.encodePacked(targetLeaf.payoutWallet, targetLeaf.glwWeight, targetLeaf.grcWeight));
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

    function signClaimFromBucketDigest(
        uint256 pk,
        uint256 bucketId,
        uint256 glwWeight,
        uint256 grcWeight,
        uint256 index,
        address[] memory grcTokens,
        bool claimFromInflation
    ) internal view returns (bytes memory) {
        bytes32 hash = minerPoolAndGCA.createClaimRewardFromBucketDigest({
            bucketId: bucketId,
            glwWeight: glwWeight,
            grcWeight: grcWeight,
            index: index,
            grcTokens: grcTokens,
            claimFromInflation: claimFromInflation
        });
        console.log("hash from tests  =", uint256(hash));

        return _signDigest(pk, hash);
    }
}
