// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.17;

// import "forge-std/Script.sol";
// import "forge-std/console.sol";
// // import {GCC} from "@/GCC.sol";
// // import {TestGLOW} from "@/testing/TestGLOW.sol";
// // import {GoerliGovernanceQuickPeriod} from "@/testing/Goerli/GoerliGovernance.QuickPeriod.sol";
// // import {GoerliGCC} from "@/testing/Goerli/GoerliGCC.sol";
// // import {MockUSDC} from "@/testing/MockUSDC.sol";
// // import {EarlyLiquidity} from "@/EarlyLiquidity.sol";
// // import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
// // import {CarbonCreditDutchAuction} from "@/CarbonCreditDutchAuction.sol";
// // import {GoerliMinerPoolAndGCAQuickPeriod} from "@/testing/Goerli/GoerliMinerPoolAndGCA.QuickPeriod.sol";
// // import {VetoCouncil} from "@/VetoCouncil.sol";
// // import {HoldingContract} from "@/HoldingContract.sol";
// // import {GrantsTreasury} from "@/GrantsTreasury.sol";
// // import {BatchCommit} from "@/BatchCommit.sol";
// import {MinerPoolAndGCA} from "@/MinerPoolAndGCA/MinerPoolAndGCA.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {SafetyDelay} from "@/SafetyDelay.sol";
// import "forge-std/Test.sol";

// contract Debug2 is Test {
//     string mainnetForkUrl = vm.envString("MAINNET_RPC");
//     uint256 mainnetFork;
//     address gca = 0xB2d687b199ee40e6113CD490455cC81eC325C496;
//     address farm = 0xD8E3164744916b8c0D1d6cc01ad82F76ec94058e;
//     MinerPoolAndGCA minerPoolAndGCA = MinerPoolAndGCA(0x6Fa8C7a89b22bf3212392b778905B12f3dBAF5C4);
//     SafetyDelay safetyDelay = SafetyDelay(0xd5970622b740a2eA5A5574616c193968b10e1297);
//     address usdg = 0xe010ec500720bE9EF3F82129E7eD2Ee1FB7955F2;
//     IERC20 glow = IERC20(0xf4fbC617A5733EAAF9af08E1Ab816B103388d8B6);

//     function setUp() public {
//         mainnetFork = vm.createFork(mainnetForkUrl);
//         vm.selectFork(mainnetFork);
//     }

//     // function testForkChangeGCAs() public {
//     //     address[] memory gcasToSlash = new address[](0);
//     //     address[] memory newGCAs = new address[](2);
//     //     newGCAs[0] = 0xB2d687b199ee40e6113CD490455cC81eC325C496;
//     //     newGCAs[1] = 0x63a74612274FbC6ca3f7096586aF01Fd986d69cE;
//     //     uint256 proposalCreationTimestamp = 1713556415;
//     //     minerPoolAndGCA.executeAgainstHash(gcasToSlash, newGCAs, proposalCreationTimestamp);
//     // }

//     function test_claimWeek41() public {
//         vm.startPrank(farm);
//         vm.warp(block.timestamp + 2 weeks);

//         bytes32[] memory proof = new bytes32[](6);
//         //         "glowWeight": "26248982812",
//         // "usdgWeight": "6142286",
//         // "proof": [
//         //     "0xd56e6a70daa9bf57dc57cc2e5ecd0727953d9ef50a4867bb6d580e97e6e47423",
//         //     "0x4480acfe49590a641e719f06526c14cf9064169b51492db75b1a33769dc43a46",
//         //     "0x005a06740b8d79b86b11765c372ed71d8fbb694731dca7156b835a5569a1c587",
//         //     "0xc8c9c4b4f4a8ee9c91fcba8d30badfc1421ce682edbbc606f9f104a615fd53a1",
//         //     "0x2811a7a18fb881649044340cd2bf74dc00215f4d22aaa67cb6486d12bca021e3",
//         //     "0xfb73ca718ae1fe8b1def6f0a230a6813f0cd654de5f24756e851797ad0984509"
//         // ]
//         proof[0] = bytes32(0xd56e6a70daa9bf57dc57cc2e5ecd0727953d9ef50a4867bb6d580e97e6e47423);
//         proof[1] = bytes32(0x4480acfe49590a641e719f06526c14cf9064169b51492db75b1a33769dc43a46);
//         proof[2] = bytes32(0x005a06740b8d79b86b11765c372ed71d8fbb694731dca7156b835a5569a1c587);
//         proof[3] = bytes32(0xc8c9c4b4f4a8ee9c91fcba8d30badfc1421ce682edbbc606f9f104a615fd53a1);
//         proof[4] = bytes32(0x2811a7a18fb881649044340cd2bf74dc00215f4d22aaa67cb6486d12bca021e3);
//         proof[5] = bytes32(0xfb73ca718ae1fe8b1def6f0a230a6813f0cd654de5f24756e851797ad0984509);

//         uint256 farmGlowWeight = 26248982812;
//         uint256 farmUsdgWeight = 6142286;
//         uint256 farmSafetyDelayAmountBefore = safetyDelay.holdings(farm, usdg).amount;
//         uint256 glowBefore = glow.balanceOf(farm);

//         minerPoolAndGCA.claimRewardFromBucket({
//             bucketId: 41,
//             glwWeight: farmGlowWeight,
//             usdcWeight: farmUsdgWeight,
//             proof: proof,
//             index: 0,
//             user: farm,
//             claimFromInflation: false,
//             signature: ""
//         });

//         uint256 farmSafetyDelayAmountAfter = safetyDelay.holdings(farm, usdg).amount;
//         uint256 glowAfter = glow.balanceOf(farm);

//         //Log the diff between the usdg and the glow
//         console.log("glow diff", glowAfter - glowBefore);
//         console.log("usdg diff", farmSafetyDelayAmountAfter - farmSafetyDelayAmountBefore);
//         vm.stopPrank();
//     }
// }
