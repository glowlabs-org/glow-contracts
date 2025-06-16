// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.17;

// import "forge-std/Script.sol";
// import "forge-std/console.sol";
// // import {GCC} from "@glow/GCC.sol";
// // import {TestGLOW} from "@glow/testing/TestGLOW.sol";
// // import {GoerliGovernanceQuickPeriod} from "@glow/testing/Goerli/GoerliGovernance.QuickPeriod.sol";
// // import {GoerliGCC} from "@glow/testing/Goerli/GoerliGCC.sol";
// // import {MockUSDC} from "@glow/testing/MockUSDC.sol";
// // import {EarlyLiquidity} from "@glow/EarlyLiquidity.sol";
// // import {IUniswapRouterV2} from "@glow/interfaces/IUniswapRouterV2.sol";
// // import {CarbonCreditDutchAuction} from "@glow/CarbonCreditDutchAuction.sol";
// // import {GoerliMinerPoolAndGCAQuickPeriod} from "@glow/testing/Goerli/GoerliMinerPoolAndGCA.QuickPeriod.sol";
// // import {VetoCouncil} from "@glow/VetoCouncil.sol";
// // import {HoldingContract} from "@glow/HoldingContract.sol";
// // import {GrantsTreasury} from "@glow/GrantsTreasury.sol";
// // import {BatchCommit} from "@glow/BatchCommit.sol";
// import "forge-std/Test.sol";

// contract Debug2 is Test {
//     string goerliForkUrl = vm.envString("GOERLI_RPC_URL");
//     uint256 goerliFork;
//     address me = 0xD509A9480559337e924C764071009D60aaCA623d;
//     address minerPoolGoerli = 0xa2126e06AF1C75686BCBAbb4cD426bE35aEECC0C;

//     function setUp() public {
//         goerliFork = vm.createFork(goerliForkUrl);
//         vm.selectFork(goerliFork);
//     }

//     function test_goerliClaimBucket_debug() public {
//         vm.startPrank(me);
//         bytes memory data =
//             hex"d004f0f7000000000000000000000000d509a9480559337e924c764071009d60aaca623d00000000000000000000000000000000000000000000000000000000000f4240";
//         address to = 0x7734720e7Cea67b29f53800C4aD5C40e61aBb645;

//              (bool success, bytes memory returnData) = address(to).call(data);
//         if(!success) {
//            assembly {
//                 revert(add(returnData, 0x20), mload(returnData))
//            }
//         }
//         vm.stopPrank();
//     }
// }
