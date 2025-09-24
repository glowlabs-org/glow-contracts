// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {FoundationRewardKernel} from "@/v2/FoundationRewardKernel.sol";
import {CounterfactualHolderFactory} from "@/v2/CounterfactualHolderFactory.sol";
import {CounterfactualHolder} from "src/v2/CounterfactualHolder.sol";
import {Call} from "@/v2/Structs.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MinerPoolAndGCA} from "@/MinerPoolAndGCA/MinerPoolAndGCA.sol";
import {_GENESIS_TIMESTAMP, _BUCKET_DURATION} from "@/Constants/Constants.sol";
import {USDG} from "@/USDG.sol";

contract DebugV2 is Test {
    string mainnetForkUrl = vm.envString("MAINNET_RPC");
    uint256 mainnetFork;
    address me = 0xD509A9480559337e924C764071009D60aaCA623d;
    MinerPoolAndGCA minerPool = MinerPoolAndGCA(0x6Fa8C7a89b22bf3212392b778905B12f3dBAF5C4);
    address gca = 0xB2d687b199ee40e6113CD490455cC81eC325C496;
    address foundationMultisig = makeAddr("foundationMultisig");
    address rejectionMultisig = makeAddr("rejectionMultisig");
    address protocolDepositHolder = makeAddr("protcoolDepositHolder");

    FoundationRewardKernel rewardKernel;
    CounterfactualHolderFactory cfhFactory;
    address constant USDC_SAFE = 0xc5174BBf649a92F9941e981af68AaA14Dd814F85;
    USDG usdg = USDG(0xe010ec500720bE9EF3F82129E7eD2Ee1FB7955F2);
    IERC20 usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address randomUser = makeAddr("randomUser");

    IERC20 glow = IERC20(0xf4fbC617A5733EAAF9af08E1Ab816B103388d8B6);

    function setUp() public {
        mainnetFork = vm.createFork({urlOrAlias: mainnetForkUrl, blockNumber: 23383234});
        vm.selectFork(mainnetFork);
        cfhFactory = new CounterfactualHolderFactory();
        rewardKernel = new FoundationRewardKernel(foundationMultisig, rejectionMultisig, cfhFactory, 2 weeks);
    }

    /*
    "totalGlowInflationRewards": "138687942330602921019391",
    "totalGlowInflationRewardsLeafWeight": "138687942330602887",
    "totalV1UsdgWeight": "1",
    "v1MerkleRoot": "0x838bec1c007c743a3a46a92f21d162c411a47fdbeae65640ccc17207a51fbd29",
    "v2MerkleRoot": "0x6f7d5e8e9d2a8c3bbef76be6a72dc6d8d5e11e47428a69b6ec8ff0d4364cd69d",
    "fullOnchainTokensAndAmountsArray": [
        {
            "amount": "276838997349",
            "asset": "USDG",
            "assetAddress": "0xe010ec500720bE9EF3F82129E7eD2Ee1FB7955F2"
        }
    ],
    */
    function test_v2_mainnet_claim() public {
        //Let's warp to week 96 of the protocol
        vm.warp(_GENESIS_TIMESTAMP + 96 * _BUCKET_DURATION + 1);

        vm.startPrank(gca);

        minerPool.submitWeeklyReport({
            bucketId: 96,
            totalNewGCC: 1,
            totalGlwRewardsWeight: uint256(138687942330602887), //Kind of incorrect
            totalGRCRewardsWeight: 1,
            root: 0x838bec1c007c743a3a46a92f21d162c411a47fdbeae65640ccc17207a51fbd29
        });
        vm.stopPrank();

        {
            vm.startPrank(foundationMultisig);

            FoundationRewardKernel.TokenAndAmount[] memory taa = new FoundationRewardKernel.TokenAndAmount[](1);
            taa[0] = FoundationRewardKernel.TokenAndAmount({
                token: address(0xe010ec500720bE9EF3F82129E7eD2Ee1FB7955F2),
                amount: 276838997349
            });
            rewardKernel.postPayoutRoot(0x6f7d5e8e9d2a8c3bbef76be6a72dc6d8d5e11e47428a69b6ec8ff0d4364cd69d, taa);
            vm.stopPrank();
        }

        //warp 2 weeks for finality
        vm.warp(block.timestamp + 2 weeks + 1);

        /*
    {
            "leaf": "0xf362da47d7ba8c6f11e7e6ad703b747d32f949267293d655576c41feedad9e98",
            "user": "0x2e2771032d119fe590fd65061ad3b366c8e9b7b9",
            "glowInflationEarned": "2408995249659971824800",
            "glowInflationEarnedLeafWeight": "2408995249659971",
            "onchainAssetsEarned": [
                {
                    "asset": "USDG",
                    "assetAddress": "0xe010ec500720bE9EF3F82129E7eD2Ee1FB7955F2",
                    "amount": "297867047"
                }
            ],
            "offchainAssetsEarned": [],
            "v1MerkleProof": [
                "0x1405f9be2b959fcab323dc62164500084520cc8e6ed82fe0baf1e20b8b858c25",
                "0xa5a8e32c228a9c51cf2621923c756136f0bf0ac31fa3bfc14f147e2130cf54f3",
                "0x30fc4928b3696f02a7b9fe5381cf030a7adeb2e15c8c960dfdd820ed7797783c",
                "0xe49fdbcabc6f4a3ed7c3d661ac7d3b06e1cfc78301f2d2b22d6143f47404579c",
                "0x82de68c60be490f8c63bdd0eb053007fd11d327ef426e6a2be469a636388f258",
                "0xc6573b42a4af137a8817a4a178171b7710d113a454f1f37fe3811955c1877d52",
                "0xf8c9fc50fb64059211504348211d5749e23e2b927924ee2349f111b526d0fb09"
            ],
            "v2MerkleProof": [
                "0x64b1178c4d5e218b4893308b301487790bfaa1ea626f61df1f594fe9e806f435",
                "0x25c3479d9d65fa3b1b19f061b188e5d8637909b531efdf4fc6db511c57f77fb4",
                "0x5406268587265e4df598440d38b004aacc799158a656dbb06428b5d83a9a2bd2",
                "0xf4d273a000c7f0c801ea9f47074e95da65402b15565c1650e3ba884be3e531f9",
                "0x8cac30c1e10362294811fc61361f60b515d0d0ed730eac06c7aac69d701ba888",
                "0x51dcc3add87374c82a2e9966af5b9d66708aa95891dbc84118ff5ea45ad65ea5",
                "0x304f0eb980d2bca44a193e3d404376291af751ba767a6fa988693bbb9b216155"
            ]
        },
            */

        vm.prank(USDC_SAFE);
        // Safe sends USDC to randomUser so they can swap to USDG, let's just do 500,000 for now
        //  vm.etch(USDC_SAFE, "");
        usdc.transfer(randomUser, 500_000 * 10 ** 6);

        vm.startPrank(randomUser);
        usdc.approve(address(usdg), 500_000 * 10 ** 6);
        usdg.swap(randomUser, 500_000 * 10 ** 6);

        // approve cfh factory to spend USDG
        usdg.approve(address(cfhFactory), 500_000 * 10 ** 6);

        //transfer to the protocol deposit holder's cfh
        cfhFactory.transferToCFH(protocolDepositHolder, address(usdg), 500_000 * 10 ** 6);

        vm.stopPrank();

        vm.prank(protocolDepositHolder);
        cfhFactory.setApprovalStatus(address(rewardKernel), true);

        uint256 nonce = rewardKernel.$nextPostNonce() - 1;
        bytes32[] memory v1Proof = new bytes32[](7);
        v1Proof[0] = 0x1405f9be2b959fcab323dc62164500084520cc8e6ed82fe0baf1e20b8b858c25;
        v1Proof[1] = 0xa5a8e32c228a9c51cf2621923c756136f0bf0ac31fa3bfc14f147e2130cf54f3;
        v1Proof[2] = 0x30fc4928b3696f02a7b9fe5381cf030a7adeb2e15c8c960dfdd820ed7797783c;
        v1Proof[3] = 0xe49fdbcabc6f4a3ed7c3d661ac7d3b06e1cfc78301f2d2b22d6143f47404579c;
        v1Proof[4] = 0x82de68c60be490f8c63bdd0eb053007fd11d327ef426e6a2be469a636388f258;
        v1Proof[5] = 0xc6573b42a4af137a8817a4a178171b7710d113a454f1f37fe3811955c1877d52;
        v1Proof[6] = 0xf8c9fc50fb64059211504348211d5749e23e2b927924ee2349f111b526d0fb09;

        bytes32[] memory v2Proof = new bytes32[](7);
        v2Proof[0] = 0x64b1178c4d5e218b4893308b301487790bfaa1ea626f61df1f594fe9e806f435;
        v2Proof[1] = 0x25c3479d9d65fa3b1b19f061b188e5d8637909b531efdf4fc6db511c57f77fb4;
        v2Proof[2] = 0x5406268587265e4df598440d38b004aacc799158a656dbb06428b5d83a9a2bd2;
        v2Proof[3] = 0xf4d273a000c7f0c801ea9f47074e95da65402b15565c1650e3ba884be3e531f9;
        v2Proof[4] = 0x8cac30c1e10362294811fc61361f60b515d0d0ed730eac06c7aac69d701ba888;
        v2Proof[5] = 0x51dcc3add87374c82a2e9966af5b9d66708aa95891dbc84118ff5ea45ad65ea5;
        v2Proof[6] = 0x304f0eb980d2bca44a193e3d404376291af751ba767a6fa988693bbb9b216155;

        address user = 0x2e2771032d119fe590FD65061Ad3B366C8e9B7b9;
        FoundationRewardKernel.TokenAndAmount[] memory taa = new FoundationRewardKernel.TokenAndAmount[](1);
        taa[0] = FoundationRewardKernel.TokenAndAmount({
            token: address(0xe010ec500720bE9EF3F82129E7eD2Ee1FB7955F2),
            amount: 297867047
        });
        bool[] memory isGuarded = new bool[](1);
        isGuarded[0] = true;
        bool[] memory toCounterfactual = new bool[](1);
        toCounterfactual[0] = false;

        (bytes32 root,,) = rewardKernel.getRewardMeta(nonce);
        assertNotEq(root, bytes32(0), "Root is 0");

        uint256 usdgBalanceBefore = usdg.balanceOf(user);
        vm.startPrank(user);
        rewardKernel.claimPayout({
            nonce: nonce,
            proof: v2Proof,
            taa: taa,
            from: protocolDepositHolder,
            to: user,
            isGuardedToken: isGuarded,
            toCounterfactual: toCounterfactual
        });
        uint256 usdgBalanceAfter = usdg.balanceOf(user);
        assertEq(usdgBalanceAfter - usdgBalanceBefore, 297867047, "USDG balance is not correct");

        // Now claim from v1 glow
        uint256 glowBalanceBefore = glow.balanceOf(user);
        minerPool.claimRewardFromBucket({
            bucketId: 96,
            glwWeight: 2408995249659971,
            usdcWeight: 0,
            proof: v1Proof,
            index: 0,
            user: user,
            claimFromInflation: true,
            signature: bytes("")
        });
        uint256 glowBalanceAfter = glow.balanceOf(user);
        console2.log("glowBalanceBefore", glowBalanceBefore);
        console2.log("glowBalanceAfter", glowBalanceAfter);
        assertGt(glowBalanceAfter, glowBalanceBefore, "Glow balance is not correct");
        vm.stopPrank();
    }
}
