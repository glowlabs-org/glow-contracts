// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.17;

// import "forge-std/Script.sol";
// import "forge-std/console.sol";
// import {GCC} from "@/GCC.sol";
// import {TestGLOW} from "@/testing/TestGLOW.sol";
// import {GoerliGovernanceQuickPeriod} from "@/testing/Goerli/GoerliGovernance.QuickPeriod.sol";
// import {GoerliGCC} from "@/testing/Goerli/GoerliGCC.sol";
// import {MockUSDC} from "@/testing/MockUSDC.sol";
// import {EarlyLiquidity} from "@/EarlyLiquidity.sol";
// import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
// import {GoerliMinerPoolAndGCAQuickPeriod} from "@/testing/Goerli/GoerliMinerPoolAndGCA.QuickPeriod.sol";
// import {VetoCouncil} from "@/VetoCouncil/VetoCouncil.sol";
// import {SafetyDelay} from "@/SafetyDelay.sol";
// import {GrantsTreasury} from "@/GrantsTreasury.sol";
// import {BatchCommit} from "@/BatchCommit.sol";
// import "forge-std/Test.sol";

// string constant fileToWriteTo = "simon.txt";

// contract DeployFullQuickBuckets is Test {
//     bytes32 gcaRequirementsHash = keccak256("my hash good ser");
//     address vestingContract = address(0xE414D49268837291fde21c33AD7e30233b7041C2);

//     address testingOther = 0x1c42C3DC7502aE55Ec4a888a940b2ADB0901a604;
//     MockUSDC mockUSDC;
//     EarlyLiquidity earlyLiquidity;
//     GoerliMinerPoolAndGCAQuickPeriod gcaAndMinerPoolContract;
//     VetoCouncil vetoCouncilContract;
//     SafetyDelay holdingContract;
//     GrantsTreasury treasury;
//     address uniswapV2Router = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
//     string goerliUrl = vm.envString("GOERLI_RPC_URL");
//     uint256 goerliFork;
//     address deployer = 0xD509A9480559337e924C764071009D60aaCA623d;
//     //TODO: make sure that this isnt mainnet deployer

//     function setUp() public {
//         goerliFork = vm.createFork(goerliUrl);
//         vm.selectFork(goerliFork);
//     }

//     function test_precompute_goerli() external {
//         vm.startPrank(deployer);
//         if (vm.exists(fileToWriteTo)) {
//             vm.removeFile(fileToWriteTo);
//         }

//         uint256 deployerNonce = vm.getNonce(deployer) + 4; //add nonce for mock usdc
//         address precomputedMinerPool = computeCreateAddress(deployer, deployerNonce + 7);
//         address precomputedGlow = computeCreateAddress(deployer, deployerNonce + 1);
//         address precomputedEarlyLiquidity = computeCreateAddress(deployer, deployerNonce + 2);
//         address precomputedGovernance = computeCreateAddress(deployer, deployerNonce + 3);
//         address precomputedVetoCouncil = computeCreateAddress(deployer, deployerNonce + 4);
//         address precomputedGrants = computeCreateAddress(deployer, deployerNonce + 6);
//         address precomputedHoldingContract = computeCreateAddress(deployer, deployerNonce + 5);

//         string memory output;

//         output = string(abi.encodePacked("address precomputedMinerPool = ", vm.toString(precomputedMinerPool), ";\n"));

//         output = string(abi.encodePacked(output, "address precomputedGlow = ", vm.toString(precomputedGlow), ";\n"));

//         output = string(
//             abi.encodePacked(
//                 output, "address precomputedEarlyLiquidity = ", vm.toString(precomputedEarlyLiquidity), ";\n"
//             )
//         );

//         output = string(
//             abi.encodePacked(output, "address precomputedGovernance = ", vm.toString(precomputedGovernance), ";\n")
//         );

//         output = string(
//             abi.encodePacked(output, "address precomputedVetoCouncil = ", vm.toString(precomputedVetoCouncil), ";\n")
//         );

//         output = string(abi.encodePacked(output, "address precomputedGrants = ", vm.toString(precomputedGrants), ";\n"));

//         output = string(
//             abi.encodePacked(
//                 output, "address precomputedHoldingContract = ", vm.toString(precomputedHoldingContract), ";\n"
//             )
//         );

//         vm.writeFile(fileToWriteTo, output);
//         vm.stopPrank();
//     }
// }
