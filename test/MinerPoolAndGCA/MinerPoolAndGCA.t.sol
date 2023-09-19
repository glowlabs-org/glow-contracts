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
import {MockMinerPoolAndGCA} from "@/MinerPoolAndGCA/mock/MockMinerPoolAndGCA.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";
import {IMinerPool} from "@/interfaces/IMinerPool.sol";

/*
TODO: 
1. Add tests for also claiming GRC tokens
2. Add tests for claiming multiple GRC tokens.
3. Add test for claiming glw and grc at same time
*/
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
    address carbonCreditAuction = address(0x11);
    address defaultAddressInWithdraw = address(0x555);

    //--------  CONSTANTS ---------//
    uint256 constant ONE_WEEK = 7 * uint256(1 days);

    function setUp() public {
        //Make sure we don't start at 0
        vm.warp(10);
        usdc = new MockUSDC();
        glow = new TestGLOW(earlyLiquidity,vestingContract);
        address[] memory temp = new address[](0);
        minerPoolAndGCA =
        new MockMinerPoolAndGCA(temp,address(glow),governance,keccak256("requirementsHash"),earlyLiquidity,address(usdc),carbonCreditAuction,vetoCouncilAddress);
        glow.setContractAddresses(address(minerPoolAndGCA), vetoCouncilAddress, grantsTreasuryAddress);
        // handler = new Handler(address(gca));
        // addGCA(address(handler));
        // bytes4[] memory selectors = new bytes4[](4);
        // selectors[0] = Handler.issueWeeklyReport.selector;
        // selectors[1] = Handler.issueWeeklyReportCurrentBucket.selector;
        // selectors[2] = Handler.incrementSlashNonce.selector;
        // selectors[3] = Handler.warp.selector;

        // FuzzSelector memory fs = FuzzSelector({selectors: selectors, addr: address(handler)});
        // targetSender(SIMON);
        // targetSender(OTHER_GCA);
        // targetSender(OTHER_GCA_2);
        // targetSender(OTHER_GCA_3);
        // targetSender(OTHER_GCA_4);
        // targetContract(address(handler));
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
        bool expectedReinstated,
        uint256 expectedReportTotalNewGCC,
        uint256 expectedReportTotalGLWRewardsWeight,
        uint256 expectedReportTotalGRCRewardsWeight,
        bytes32 expectedMerkleRoot,
        address expectedProposingAgent
    ) internal {
        IGCA.Bucket memory bucket = minerPoolAndGCA.bucket(bucketId);
        assertEq(bucket.reports.length, expectedReportsLength);
        assertEq(bucket.nonce, expectedNonce);
        assertEq(bucket.reinstated, expectedReinstated);
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

    function test_CreateClaimLeafProof() public {
        ClaimLeaf[] memory leaves = new ClaimLeaf[](5);
        for (uint256 i; i < leaves.length; ++i) {
            leaves[i] = ClaimLeaf({payoutWallet: address(uint160(0x555 + i)), glwWeight: 100 + i, grcWeight: 200 + i});
        }

        ClaimLeaf memory targetLeaf =
            ClaimLeaf({payoutWallet: address(uint160(0x555 + 3)), glwWeight: 103, grcWeight: 203});
        bytes32 root = createClaimLeafRoot(leaves);
        bytes32[] memory proof = createClaimLeafProof(leaves, targetLeaf);
        bool validProof = MerkleProofLib.verify(
            proof,
            root,
            keccak256(abi.encodePacked(targetLeaf.payoutWallet, targetLeaf.glwWeight, targetLeaf.grcWeight))
        );
        assertTrue(validProof);
    }

    function test_FFI_MerkleRoot() public {
        address[] memory arr = new address[](2);
        arr[0] = defaultAddressInWithdraw;
        arr[1] = address(0x777);
        bytes32[] memory hashes = new bytes32[](arr.length);
        for (uint256 i; i < arr.length; ++i) {
            hashes[i] = keccak256(abi.encodePacked(bytes32(uint256(uint160(arr[i])))));
        }
        string[] memory inputs = new string[](4);

        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = "./test/MinerPoolAndGCA/CreateMerkleRoot.ts";
        inputs[3] = string(abi.encodePacked("--leaves=", stringifyBytes32Array(hashes)));

        bytes memory res = vm.ffi(inputs);

        bytes32 root = abi.decode(res, (bytes32));
        assertEq(root, bytes32(0x2a1f8d700503a793decdfdc50d092eda9ec782510eeab6159a68366bbdf8f203));
    }

    function test_FFI_getMerkleProof() public {
        address[] memory arr = new address[](2);
        arr[0] = defaultAddressInWithdraw;
        arr[1] = address(0x777);
        bytes32[] memory hashes = new bytes32[](arr.length);
        for (uint256 i; i < arr.length; ++i) {
            hashes[i] = keccak256(abi.encodePacked(bytes32(uint256(uint160(arr[i])))));
        }
        bytes32 root = 0x2a1f8d700503a793decdfdc50d092eda9ec782510eeab6159a68366bbdf8f203;
        string[] memory inputs = new string[](5);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = "./test/MinerPoolAndGCA/GetMerkleProof.ts";
        inputs[3] = string(abi.encodePacked("--leaves=", stringifyBytes32Array(hashes)));
        inputs[4] = string(abi.encodePacked("--targetLeaf=", Strings.toHexString(uint256(hashes[1]), 32)));

        bytes memory res = vm.ffi(inputs);

        bytes32[] memory proof = abi.decode(res, (bytes32[]));
        bool validProof = MerkleProofLib.verify(proof, root, hashes[1]);
        assertTrue(validProof);
    }

    //------------WITHDRAWALS----------------//
    function test_withdrawFromBucket() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        uint256 totalGlwWeight;
        uint256 totalGrcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalGrcWeight += 200 + i;
            claimLeaves[i] =
                ClaimLeaf({payoutWallet: address(uint160(0x555 + i)), glwWeight: 100 + i, grcWeight: 200 + i});
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
        // minerPoolAndGCA.claimRewardMultipleRootsOneBucket(bucketId, glwWeight, grcWeight, proof, packedIndex, user, grcTokens, claimFromInflation);
        address[] memory grcTokens = new address[](1);
        minerPoolAndGCA.claimRewardMultipleRootsOneBucket({
            bucketId: bucketId,
            glwWeight: glwWeightForAddress,
            grcWeight: grcWeightForAddress,
            proof: createClaimLeafProof(claimLeaves, claimLeaves[0]),
            index: 0,
            user: defaultAddressInWithdraw,
            grcTokens: grcTokens,
            claimFromInflation: true
        });

        //Should have gotten all the glow rewards
        assertEq(glow.balanceOf(defaultAddressInWithdraw), 175_000 ether * glwWeightForAddress / totalGlwWeight);

        vm.stopPrank();
    }

    function test_withdrawFromBucket_SingleAddressShouldRecoverAllGlow() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](1);
        uint256 totalGlwWeight;
        uint256 totalGrcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalGrcWeight += 200 + i;
            claimLeaves[i] =
                ClaimLeaf({payoutWallet: address(uint160(0x555 + i)), glwWeight: 100 + i, grcWeight: 200 + i});
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
        // minerPoolAndGCA.claimRewardMultipleRootsOneBucket(bucketId, glwWeight, grcWeight, proof, packedIndex, user, grcTokens, claimFromInflation);
        address[] memory grcTokens = new address[](1);
        minerPoolAndGCA.claimRewardMultipleRootsOneBucket({
            bucketId: bucketId,
            glwWeight: glwWeightForAddress,
            grcWeight: grcWeightForAddress,
            proof: createClaimLeafProof(claimLeaves, claimLeaves[0]),
            index: 0,
            user: defaultAddressInWithdraw,
            grcTokens: grcTokens,
            claimFromInflation: true
        });

        //Should have gotten all the glow rewards
        assertEq(glow.balanceOf(defaultAddressInWithdraw), 175_000 ether);

        vm.stopPrank();
    }

    modifier setStageForWithdrawRevertTests() {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](1);
        uint256 totalGlwWeight;
        uint256 totalGrcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalGrcWeight += 200 + i;
            claimLeaves[i] =
                ClaimLeaf({payoutWallet: address(uint160(0x555 + i)), glwWeight: 100 + i, grcWeight: 200 + i});
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
        // minerPoolAndGCA.claimRewardMultipleRootsOneBucket(bucketId, glwWeight, grcWeight, proof, packedIndex, user, grcTokens, claimFromInflation);
        address[] memory grcTokens = new address[](1);
        bytes32[] memory arbitraryProof = new bytes32[](1);
        grcTokens[0] = address(usdc);
        minerPoolAndGCA.claimRewardMultipleRootsOneBucket({
            bucketId: 0,
            glwWeight: glwWeightForAddress,
            grcWeight: grcWeightForAddress,
            proof: arbitraryProof,
            index: 0,
            user: defaultAddressInWithdraw,
            grcTokens: grcTokens,
            claimFromInflation: true
        });
    }

    function test_withdrawFromBucket_badProof_shouldRevert() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        uint256 totalGlwWeight;
        uint256 totalGrcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalGrcWeight += 200 + i;
            claimLeaves[i] =
                ClaimLeaf({payoutWallet: address(uint160(0x555 + i)), glwWeight: 100 + i, grcWeight: 200 + i});
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
        // minerPoolAndGCA.claimRewardMultipleRootsOneBucket(bucketId, glwWeight, grcWeight, proof, packedIndex, user, grcTokens, claimFromInflation);
        address[] memory grcTokens = new address[](1);
        //Create the bad proof array
        bytes32[] memory badProof = new bytes32[](3);
        //put a random value
        badProof[0] = bytes32(uint256(10));
        vm.expectRevert(IMinerPool.InvalidProof.selector);
        minerPoolAndGCA.claimRewardMultipleRootsOneBucket({
            bucketId: bucketId,
            glwWeight: glwWeightForAddress,
            grcWeight: grcWeightForAddress,
            proof: badProof,
            index: 0,
            user: defaultAddressInWithdraw,
            grcTokens: grcTokens,
            claimFromInflation: true
        });
    }

    function test_ClaimingShouldSetBitmap() public {
        ClaimLeaf[] memory claimLeaves = new ClaimLeaf[](5);
        uint256 totalGlwWeight;
        uint256 totalGrcWeight;
        for (uint256 i; i < claimLeaves.length; ++i) {
            totalGlwWeight += 100 + i;
            totalGrcWeight += 200 + i;
            claimLeaves[i] =
                ClaimLeaf({payoutWallet: address(uint160(0x555 + i)), glwWeight: 100 + i, grcWeight: 200 + i});
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
        // minerPoolAndGCA.claimRewardMultipleRootsOneBucket(bucketId, glwWeight, grcWeight, proof, packedIndex, user, grcTokens, claimFromInflation);
        address[] memory grcTokens = new address[](1);
        grcTokens[0] = address(usdc);

        minerPoolAndGCA.claimRewardMultipleRootsOneBucket({
            bucketId: 0,
            glwWeight: glwWeightForAddress,
            grcWeight: grcWeightForAddress,
            proof: createClaimLeafProof(claimLeaves, claimLeaves[0]),
            index: 0,
            user: defaultAddressInWithdraw,
            grcTokens: grcTokens,
            claimFromInflation: true
        });

        uint256 bitmap = minerPoolAndGCA.getUserBitmapForBucket(0, defaultAddressInWithdraw);
        assertTrue(bitmap == 1);

        vm.warp(block.timestamp + ONE_WEEK);
        // vm.expectRevert(IMinerPool.UserAlreadyClaimed.selector);
        minerPoolAndGCA.claimRewardMultipleRootsOneBucket({
            bucketId: 1,
            glwWeight: glwWeightForAddress,
            grcWeight: grcWeightForAddress,
            proof: createClaimLeafProof(claimLeaves, claimLeaves[0]),
            index: 0,
            user: defaultAddressInWithdraw,
            grcTokens: grcTokens,
            claimFromInflation: true
        });

        bitmap = minerPoolAndGCA.getUserBitmapForBucket(1, defaultAddressInWithdraw);
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
            claimLeaves[i] =
                ClaimLeaf({payoutWallet: address(uint160(0x555 + i)), glwWeight: 100 + i, grcWeight: 200 + i});
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
        // minerPoolAndGCA.claimRewardMultipleRootsOneBucket(bucketId, glwWeight, grcWeight, proof, packedIndex, user, grcTokens, claimFromInflation);
        address[] memory grcTokens = new address[](1);
        minerPoolAndGCA.claimRewardMultipleRootsOneBucket({
            bucketId: bucketId,
            glwWeight: glwWeightForAddress,
            grcWeight: grcWeightForAddress,
            proof: createClaimLeafProof(claimLeaves, claimLeaves[0]),
            index: 0,
            user: defaultAddressInWithdraw,
            grcTokens: grcTokens,
            claimFromInflation: true
        });

        vm.expectRevert(IMinerPool.UserAlreadyClaimed.selector);
        grcTokens[0] = address(usdc);
        minerPoolAndGCA.claimRewardMultipleRootsOneBucket({
            bucketId: 0,
            glwWeight: glwWeightForAddress,
            grcWeight: grcWeightForAddress,
            proof: createClaimLeafProof(claimLeaves, claimLeaves[0]),
            index: 0,
            user: defaultAddressInWithdraw,
            grcTokens: grcTokens,
            claimFromInflation: true
        });
        vm.stopPrank();
    }

    //------------------------ HELPERS -----------------------------
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
}
