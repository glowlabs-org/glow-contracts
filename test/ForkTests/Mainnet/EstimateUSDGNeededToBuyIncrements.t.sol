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
// import {MinerPoolAndGCA} from "@/MinerPoolAndGCA/MinerPoolAndGCA.sol";
// import {GrantsTreasury} from "@/GrantsTreasury.sol";
// import {BatchCommit} from "@/BatchCommit.sol";
// import {USDG} from "@/USDG.sol";
// import "forge-std/Test.sol";
// import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// contract EstimateUSDGNeededToBuyIncrements is Test {
//     address glow = 0xf4fbC617A5733EAAF9af08E1Ab816B103388d8B6;
//     EarlyLiquidity earlyLiquidity = EarlyLiquidity(0xD5aBe236d2F2F5D10231c054e078788Ea3447DFc);
//     uint256 incrementsToBuy = 100; // 1 glow
//     uint mainnetFork;
//     string forkUrl = vm.envString("MAINNET_RPC");
//     uint maxLoops = 10_000;

//     function setUp() public {
//         mainnetFork = vm.createFork(forkUrl);
//         vm.selectFork(mainnetFork);
//     }

//     function test_estimateUSDGNeededToBuyIncrements() public {
//         uint256 usdcNeeded = earlyLiquidity.getPrice(10000);
//         console.log("USDG needed to buy 10000 increments: ", usdcNeeded);

//     }

//     function test_whileLoop() public {
//         uint usdgToSpend = 273512534;
//         uint priceForOneIncrement = earlyLiquidity.getPrice(1); //for 1 increment
//         //How much glow can be bought with 2735031 usdg
//         // uint initialGuess
//     }

//     function inRange(uint256 value, uint256 min, uint256 max) public pure returns (bool) {
//         return value >= min && value <= max;
//     }
// }
