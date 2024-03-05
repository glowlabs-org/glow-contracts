// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {GCC} from "@/GCC.sol";
import {TestGLOW} from "@/testing/TestGLOW.sol";
import {Governance} from "@/Governance.sol";
import {GoerliGCC} from "@/testing/Goerli/GoerliGCC.sol";
import {MockUSDC} from "@/testing/MockUSDC.sol";
import {EarlyLiquidity} from "@/EarlyLiquidity.sol";
import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
import {CarbonCreditDescendingPriceAuction} from "@/CarbonCreditDescendingPriceAuction.sol";
import {GoerliMinerPoolAndGCAQuickPeriod} from "@/testing/Goerli/GoerliMinerPoolAndGCA.QuickPeriod.sol";
import {VetoCouncil} from "@/VetoCouncil/VetoCouncil.sol";
import {SafetyDelay} from "@/SafetyDelay.sol";
import {MinerPoolAndGCA} from "@/MinerPoolAndGCA/MinerPoolAndGCA.sol";
import {GrantsTreasury} from "@/GrantsTreasury.sol";
import {BatchCommit} from "@/BatchCommit.sol";
import {USDG} from "@/USDG.sol";
import "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

string constant fileToWriteTo = "deployedContractsGoerli.json";

struct ClaimLeaf {
    address payoutWallet;
    uint256 glwWeight;
    uint256 usdcWeight;
}

struct ClaimObj {
    uint256 bucket;
    uint256 glwWeight;
    uint256 usdcWeight;
    bytes32[] proof;
    uint256 reportIndex;
    address leafAddress;
}

