// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.17;

// import "forge-std/Script.sol";
// import "forge-std/console.sol";
// import {GoerliGlowGuardedLaunch} from "@/testing/GuardedLaunch/GoerliGLOW.GuardedLaunch.sol";
// import {Governance} from "@/Governance.sol";
// import {GoerliGCCGuardedLaunch} from "@/testing/GuardedLaunch/GoerliGCC.GuardedLaunch.sol";
// import {MockUSDC} from "@/testing/MockUSDC.sol";
// import {EarlyLiquidity} from "@/EarlyLiquidity.sol";
// import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
// import {CarbonCreditDutchAuction} from "@/CarbonCreditDutchAuction.sol";
// import {MinerPoolAndGCA} from "@/MinerPoolAndGCA/MinerPoolAndGCA.sol";
// import {VetoCouncil} from "@/VetoCouncil.sol";
// import {HoldingContract} from "@/HoldingContract.sol";
// import {GrantsTreasury} from "@/GrantsTreasury.sol";
// import {BatchCommit} from "@/BatchCommit.sol";
// import "forge-std/Test.sol";
// import {USDG} from "@/USDG.sol";

// string constant fileToWriteTo = "deployedContractsGoerli.json";

// contract DeployFull is Test, Script {
//     bytes32 gcaRequirementsHash = keccak256("my hash good ser");
//     address vestingContract = address(0xE414D49268837291fde21c33AD7e30233b7041C2);

//     MockUSDC mockUSDC;
//     EarlyLiquidity earlyLiquidity;
//     MinerPoolAndGCA gcaAndMinerPoolContract;
//     VetoCouncil vetoCouncilContract;
//     HoldingContract holdingContract;
//     GrantsTreasury treasury;
//     USDG usdg;
//     address uniswapV2Router = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
//     address uniswapV2Factory = address(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);
//     address usdcReceiver = address(0xfdafafdafafa124412f);

//     function run() external {
//         if (usdcReceiver == tx.origin) {
//             revert("set usdcReceiver to not be tx.origin");
//         }
//         address[] memory startingAgents = new address[](1);
//         startingAgents[0] = tx.origin;
//         address[] memory startingVetoCouncilAgents = new address[](1);
//         startingVetoCouncilAgents[0] = tx.origin;
//         if (vm.exists(fileToWriteTo)) {
//             vm.removeFile(fileToWriteTo);
//         }

//         vm.startBroadcast();
//         address usdgOwner = tx.origin;
//         mockUSDC = new MockUSDC();
//         usdg = new USDG({
//             _usdc: address(mockUSDC),
//             _usdcReceiver: usdcReceiver,
//             _owner: usdgOwner,
//             _univ2Factory: uniswapV2Factory
//         });

//         mockUSDC.mint(tx.origin, 1000000 * 1e6);
//         mockUSDC.approve(address(usdg), 1000000 * 1e6);
//         usdg.swap(tx.origin, 1000000 * 1e6);
//         earlyLiquidity = new EarlyLiquidity(address(usdg), address(holdingContract));
//         Governance governance = new Governance();

//         GoerliGlowGuardedLaunch glow = new GoerliGlowGuardedLaunch({
//             _earlyLiquidityAddress: address(earlyLiquidity),
//             _vestingContract: vestingContract,
//             _owner: tx.origin,
//             _usdg: address(usdg),
//             _uniswapV2Factory: uniswapV2Factory
//         });

//         vetoCouncilContract = new VetoCouncil(address(glow), address(glow), startingVetoCouncilAgents);
//         holdingContract = new HoldingContract(address(vetoCouncilContract));
//         treasury = new GrantsTreasury(address(glow), address(governance));
//         gcaAndMinerPoolContract = new MinerPoolAndGCA(
//             startingAgents,
//             address(glow),
//             address(governance),
//             gcaRequirementsHash,
//             address(earlyLiquidity),
//             address(usdg),
//             address(vetoCouncilContract),
//             address(holdingContract)
//         );

//         glow.mint(tx.origin, 100 ether);
//         GoerliGCCGuardedLaunch gcc = new GoerliGCCGuardedLaunch({
//             _gcaAndMinerPoolContract: address(gcaAndMinerPoolContract),
//             _governance: address(governance),
//             _glowToken: address(glow),
//             _usdg: address(usdg),
//             _vetoCouncilAddress: address(vetoCouncilContract),
//             _uniswapRouter: uniswapV2Router,
//             _uniswapFactory: uniswapV2Factory
//         });
//         gcc.allowlistPostConstructionContracts();
//         gcaAndMinerPoolContract.setGCC(address(gcc));

