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
// import {CarbonCreditDutchAuction} from "@/CarbonCreditDutchAuction.sol";
// import {GoerliMinerPoolAndGCAQuickPeriod} from "@/testing/Goerli/GoerliMinerPoolAndGCA.QuickPeriod.sol";
// import {VetoCouncil} from "@/VetoCouncil.sol";
// import {HoldingContract} from "@/HoldingContract.sol";
// import {GrantsTreasury} from "@/GrantsTreasury.sol";
// import {BatchCommit} from "@/BatchCommit.sol";
// import "forge-std/Test.sol";

// string constant fileToWriteTo = "deployedContractsGoerli.json";

// contract DeployGoerliQuickBuckets is Test {
//     bytes32 gcaRequirementsHash = keccak256("my hash good ser");
//     address vestingContract = address(0xE414D49268837291fde21c33AD7e30233b7041C2);

//     address testingOther = 0x1c42C3DC7502aE55Ec4a888a940b2ADB0901a604;
//     MockUSDC mockUSDC;
//     EarlyLiquidity earlyLiquidity;
//     GoerliMinerPoolAndGCAQuickPeriod gcaAndMinerPoolContract;
//     VetoCouncil vetoCouncilContract;
//     HoldingContract holdingContract;
//     GrantsTreasury treasury;
//     address uniswapV2Router = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

//     string goerliForkUrl = vm.envString("GOERLI_RPC_URL");
//     uint256 goerliFork;

//     address me = 0xD509A9480559337e924C764071009D60aaCA623d;

//     function setUp() public {
//         goerliFork = vm.createFork(goerliForkUrl);
//         vm.selectFork(goerliFork);
//     }

//     function test_deploy_quick_buckets_goerli() external {
//         address[] memory startingAgents = new address[](2);
//         startingAgents[0] = me;
//         startingAgents[1] = testingOther;
//         address[] memory startingVetoCouncilAgents = new address[](2);
//         startingVetoCouncilAgents[0] = tx.origin;
//         startingVetoCouncilAgents[1] = testingOther;
//         if (vm.exists(fileToWriteTo)) {
//             vm.removeFile(fileToWriteTo);
//         }

//         vm.startBroadcast();
//         mockUSDC = new MockUSDC();
//         mockUSDC.mint(tx.origin, 1000000 * 1e6);
//         earlyLiquidity = new EarlyLiquidity(address(mockUSDC), address(holdingContract));
//         GoerliGovernanceQuickPeriod governance = new GoerliGovernanceQuickPeriod();

//         TestGLOW glow = new TestGLOW(address(earlyLiquidity), vestingContract);
//         vetoCouncilContract = new VetoCouncil(address(glow), address(glow), startingVetoCouncilAgents);
//         holdingContract = new HoldingContract(address(vetoCouncilContract));
//         treasury = new GrantsTreasury(address(glow), address(governance));
//         gcaAndMinerPoolContract = new GoerliMinerPoolAndGCAQuickPeriod(
//             startingAgents,
//             address(glow),
//             address(governance),
//             gcaRequirementsHash,
//             address(earlyLiquidity),
//             address(mockUSDC),
//             address(vetoCouncilContract),
//             address(holdingContract)
//         );

//         //TODO: set these addresses
//         // glow.setContractAddresses(address(gcaAndMinerPoolContract), address(vetoCouncilContract), address(treasury));
//         glow.mint(tx.origin, 100 ether);
//         GoerliGCC gcc = new GoerliGCC(
//             address(gcaAndMinerPoolContract), address(governance), address(glow), address(mockUSDC), uniswapV2Router
//         );
//         BatchCommit batchCommit = new BatchCommit(address(gcc), address(mockUSDC));
//         gcc.mint(tx.origin, 1000 ether);
//         gcc.approve(uniswapV2Router, 100 ether);
//         mockUSDC.approve(uniswapV2Router, 20000 * 1e6);
//         IUniswapRouterV2(uniswapV2Router).addLiquidity(
//             address(gcc), address(mockUSDC), 100 ether, 2000 * 1e6, 0, 0, tx.origin, block.timestamp + 1 days
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
//         gcaAndMinerPoolContract.setGCC(address(gcc));

//         //start a prank
//         vm.stopBroadcast();
//         vm.startPrank(startingAgents[0]);
//         uint256 currentTimestamp = block.timestamp;
//         gcaAndMinerPoolContract.submitWeeklyReport({
//             bucketId: 0,
//             totalNewGCC: 100 ether,
//             totalGlwRewardsWeight: 269,
//             totalGRCRewardsWeight: 269,
//             root: bytes32(0xa42f7e89c311e7da19cef65f74f3969933d7cd4be40103a8ea003cbdb52c85be)
//         });

//         //Warp 2 hours
//         vm.warp(block.timestamp + 60 * 120);

//         //Mint some for testing so it doesent have to wait for inflation

//         glow.mint(address(gcaAndMinerPoolContract), 5000000000 ether);
//         bytes32[] memory proof = new bytes32[](0);
//         gcaAndMinerPoolContract.claimRewardFromBucket({
//             bucketId: 0,
//             glwWeight: 269,
//             usdcWeight: 269,
//             proof: proof,
//             index: 0,
//             user: me,
//             claimFromInflation: false,
//             signature: ""
//         });

//         vm.stopPrank();
//     }
// }