contract DebugCommitReport is Test {
    string mainnetForkUrl = vm.envString("MAINNET_RPC");
    uint256 mainnetFork;
    address gca = (0xB2d687b199ee40e6113CD490455cC81eC325C496);
    MinerPoolAndGCA minerPoolAndGCA = MinerPoolAndGCA(0x6Fa8C7a89b22bf3212392b778905B12f3dBAF5C4);

    function setUp() public {
        mainnetFork = vm.createFork(mainnetForkUrl);
        vm.selectFork(mainnetFork);
    }

    function test_submitReportMainnet() public {
        vm.startPrank(gca);
        // minerPoolAndGCA.submitWeeklyReport(bucketId, totalNewGCC, totalGlwRewardsWeight, totalGRCRewardsWeight, root);
        // minerPoolAndGCA.executeAgainstHash(gcasToSlash, newGCAs, proposalCreationTimestamp);
        address[] memory gcasToSlash = new address[](0);
        address[] memory newGCAs = new address[](1);
        newGCAs[0] = address(gca);
        // minerPoolAndGCA.submitWeeklyReport({
        //     bucketId: minerPoolAndGCA.currentBucket(),
        //     totalNewGCC: 689843857893639930,
        //     totalGlwRewardsWeight: 3067431198,
        //     totalGRCRewardsWeight: 689844,
        //     root: bytes32(0x03367cff4ec5a2ba7da1a41d477056299e7e8ca9a37f825bad1626ada08b8513)
        // });

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = bytes32(0xec0460ee1729da81e9244b2fa8826501575f962e97ec49723bdf293fbc205aac);
        proof[1] = bytes32(0xc5e29470a1a17aa0c1f7d504a78d61ee78fa0a6c87c9054b74c3a5a62fa9b40e);
        vm.stopPrank();

        //warp 3 weeks and let's see if we can claim

        //leaf 0
        // {
        //   address: '0x2e2771032d119fe590FD65061Ad3B366C8e9B7b9',
        //   glowWeight: '18265401042',
        //   usdcWeight: '50770'
        // }
        uint256 glowSum;
        vm.warp(block.timestamp + 604800 * 3);
        uint256 bucketId = 9;
        //setup all these leaves
        ClaimObj[] memory claimObjs = new ClaimObj[](6);
        // proof =
        {
            bytes32[] memory proof0 = new bytes32[](3);
            proof0[0] = bytes32(0x9d505b593053d30ec21f4bac918d5eb72bb9d6ac19dd2f6a7643aece89748a94);
            proof0[1] = bytes32(0x9ab82a138a0a735eaebfe3058ee08f8b600910fa77439f1b0f8770aeacf6b9c5);
            proof0[2] = bytes32(0x29ced4ef9c49bad97e6cd421b500310a7e71758f01c81f38d482b83f37cf54bd);
            claimObjs[0] = ClaimObj({
                bucket: bucketId,
                glwWeight: 182654010,
                usdcWeight: 50770,
                proof: proof0,
                reportIndex: 0,
                leafAddress: 0x2e2771032d119fe590FD65061Ad3B366C8e9B7b9
            });
        }

        {
            bytes32[] memory proof1 = new bytes32[](3);
            proof1[0] = bytes32(0x32c611fbcd5b6687a917f34b43af54833971138293821925b1f24c9a0c699c72);
            proof1[1] = bytes32(0x38c1cd0920d587a2a211cad419791162949a0599c994b3f25e63e2d479e5d3a1);
            proof1[2] = bytes32(0x29ced4ef9c49bad97e6cd421b500310a7e71758f01c81f38d482b83f37cf54bd);

            claimObjs[1] = ClaimObj({
                bucket: bucketId,
                glwWeight: 300241125,
                usdcWeight: 228346,
                proof: proof1,
                reportIndex: 0,
                leafAddress: 0x1f00e91A9e467FfE8038e520c498D371F63dFE56
            });
        }

        {
            bytes32[] memory proof2 = new bytes32[](2);
            proof2[0] = bytes32(0xbab5e440bc2057aa33e9935726bbee9b687da25498c2d7e3156a9b8eedd5016a);
            proof2[1] = bytes32(0x65f2b20022ef78e6c0745e1da28c187eb871b923db29908253bf76228d99089f);

            claimObjs[2] = ClaimObj({
                bucket: bucketId,
                glwWeight: 1407219198,
                usdcWeight: 4319,
                proof: proof2,
                reportIndex: 0,
                leafAddress: 0xCB0695C5e231D04a36feb07841e26D44e6D08c9d
            });
        }

        {
            bytes32[] memory proof3 = new bytes32[](3);
            proof3[0] = bytes32(0x8083dce0d0e91e6f56d686aab2d8c6e55e980fdea9e7d2f9df1d0e8f5cd9bf99);
            proof3[1] = bytes32(0x9ab82a138a0a735eaebfe3058ee08f8b600910fa77439f1b0f8770aeacf6b9c5);
            proof3[2] = bytes32(0x29ced4ef9c49bad97e6cd421b500310a7e71758f01c81f38d482b83f37cf54bd);
            claimObjs[3] = ClaimObj({
                bucket: bucketId,
                glwWeight: 511513151,
                usdcWeight: 156890,
                proof: proof3,
                reportIndex: 0,
                leafAddress: 0x09EfEe2b1fC9105Ff080Ec2d379f21aff697455C
            });
        }

        {
            bytes32[] memory proof4 = new bytes32[](3);
            proof4[0] = bytes32(0x0be5d2197926473431f358d6187da7f4dcca3b155bd94bd0efa1155da0298ce6);
            proof4[1] = bytes32(0x38c1cd0920d587a2a211cad419791162949a0599c994b3f25e63e2d479e5d3a1);
            proof4[2] = bytes32(0x29ced4ef9c49bad97e6cd421b500310a7e71758f01c81f38d482b83f37cf54bd);
            claimObjs[4] = ClaimObj({
                bucket: bucketId,
                glwWeight: 511513151,
                usdcWeight: 184856,
                proof: proof4,
                reportIndex: 0,
                leafAddress: 0x0e9c3c8c10900c899C5681F87114fe0B6Fb2a198
            });
        }
        {
            bytes32[] memory proof5 = new bytes32[](2);
            proof5[0] = bytes32(0xe4d7af23f8cb23d40f525836cbe542da342ce1121d8a45dd53643f14cd766e1a);
            proof5[1] = bytes32(0x65f2b20022ef78e6c0745e1da28c187eb871b923db29908253bf76228d99089f);
            claimObjs[5] = ClaimObj({
                bucket: bucketId,
                glwWeight: 154290563,
                usdcWeight: 64663,
                proof: proof5,
                reportIndex: 0,
                leafAddress: 0x5bC1A82995C73eED31183DAE1b7ce70E70eBF3Cf
            });
        }

        for (uint256 i; i < claimObjs.length; ++i) {
            glowSum += claimForLeaf(claimObjs[i]);
        }
        console.log("glowSum: ", glowSum);

        // [
        //     {
        //         "address": "0x2e2771032d119fe590FD65061Ad3B366C8e9B7b9",
        //         "glowWeight": "182654010",
        //         "usdcWeight": "50770",
        //         "proof": [
        //             "0x9d505b593053d30ec21f4bac918d5eb72bb9d6ac19dd2f6a7643aece89748a94",
        //             "0x9ab82a138a0a735eaebfe3058ee08f8b600910fa77439f1b0f8770aeacf6b9c5",
        //             "0x29ced4ef9c49bad97e6cd421b500310a7e71758f01c81f38d482b83f37cf54bd"
        //         ]
        //     },
        //     {
        //         "address": "0x1f00e91A9e467FfE8038e520c498D371F63dFE56",
        //         "glowWeight": "300241125",
        //         "usdcWeight": "228346",
        //         "proof": [
        //             "0x32c611fbcd5b6687a917f34b43af54833971138293821925b1f24c9a0c699c72",
        //             "0x38c1cd0920d587a2a211cad419791162949a0599c994b3f25e63e2d479e5d3a1",
        //             "0x29ced4ef9c49bad97e6cd421b500310a7e71758f01c81f38d482b83f37cf54bd"
        //         ]
        //     },
        //     {
        //         "address": "0xCB0695C5e231D04a36feb07841e26D44e6D08c9d",
        //         "glowWeight": "1407219198",
        //         "usdcWeight": "4319",
        //         "proof": [
        //             "0xbab5e440bc2057aa33e9935726bbee9b687da25498c2d7e3156a9b8eedd5016a",
        //             "0x65f2b20022ef78e6c0745e1da28c187eb871b923db29908253bf76228d99089f"
        //         ]
        //     },
        //     {
        //         "address": "0x09EfEe2b1fC9105Ff080Ec2d379f21aff697455C",
        //         "glowWeight": "511513151",
        //         "usdcWeight": "156890",
        //         "proof": [
        //             "0x8083dce0d0e91e6f56d686aab2d8c6e55e980fdea9e7d2f9df1d0e8f5cd9bf99",
        //             "0x9ab82a138a0a735eaebfe3058ee08f8b600910fa77439f1b0f8770aeacf6b9c5",
        //             "0x29ced4ef9c49bad97e6cd421b500310a7e71758f01c81f38d482b83f37cf54bd"
        //         ]
        //     },
        //     {
        //         "address": "0x0e9c3c8c10900c899c5681f87114fe0b6fb2a198",
        //         "glowWeight": "511513151",
        //         "usdcWeight": "184856",
        //         "proof": [
        //             "0x0be5d2197926473431f358d6187da7f4dcca3b155bd94bd0efa1155da0298ce6",
        //             "0x38c1cd0920d587a2a211cad419791162949a0599c994b3f25e63e2d479e5d3a1",
        //             "0x29ced4ef9c49bad97e6cd421b500310a7e71758f01c81f38d482b83f37cf54bd"
        //         ]
        //     },
        //     {
        //         "address": "0x5bC1A82995C73eED31183DAE1b7ce70E70eBF3Cf",
        //         "glowWeight": "154290563",
        //         "usdcWeight": "64663",
        //         "proof": [
        //             "0xe4d7af23f8cb23d40f525836cbe542da342ce1121d8a45dd53643f14cd766e1a",
        //             "0x65f2b20022ef78e6c0745e1da28c187eb871b923db29908253bf76228d99089f"
        //         ]
        //     }
        // ]

        // IERC20 glowToken = IERC20(minerPoolAndGCA.GLOW_TOKEN());
        // IERC20 usdg = IERC20(minerPoolAndGCA.USDC());

        // //log glowtoken balance after
        // console.log("glowToken balance after: ", glowToken.balanceOf(leafAddress));
        // console.log("usdg balance after: ", usdg.balanceOf(leafAddress));
    }

    function claimForLeaf(ClaimObj memory obj) public returns (uint256) {
        console.log("claiming for leaf: ", obj.leafAddress);
        uint256 glowBalanceBefore = IERC20(minerPoolAndGCA.GLOW_TOKEN()).balanceOf(obj.leafAddress);
        vm.startPrank(obj.leafAddress);
        minerPoolAndGCA.claimRewardFromBucket(
            obj.bucket, obj.glwWeight, obj.usdcWeight, obj.proof, obj.reportIndex, obj.leafAddress, true, ""
        );
        uint256 glowBalanceAfter = IERC20(minerPoolAndGCA.GLOW_TOKEN()).balanceOf(obj.leafAddress);
        uint256 glowBalanceDiff = glowBalanceAfter - glowBalanceBefore;
        vm.stopPrank();
        return glowBalanceDiff;
    }

    function createClaimLeafRoot(ClaimLeaf[] memory leaves) internal returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](leaves.length);
        for (uint256 i; i < leaves.length; ++i) {
            hashes[i] = keccak256(abi.encodePacked(leaves[i].payoutWallet, leaves[i].glwWeight, leaves[i].usdcWeight));
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
            hashes[i] = keccak256(abi.encodePacked(leaves[i].payoutWallet, leaves[i].glwWeight, leaves[i].usdcWeight));
        }
        string[] memory inputs = new string[](5);
        inputs[0] = "npx";
        inputs[1] = "ts-node";
        inputs[2] = "./test/MinerPoolAndGCA/GetMerkleProof.ts";
        inputs[3] = string(abi.encodePacked("--leaves=", stringifyBytes32Array(hashes)));
        bytes32 targetLeaf =
            keccak256(abi.encodePacked(targetLeaf.payoutWallet, targetLeaf.glwWeight, targetLeaf.usdcWeight));
        inputs[4] = string(abi.encodePacked("--targetLeaf=", Strings.toHexString(uint256(targetLeaf), 32)));

        bytes memory res = vm.ffi(inputs);
        bytes32[] memory proof = abi.decode(res, (bytes32[]));
        return proof;
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
}
