/*// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.17;

// import "forge-std/Script.sol";
// import "forge-std/console.sol";
// import {GCC} from "@/GCC.sol";
// import {Glow} from "@/GLOW.sol";
// import {Governance} from "@/Governance.sol";
// import {GCC} from "@/GCC.sol";
// import {EarlyLiquidity} from "@/EarlyLiquidity.sol";
// import {IUniswapRouterV2} from "@/interfaces/IUniswapRouterV2.sol";
// import {CarbonCreditDutchAuction} from "@/CarbonCreditDutchAuction.sol";
// import {MinerPoolAndGCA} from "@/MinerPoolAndGCA/MinerPoolAndGCA.sol";
// import {VetoCouncil} from "@/VetoCouncil.sol";
// import {HoldingContract} from "@/HoldingContract.sol";
// import {GrantsTreasury} from "@/GrantsTreasury.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {BatchCommit} from "@/BatchCommit.sol";
// import "forge-std/console.sol";
// import "forge-std/Test.sol";

// string constant fileToWriteTo = "deployedContractsMainnet.json";

// contract DeployFull is Test, Script {
//     bytes32 gcaRequirementsHash = keccak256("my hash good ser");
//     address vestingContract = tx.origin;

//     EarlyLiquidity earlyLiquidity;
//     MinerPoolAndGCA gcaAndMinerPoolContract;
//     VetoCouncil vetoCouncilContract;
//     HoldingContract holdingContract;
//     GrantsTreasury treasury;
//     address uniswapV2Router = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
//     address usdc = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
//     uint256 amountGCCToLP = 1 ether;
//     uint256 amonutUSDCToLP = 10 * 1e6;

//     function run() external {
//         address[] memory startingAgents = new address[](1);
//         startingAgents[0] = tx.origin;
//         address[] memory startingVetoCouncilAgents = new address[](1);
//         startingVetoCouncilAgents[0] = tx.origin;
//         if (vm.exists(fileToWriteTo)) {
//             vm.removeFile(fileToWriteTo);
//         }

//         vm.startBroadcast();
//         earlyLiquidity = new EarlyLiquidity(usdc, address(holdingContract));
//         Governance governance = new Governance();

//         Glow glow = new Glow(address(earlyLiquidity), vestingContract);
//         vetoCouncilContract = new VetoCouncil(address(glow), address(glow), startingVetoCouncilAgents);
//         holdingContract = new HoldingContract(address(vetoCouncilContract));
//         treasury = new GrantsTreasury(address(glow), address(governance));
//         gcaAndMinerPoolContract = new MinerPoolAndGCA(
//             startingAgents,
//             address(glow),
//             address(governance),
//             gcaRequirementsHash,
//             address(earlyLiquidity),
//             usdc,
//             address(vetoCouncilContract),
//             address(holdingContract)
//         );

//         GCC gcc = new GCC(address(gcaAndMinerPoolContract), address(governance), address(glow), usdc, uniswapV2Router);
//         BatchCommit batchCommit = new BatchCommit(address(gcc), usdc);
//         gcc.approve(uniswapV2Router, amountGCCToLP);
//         IERC20(usdc).approve(uniswapV2Router, amonutUSDCToLP);
//         IUniswapRouterV2(uniswapV2Router).addLiquidity(
//             address(gcc), usdc, amountGCCToLP, amonutUSDCToLP, 0, 0, tx.origin, block.timestamp + 1 days
//         );
//         governance.setContractAddresses(
//             address(gcc),
//             address(gcaAndMinerPoolContract),
//             address(vetoCouncilContract),
//             address(treasury),
//             address(glow)
//         );
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
//             string(abi.encodePacked(jsonStringOutput, "\"usdc\":", "\"", vm.toString(address(usdc)), "\"", ","));
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
// }*/
