// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.17;

// import "forge-std/Script.sol";
// import "forge-std/console.sol";
// import {GCC} from "@/GCC.sol";
// import {TestGLOW} from "@/testing/TestGLOW.sol";
// import {Governance} from "@/Governance.sol";
// import {GoerliGCC} from "@/testing/Goerli/GoerliGCC.sol";
// import {MockUSDC} from "@/testing/MockUSDC.sol";
// import {EarlyLiquidity} from "@/EarlyLiquidity.sol";
// import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
// import {CarbonCreditDescendingPriceAuction} from "@/CarbonCreditDescendingPriceAuction.sol";
// import {GoerliMinerPoolAndGCAQuickPeriod} from "@/testing/Goerli/GoerliMinerPoolAndGCA.QuickPeriod.sol";
// import {VetoCouncil} from "@/VetoCouncil/VetoCouncil.sol";
// import {SafetyDelay} from "@/SafetyDelay.sol";
// import {GrantsTreasury} from "@/GrantsTreasury.sol";
// import {BatchCommit} from "@/BatchCommit.sol";
// import {MinerPoolAndGCA} from "@/MinerPoolAndGCA/MinerPoolAndGCA.sol";
// import {USDG} from "@/USDG.sol";
// import "forge-std/Test.sol";

// string constant fileToWriteTo = "deployedContractsGoerli.json";

// contract DebugClaimRewards is Test {
//     string mainnetForkUrl = vm.envString("MAINNET_RPC");
//     uint256 mainnetFork;
//     MinerPoolAndGCA minerPool = MinerPoolAndGCA(0x6Fa8C7a89b22bf3212392b778905B12f3dBAF5C4);
//     // vm.etch

//     function setUp() public {
//         mainnetFork = vm.createFork(mainnetForkUrl);
//         vm.selectFork(mainnetFork);
//     }

//     function test_logAmount() public {
//         vm.startPrank(0x2e2771032d119fe590FD65061Ad3B366C8e9B7b9);
//         uint256 glowWeight = 171802632;
//         uint256 usdgWeight = 14658;

//         bytes32[] memory proof = new bytes32[](5);

//         proof[0] = 0x6fb0355b315178fa65587a63e4e7f6bb17fbe2efebbb55f7239b4bba0101d29c;
//         proof[1] = 0x9e3577c97854c57a58d0323888959c0f001d63e2f534c144717659ebd43e756f;
//         proof[2] = 0xb4bc42273cf40712c0c9108736c377c7ebee2d385e183e73aa4392eb884f8013;
//         proof[3] = 0x488746488002ee15b69eacf7802cdfbbeb8ae37b411090dd5728e2b64318869a;
//         proof[4] = 0xcbeee208e643b5899a95fef51f6cb7e2c608c8701c2181037fee40113f406d1a;

//         //Claim
//         minerPool.claimRewardFromBucket(
//             16, glowWeight, usdgWeight, proof, 0, 0x2e2771032d119fe590FD65061Ad3B366C8e9B7b9, true, ""
//         );

//         vm.stopPrank();
//     }
// }