//         //TODO: make sure this is taken care of
//         // glow.setContractAddresses(address(gcaAndMinerPoolContract), address(vetoCouncilContract), address(treasury));
//         BatchCommit batchCommit = new BatchCommit(address(gcc), address(usdg));
//         gcc.mint(tx.origin, 1000 ether);
//         gcc.approve(uniswapV2Router, 100 ether);
//         usdg.approve(uniswapV2Router, 20000 * 1e6);
//         // usdg.setAllowlistedContracts({
//         //     _glow: address(glow),
//         //     _gcc: address(gcc),
//         //     _holdingContract: address(holdingContract),
//         //     _vetoCouncilContract: address(vetoCouncilContract),
//         //     _impactCatalyst: address(gcc.IMPACT_CATALYST())
//         // });
//         IUniswapRouterV2(uniswapV2Router).addLiquidity(
//             address(gcc), address(usdg), 100 ether, 2000 * 1e6, 0, 0, tx.origin, block.timestamp + 1 days
//         );
//         governance.setContractAddresses(
//             address(gcc),
//             address(gcaAndMinerPoolContract),
//             address(vetoCouncilContract),
//             address(treasury),
//             address(glow)
//         );

//         gcc.approve(tx.origin, 100 ether);
//         gcc.commitGCC(5 ether, tx.origin, 0);
//         uint256 nextNominationCost = governance.costForNewProposal();
//         governance.createChangeGCARequirementsProposal(keccak256("new requiremenents hash"), nextNominationCost);
//         nextNominationCost = governance.costForNewProposal();
//         governance.createVetoCouncilElectionOrSlash(address(0x444), address(0x123), true, nextNominationCost);
//         vm.stopBroadcast();
//         string memory jsonStringOutput = string("{");
//         jsonStringOutput = string(
//             abi.encodePacked(
//                 jsonStringOutput, "\"earlyLiquidity\":", "\"", vm.toString(address(earlyLiquidity)), "\"", ","
//             )
//         );
//         jsonStringOutput = string(
//             abi.encodePacked(jsonStringOutput, "\"governance\":", "\"", vm.toString(address(governance)), "\"", ",")
//         );
//         jsonStringOutput =
//             string(abi.encodePacked(jsonStringOutput, "\"glow\":", "\"", vm.toString(address(glow)), "\"", ","));
//         jsonStringOutput = string(
//             abi.encodePacked(
//                 jsonStringOutput, "\"vetoCouncilContract\":", "\"", vm.toString(address(vetoCouncilContract)), "\"", ","
//             )
//         );
//         jsonStringOutput = string(
//             abi.encodePacked(
//                 jsonStringOutput, "\"holdingContract\":", "\"", vm.toString(address(holdingContract)), "\"", ","
//             )
//         );
//         jsonStringOutput = string(
//             abi.encodePacked(jsonStringOutput, "\"grantsTreasury\":", "\"", vm.toString(address(treasury)), "\"", ",")
//         );
//         jsonStringOutput = string(
//             abi.encodePacked(
//                 jsonStringOutput,
//                 "\"gcaAndMinerPoolContract\":",
//                 "\"",
//                 vm.toString(address(gcaAndMinerPoolContract)),
//                 "\"",
//                 ","
//             )
//         );
//         jsonStringOutput =
//             string(abi.encodePacked(jsonStringOutput, "\"gcc\":", "\"", vm.toString(address(gcc)), "\"", ","));
//         jsonStringOutput = string(
//             abi.encodePacked(jsonStringOutput, "\"batchCommit\":", "\"", vm.toString(address(batchCommit)), "\"", ",")
//         );

//         jsonStringOutput =
//             string(abi.encodePacked(jsonStringOutput, "\"usdc\":", "\"", vm.toString(address(mockUSDC)), "\"", ","));
//         jsonStringOutput =
//             string(abi.encodePacked(jsonStringOutput, "\"usdg\":", "\"", vm.toString(address(usdg)), "\"", ","));
//         jsonStringOutput = string(
//             abi.encodePacked(
//                 jsonStringOutput, "\"impactCatalyst\":", "\"", vm.toString(address(gcc.IMPACT_CATALYST())), "\"", ","
//             )
//         );
//         jsonStringOutput = string(
//             abi.encodePacked(
//                 jsonStringOutput,
//                 "\"carbonCreditAuction\":",
//                 "\"",
//                 vm.toString(address(gcc.CARBON_CREDIT_AUCTION())),
//                 "\""
//             )
//         );

//         jsonStringOutput = string(abi.encodePacked(jsonStringOutput, "}"));

//         vm.writeFile(fileToWriteTo, jsonStringOutput);
//     }
// }
