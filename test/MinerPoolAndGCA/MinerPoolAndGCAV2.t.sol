// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import "@/testing/GuardedLaunch/TestGCC.GuardedLaunch.sol";
import "forge-std/console.sol";
import {IGCA} from "@/interfaces/IGCA.sol";
import {MockGCA} from "@/MinerPoolAndGCA/mock/MockGCA.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Governance} from "@/Governance.sol";
import {CarbonCreditDescendingPriceAuction} from "@/CarbonCreditDescendingPriceAuction.sol";
import "forge-std/StdUtils.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
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

        vm.warp(block.timestamp + (ONE_WEEK * 2));

        vm.startPrank(defaultAddressInWithdraw);

        vm.stopPrank();

        address[] memory gcasToSlash = new address[](1);
        gcasToSlash[0] = OTHER_GCA;
        address[] memory newGCAs = new address[](1);
        newGCAs[0] = SIMON;
        uint256 ts = block.timestamp;
        bytes32 hash = keccak256(abi.encode(gcasToSlash, newGCAs, ts));
        minerPoolAndGCA.pushRequirementsHashMock(hash);
        minerPoolAndGCA.incrementSlashNonce();
        minerPoolAndGCA.executeAgainstHash(gcasToSlash, newGCAs, ts);

        assert(minerPoolAndGCA.isBucketFinalized(bucketId));
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

            assert(bucket.originalNonce == 0);
            assert(bucket.lastUpdatedNonce == 0);
            assert(bucket.reports.length == 2);

            vm.warp(block.timestamp + (ONE_WEEK * 2));

            vm.startPrank(defaultAddressInWithdraw);

            vm.stopPrank();

            address[] memory gcasToSlash = new address[](1);
            gcasToSlash[0] = OTHER_GCA;
            address[] memory newGCAs = new address[](1);
            newGCAs[0] = SIMON;
            uint256 ts = block.timestamp;
            bytes32 hash = keccak256(abi.encode(gcasToSlash, newGCAs, ts));
            minerPoolAndGCA.pushRequirementsHashMock(hash);
            minerPoolAndGCA.incrementSlashNonce();
            minerPoolAndGCA.executeAgainstHash(gcasToSlash, newGCAs, ts);

            // {
            // vm.expectRevert(BUCKET_OUT_OF_BOUNDS_SIG);
            // minerPoolAndGCA.claimRewardFromBucket({
            //     bucketId: bucketId,
            //     glwWeight: 100,
            //     usdcWeight: 200,
            //     proof: createClaimLeafProof(claimLeaves, claimLeaves[0]),
            //     index: 0,
            //     user: (defaultAddressInWithdraw),
            //     claimFromInflation: true,
            //     signature: bytes("")
            // });

            // }

            issueReport({
                gcaToSubmitAs: SIMON,
                bucket: bucketId,
                totalNewGCC: totalNewGCC,
                totalGlwRewardsWeight: totalGlwWeight,
                totalGRCRewardsWeight: totalusdcWeight,
                randomMerkleRoot: root
            });

            bucket = minerPoolAndGCA.bucket(bucketId);
            assert(bucket.originalNonce == 0);
            assert(bucket.lastUpdatedNonce == 1);
            assert(bucket.reports.length == 1);
        }
        vm.startPrank(defaultAddressInWithdraw);
        vm.warp(block.timestamp + (ONE_WEEK * 4));
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
        bytes32 hash = keccak256(abi.encode(gcasToSlash, newGCAs, ts));
        minerPoolAndGCA.pushRequirementsHashMock(hash);
        minerPoolAndGCA.incrementSlashNonce();
        minerPoolAndGCA.executeAgainstHash(gcasToSlash, newGCAs, ts);

        //Warp past the original expiration
        vm.warp(block.timestamp + 21);
        //It should not be finalized since the slash nonce does not match
        //and the bucket has not been reinstated.
        assert(!minerPoolAndGCA.isBucketFinalized(bucketId));
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

    function test_v2_guarded_delayBucketFinalization_bucketNotInitialized_shouldRevert() public {
        vm.startPrank(SIMON);
        vm.expectRevert(IMinerPool.CannotDelayEmptyBucket.selector);
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

        assertTrue(minerPoolAndGCA.hasBucketBeenDelayed(0));

        vm.expectRevert(IMinerPool.BucketAlreadyDelayed.selector);
        minerPoolAndGCA.delayBucketFinalization(0);

        vm.stopPrank();
    }

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
        uint256 finalizationTimestampBefore = minerPoolAndGCA.bucket(bucketId).finalizationTimestamp;
        minerPoolAndGCA.incrementSlashNonce();
        vm.expectRevert(IMinerPool.CannotDelayBucketThatNeedsToUpdateSlashNonce.selector);
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
